import 'dart:typed_data';

import 'constants.dart';
import 'l3bitstream.dart' as l3bitstream;
import 'l3loop.dart' as l3loop;
import 'l3mdct.dart' as l3mdct;
import 'l3subband.dart' as l3subband;
import 'tables.dart';
import 'types.dart';

/// Enumerates the PCM layouts supported by the encoder.
enum Channels {
  pcmMono(1),
  pcmStereo(2);

  const Channels(this.channelCount);
  final int channelCount;
}

enum MpegVersion {
  mpeg25(0, granulesPerFrame: 1),
  reserved(1, granulesPerFrame: -1),
  mpeg2(2, granulesPerFrame: 1),
  mpeg1(3, granulesPerFrame: 2);

  const MpegVersion(this.value, {required this.granulesPerFrame});

  final int value;
  final int granulesPerFrame;
}

enum MpegLayer {
  layer3(1);

  const MpegLayer(this.value);
  final int value;
}

enum StereoMode {
  stereo(0),
  jointStereo(1),
  dualChannel(2),
  mono(3);

  const StereoMode(this.value);
  final int value;
}

enum Emphasis {
  none(0),
  mu50_15(1),
  citt(3);

  const Emphasis(this.value);
  final int value;
}

/// Public descriptor for the PCM input stream.
class ShineWave {
  ShineWave({this.channels = Channels.pcmStereo, this.samplerate = 44100});

  Channels channels;
  int samplerate;

  int get channelCount => channels.channelCount;
}

/// Public descriptor for the MPEG output stream.
class ShineMpeg {
  ShineMpeg({
    this.mode = StereoMode.stereo,
    this.bitr = 128,
    this.emph = Emphasis.none,
    this.copyright = false,
    this.original = true,
  });

  StereoMode mode;
  int bitr;
  Emphasis emph;
  bool copyright;
  bool original;
}

/// Aggregated configuration passed to [shineInitialise].
class ShineConfig {
  ShineConfig({required this.wave, required this.mpeg});

  final ShineWave wave;
  final ShineMpeg mpeg;
}

/// Alias mirroring the opaque `shine_t` handle in the C implementation.
typedef ShineT = ShineGlobalConfig;

const List<int> _granulesPerFrame = <int>[1, -1, 1, 2];

/// Populates the provided [mpeg] structure with the default values defined in
/// `layer3.c`.
void shineSetConfigMpegDefaults(ShineMpeg mpeg) {
  mpeg
    ..bitr = 128
    ..emph = Emphasis.none
    ..copyright = false
    ..original = true;
}

/// Returns the MPEG version identifier for the provided samplerate index.
int shineMpegVersion(int samplerateIndex) {
  if (samplerateIndex < 3) {
    return 3; // MPEG_I
  } else if (samplerateIndex < 6) {
    return 2; // MPEG_II
  }
  return 0; // MPEG_2.5
}

/// Looks up the samplerate index matching [freq]. Returns -1 if unsupported.
int shineFindSamplerateIndex(int freq) {
  for (int i = 0; i < samplerates.length; i++) {
    if (freq == samplerates[i]) {
      return i;
    }
  }
  return -1;
}

/// Looks up the bitrate index for [bitr] and [mpegVersion]. Returns -1 if
/// unsupported.
int shineFindBitrateIndex(int bitr, int mpegVersion) {
  for (int i = 0; i < bitrates.length; i++) {
    if (bitr == bitrates[i][mpegVersion]) {
      return i;
    }
  }
  return -1;
}

/// Validates the provided [freq] and [bitr] pair, returning the MPEG version on
/// success or `-1` on failure.
int shineCheckConfig(int freq, int bitr) {
  final int samplerateIndex = shineFindSamplerateIndex(freq);
  if (samplerateIndex < 0) {
    return -1;
  }

  final int mpegVersion = shineMpegVersion(samplerateIndex);
  final int bitrateIndex = shineFindBitrateIndex(bitr, mpegVersion);
  if (bitrateIndex < 0) {
    return -1;
  }

  return mpegVersion;
}

/// Returns the number of PCM samples consumed per encoding call.
int shineSamplesPerPass(ShineT handle) {
  return handle.mpeg.granules_per_frame * granuleSize;
}

