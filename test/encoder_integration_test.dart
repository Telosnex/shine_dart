import 'dart:io';
import 'dart:typed_data';

import 'package:shine_dart/shine.dart';
import 'package:test/test.dart';

void main() {
  group('Shine encoder integration', () {
    test('encodes mono 24kHz sample to MP3', () {
      final File wavFile =
          File('test/assets/audio_sample_mono_24khz_16bit_golden.wav');
      expect(wavFile.existsSync(), isTrue,
          reason: 'WAV fixture is required for the integration test.');

      final _WavFile wav = _WavFile.fromBytes(wavFile.readAsBytesSync());

      expect(wav.numChannels, equals(1));
      expect(wav.bitsPerSample, equals(16));

      final ShineConfig config = ShineConfig(
        wave: ShineWave(channels: Channels.pcmMono, samplerate: wav.sampleRate),
        mpeg: ShineMpeg()
          ..bitr = 64
          ..mode = StereoMode.mono,
      );

      final ShineT? encoder = shineInitialise(config);
      expect(encoder, isNotNull, reason: 'Unsupported encoder configuration.');
      final ShineT handle = encoder!;

      final int samplesPerPass = shineSamplesPerPass(handle);
      final int frameSize = samplesPerPass * wav.numChannels;
      final Int16List pcm = wav.pcmData;

      final BytesBuilder builder = BytesBuilder();
      int offset = 0;
      while (offset < pcm.length) {
        Int16List frame;
        if (offset + frameSize <= pcm.length) {
          frame = Int16List.sublistView(pcm, offset, offset + frameSize);
        } else {
          frame = Int16List(frameSize);
          final int remaining = pcm.length - offset;
          frame.setRange(0, remaining, pcm.sublist(offset));
        }

        final ShineEncodeResult result =
            shineEncodeBufferInterleaved(handle, frame);
        builder.add(result.buffer);
        offset += frameSize;
      }

      final ShineEncodeResult flushResult = shineFlush(handle);
      builder.add(flushResult.buffer);
      shineClose(handle);

      final Uint8List encodedBytes = builder.takeBytes();

      final File mp3File =
          File('test/output/audio_sample_mono_24khz_16bit_golden.mp3');
      mp3File.parent.createSync(recursive: true);
      mp3File.writeAsBytesSync(encodedBytes, flush: true);

      expect(mp3File.existsSync(), isTrue);
      expect(mp3File.lengthSync(), greaterThan(0));

      final Uint8List goldenBytes = File(
        'test/assets/audio_sample_mono_24khz_16bit_golden.mp3',
      ).readAsBytesSync();
      expect(encodedBytes.length, goldenBytes.length,
          reason: 'Encoded MP3 size should match golden reference');
      expect(encodedBytes, equals(goldenBytes));
    });

    test('encodes Gemini mono 24kHz sample to MP3', () {
      final File wavFile =
          File('test/assets/audio_sample_geminitts_mono_24khz_16bit.wav');
      expect(wavFile.existsSync(), isTrue,
          reason: 'WAV fixture is required for the integration test.');

      final _WavFile wav = _WavFile.fromBytes(wavFile.readAsBytesSync());

      expect(wav.numChannels, equals(1));
      expect(wav.bitsPerSample, equals(16));

      final ShineConfig config = ShineConfig(
        wave: ShineWave(channels: Channels.pcmMono, samplerate: wav.sampleRate),
        mpeg: ShineMpeg()
          ..bitr = 64
          ..mode = StereoMode.mono,
      );

      final ShineT? encoder = shineInitialise(config);
      expect(encoder, isNotNull, reason: 'Unsupported encoder configuration.');
      final ShineT handle = encoder!;

      final int samplesPerPass = shineSamplesPerPass(handle);
      final int frameSize = samplesPerPass * wav.numChannels;
      final Int16List pcm = wav.pcmData;

      final BytesBuilder builder = BytesBuilder();
      int offset = 0;
      while (offset < pcm.length) {
        Int16List frame;
        if (offset + frameSize <= pcm.length) {
          frame = Int16List.sublistView(pcm, offset, offset + frameSize);
        } else {
          frame = Int16List(frameSize);
          final int remaining = pcm.length - offset;
          frame.setRange(0, remaining, pcm.sublist(offset));
        }

        final ShineEncodeResult result =
            shineEncodeBufferInterleaved(handle, frame);
        builder.add(result.buffer);
        offset += frameSize;
      }

      final ShineEncodeResult flushResult = shineFlush(handle);
      builder.add(flushResult.buffer);
      shineClose(handle);

      final Uint8List encodedBytes = builder.takeBytes();

      final File mp3File = File(
          'test/output/audio_sample_geminitts_mono_24khz_16bit_golden.mp3');
      mp3File.parent.createSync(recursive: true);
      mp3File.writeAsBytesSync(encodedBytes, flush: true);

      expect(mp3File.existsSync(), isTrue);
      expect(mp3File.lengthSync(), greaterThan(0));

      final Uint8List goldenBytes = File(
        'test/assets/audio_sample_geminitts_mono_24khz_16bit_golden.mp3',
      ).readAsBytesSync();
      expect(encodedBytes.length, goldenBytes.length,
          reason: 'Encoded MP3 size should match golden reference');
      expect(encodedBytes, equals(goldenBytes));
    });
  });
}

