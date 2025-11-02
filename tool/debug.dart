import 'dart:io';
import 'dart:typed_data';

import 'package:shine_dart/shine.dart';

void main(List<String> args) {
  final file = File('test/assets/audio_sample_mono_24khz_16bit_golden.wav');
  if (!file.existsSync()) {
    stderr.writeln('Fixture missing; run tests first to copy WAV asset.');
    exit(1);
  }

  final wav = _WavFile.fromBytes(file.readAsBytesSync());
  final config = ShineConfig(
    wave: ShineWave(channels: Channels.pcmMono, samplerate: wav.sampleRate),
    mpeg: ShineMpeg()
      ..bitr = 64
      ..mode = StereoMode.mono,
  );
  final encoder = shineInitialise(config)!
    ..side_info.reset();

  final samplesPerPass = shineSamplesPerPass(encoder);
  final frameSize = samplesPerPass * wav.numChannels;
  final pcm = wav.pcmData;

  int offset = 0;
  int frameIndex = 0;
  while (offset < pcm.length) {
    Int16List frame;
    if (offset + frameSize <= pcm.length) {
      frame = Int16List.sublistView(pcm, offset, offset + frameSize);
    } else {
      frame = Int16List(frameSize);
      final remaining = pcm.length - offset;
      frame.setRange(0, remaining, pcm.sublist(offset));
    }

    final result = shineEncodeBufferInterleaved(encoder, frame);
    if (frameIndex == 0) {
      final info = encoder.side_info.gr[0][0];
      stdout.writeln('Frame 0: part2_3_length=${info.part2_3_length}, '
          'big_values=${info.big_values}, count1=${info.count1}');
      stdout.writeln('  table_select=${info.table_select}');
      stdout.writeln('  quantizerStepSize=${info.quantizerStepSize}');
      stdout.writeln('  mean_bits=${encoder.mean_bits}, '
          'sideinfo_len=${encoder.sideinfo_len}');
      stdout.writeln('  encoded bytes=${result.length}');
      stdout.writeln('  ResvSize=${encoder.ResvSize}, ResvMax=${encoder.ResvMax}, '
          'resvDrain=${encoder.side_info.resvDrain}');
      stdout.writeln('  mdct_freq[0..31]=${encoder.mdct_freq[0][0].sublist(0, 32)}');
      stdout.writeln(
          '  subband[gr+1][k=0][0..31]=${encoder.l3_sb_sample[0][1][0].sublist(0, 32)}');
      stdout.writeln('  shineEnwindow[0..9]=${shineEnwindow.sublist(0, 10)}');
      final ix = encoder.l3_enc[0][0];
      stdout.writeln('  ix[0..31]=${ix.sublist(0, 32)}');
    }

    offset += frameSize;
    frameIndex++;
    if (frameIndex == 1) {
      break; // inspect only first frame for now
    }
  }
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
    final data = ByteData.sublistView(bytes);

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
      final chunkId = fourCc(offset);
      final chunkSize = data.getUint32(offset + 4, Endian.little);
      offset += 8;
      if (offset + chunkSize > bytes.length) {
        throw FormatException('Invalid chunk size');
      }
      if (chunkId == 'fmt ') {
        final audioFormat = data.getUint16(offset, Endian.little);
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
        offset += 1;
      }
    }

    if (numChannels == null ||
        sampleRate == null ||
        bitsPerSample == null ||
        dataStart == -1) {
      throw FormatException('Incomplete WAV header');
    }

    final sampleCount = dataLength ~/ 2;
    final samples = Int16List(sampleCount);
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
