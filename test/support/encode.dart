import 'dart:typed_data';

import 'package:shine_dart/shine.dart';

/// Encodes interleaved [pcm] as the C `shineenc` does: stereo mode for two
/// channels, mono for one, the last pass padded with zeros.
Uint8List encodeLikeShineenc(
  Int16List pcm, {
  required int sampleRate,
  required int channels,
  required int bitrate,
}) {
  final encoder = shineInitialise(
    ShineConfig(
      wave: ShineWave(
        channels: channels == 2 ? Channels.pcmStereo : Channels.pcmMono,
        samplerate: sampleRate,
      ),
      mpeg: ShineMpeg()
        ..bitr = bitrate
        ..mode = channels == 2 ? StereoMode.stereo : StereoMode.mono,
    ),
  )!;
  final perPass = shineSamplesPerPass(encoder) * channels;
  final out = BytesBuilder();
  for (var offset = 0; offset < pcm.length; offset += perPass) {
    final end = offset + perPass < pcm.length ? offset + perPass : pcm.length;
    final pass = Int16List(perPass)..setRange(0, end - offset, pcm, offset);
    out.add(shineEncodeBufferInterleaved(encoder, pass).buffer);
  }
  out.add(shineFlush(encoder).buffer);
  shineClose(encoder);
  return out.takeBytes();
}