class _WavFile {
  _WavFile({
    required this.numChannels,
    required this.sampleRate,
    required this.bitsPerSample,
    required this.pcmData,
  });

  final int numChannels;
  final int sampleRate;
  final int bitsPerSample;
  final Int16List pcmData;

  factory _WavFile.fromBytes(Uint8List bytes) {
    if (bytes.length < 44) {
      throw FormatException('WAV data too small (${bytes.length} bytes)');
    }

    final ByteData data = ByteData.sublistView(bytes);

    String fourCc(int offset) =>
        String.fromCharCodes(bytes.sublist(offset, offset + 4));

    if (fourCc(0) != 'RIFF' || fourCc(8) != 'WAVE') {
      throw FormatException('Not a RIFF/WAVE file');
    }

    int? numChannels;
    int? sampleRate;
    int? bitsPerSample;
    int dataStart = -1;
    int dataLength = 0;

    int offset = 12;
    while (offset + 8 <= bytes.length) {
      final String chunkId = fourCc(offset);
      final int chunkSize = data.getUint32(offset + 4, Endian.little);
      offset += 8;

      if (offset + chunkSize > bytes.length) {
        throw FormatException('Invalid chunk size in WAV file');
      }

      if (chunkId == 'fmt ') {
        final int audioFormat = data.getUint16(offset, Endian.little);
        if (audioFormat != 1) {
          throw UnsupportedError('Only PCM WAV files are supported');
        }
        numChannels = data.getUint16(offset + 2, Endian.little);
        sampleRate = data.getUint32(offset + 4, Endian.little);
        bitsPerSample = data.getUint16(offset + 14, Endian.little);
      } else if (chunkId == 'data') {
        dataStart = offset;
        dataLength = chunkSize;
        break;
      }

      offset += chunkSize;
      if (chunkSize.isOdd) {
        offset += 1; // Align to even boundary.
      }
    }

    if (numChannels == null ||
        sampleRate == null ||
        bitsPerSample == null ||
        dataStart == -1) {
      throw FormatException('Incomplete WAV header');
    }

    if (bitsPerSample != 16) {
      throw UnsupportedError('Only 16-bit PCM WAV files are supported');
    }

    final int sampleCount = dataLength ~/ 2;
    final Int16List samples = Int16List(sampleCount);
    for (int i = 0; i < sampleCount; i++) {
      samples[i] = data.getInt16(dataStart + i * 2, Endian.little);
    }

    return _WavFile(
      numChannels: numChannels,
      sampleRate: sampleRate,
      bitsPerSample: bitsPerSample,
      pcmData: samples,
    );
  }
}