/// Allocates and initialises the encoder state using [pubConfig]. Returns
/// `null` if the configuration is invalid.
ShineT? shineInitialise(ShineConfig pubConfig) {
  if (shineCheckConfig(pubConfig.wave.samplerate, pubConfig.mpeg.bitr) < 0) {
    return null;
  }

  final PrivShineWave wave = PrivShineWave(
    channels: pubConfig.wave.channelCount,
    samplerate: pubConfig.wave.samplerate,
  );
  final PrivShineMpeg mpeg = PrivShineMpeg()
    ..mode = pubConfig.mpeg.mode.value
    ..bitr = pubConfig.mpeg.bitr
    ..emph = pubConfig.mpeg.emph.value
    ..copyright = pubConfig.mpeg.copyright ? 1 : 0
    ..original = pubConfig.mpeg.original ? 1 : 0
    ..layer = MpegLayer.layer3.value
    ..bits_per_slot = 8
    ..crc = 0
    ..ext = 0
    ..mode_ext = 0;

  final ShineGlobalConfig config = ShineGlobalConfig(wave: wave, mpeg: mpeg);

  l3subband.shineSubbandInitialise(config);
  l3mdct.shineMdctInitialise(config);
  l3loop.shineLoopInitialise(config);

  mpeg.samplerate_index = shineFindSamplerateIndex(wave.samplerate);
  mpeg.version = shineMpegVersion(mpeg.samplerate_index);
  mpeg.bitrate_index = shineFindBitrateIndex(mpeg.bitr, mpeg.version);
  mpeg.granules_per_frame = _granulesPerFrame[mpeg.version];

  final double avgSlotsPerFrame =
      (mpeg.granules_per_frame * granuleSize / wave.samplerate) *
          (1000.0 * mpeg.bitr / mpeg.bits_per_slot);
  mpeg.whole_slots_per_frame = avgSlotsPerFrame.floor();
  mpeg.frac_slots_per_frame =
      avgSlotsPerFrame - mpeg.whole_slots_per_frame.toDouble();
  mpeg.slot_lag = -mpeg.frac_slots_per_frame;

  if (mpeg.frac_slots_per_frame == 0) {
    mpeg.padding = 0;
  }

  config.bs.reset();
  config.side_info.reset();

  if (mpeg.granules_per_frame == 2) {
    config.sideinfo_len =
        8 * ((wave.channels == 1) ? 4 + 17 : 4 + 32);
  } else {
    config.sideinfo_len =
        8 * ((wave.channels == 1) ? 4 + 9 : 4 + 17);
  }

  return config;
}

/// Encapsulates the encoded output buffer and the number of valid bytes.
class ShineEncodeResult {
  ShineEncodeResult(this.buffer, this.length);

  final Uint8List buffer;
  final int length;
}

ShineEncodeResult _encodeInternal(ShineT config, int stride) {
  final PrivShineMpeg mpeg = config.mpeg;

  if (mpeg.frac_slots_per_frame != 0) {
    mpeg.padding =
        (mpeg.slot_lag <= (mpeg.frac_slots_per_frame - 1.0)) ? 1 : 0;
    mpeg.slot_lag += mpeg.padding - mpeg.frac_slots_per_frame;
  }

  mpeg.bits_per_frame =
      8 * (mpeg.whole_slots_per_frame + mpeg.padding);
  config.mean_bits =
      (mpeg.bits_per_frame - config.sideinfo_len) ~/ mpeg.granules_per_frame;

  l3mdct.shineMdctSub(config, stride);
  l3loop.shineIterationLoop(config);
  l3bitstream.shineFormatBitstream(config);

  final int written = config.bs.dataPosition;
  final Uint8List view = Uint8List.sublistView(config.bs.data, 0, written);
  config.bs.reset();
  return ShineEncodeResult(view, written);
}

ShineEncodeResult shineEncodeBuffer(ShineT config, List<Int16List> data) {
  if (data.isEmpty || data.length < config.wave.channels) {
    throw ArgumentError('PCM buffer does not contain the expected channels');
  }

  final int expectedSamples = shineSamplesPerPass(config);
  for (int ch = 0; ch < config.wave.channels; ch++) {
    final Int16List channelData = data[ch];
    if (channelData.length < expectedSamples) {
      throw ArgumentError('Channel $ch has ${channelData.length} samples, '
          'expected at least $expectedSamples');
    }
    config.buffer[ch] = PcmPointer(channelData, 0);
  }
  for (int ch = config.wave.channels; ch < config.buffer.length; ch++) {
    config.buffer[ch] = null;
  }

  return _encodeInternal(config, 1);
}

ShineEncodeResult shineEncodeBufferInterleaved(
    ShineT config, Int16List data) {
  final int expectedSamples = shineSamplesPerPass(config) * config.wave.channels;
  if (data.length < expectedSamples) {
    throw ArgumentError('Interleaved buffer has ${data.length} samples, '
        'expected at least $expectedSamples');
  }

  config.buffer[0] = PcmPointer(data, 0);
  if (config.wave.channels == 2) {
    config.buffer[1] = PcmPointer(data, 1);
  }
  for (int ch = config.wave.channels; ch < config.buffer.length; ch++) {
    config.buffer[ch] = null;
  }
  return _encodeInternal(config, config.wave.channels);
}

ShineEncodeResult shineFlush(ShineT config) {
  final int written = config.bs.dataPosition;
  final Uint8List view = Uint8List.sublistView(config.bs.data, 0, written);
  config.bs.reset();
  return ShineEncodeResult(view, written);
}

void shineClose(ShineT config) {
  config.bs.reset();
  for (int i = 0; i < config.buffer.length; i++) {
    config.buffer[i] = null;
  }
}
