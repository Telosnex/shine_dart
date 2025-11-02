import 'dart:io';
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:shine_dart/shine.dart';

void main() {
  test('Encode Gemini WAV file', () {
    final wavFile = File('test/assets/test_gemini.wav');
    final wavBytes = wavFile.readAsBytesSync();
    
    // Parse WAV
    final data = ByteData.sublistView(Uint8List.fromList(wavBytes));
    
    // Find 'data' chunk
    int dataStart = 44;
    for (int i = 12; i < wavBytes.length - 8; i++) {
      if (wavBytes[i] == 0x64 && // 'd'
          wavBytes[i + 1] == 0x61 && // 'a'
          wavBytes[i + 2] == 0x74 && // 't'
          wavBytes[i + 3] == 0x61) {  // 'a'
        dataStart = i + 8;
        break;
      }
    }
    
    final sampleCount = (wavBytes.length - dataStart) ~/ 2;
    print('Sample count: $sampleCount');
    
    final samples = Int16List(sampleCount);
    for (int i = 0; i < sampleCount; i++) {
      samples[i] = data.getInt16(dataStart + i * 2, Endian.little);
    }
    
    // Check samples
    final nonZero = samples.where((s) => s != 0).length;
    print('Non-zero samples: $nonZero / $sampleCount');
    final firstNonZeroIdx = samples.indexWhere((s) => s != 0);
    print('First non-zero at index: $firstNonZeroIdx, value: ${samples[firstNonZeroIdx]}');
    
    // Encode
    final config = ShineConfig(
      wave: ShineWave(channels: Channels.pcmMono, samplerate: 24000),
      mpeg: ShineMpeg()
        ..bitr = 64
        ..mode = StereoMode.mono,
    );
    
    final encoder = shineInitialise(config);
    expect(encoder, isNotNull);
    final handle = encoder!;
    
    try {
      final builder = BytesBuilder(copy: false);
      final samplesPerPass = shineSamplesPerPass(handle);
      print('Samples per pass: $samplesPerPass');
      final frameSamples = samplesPerPass;
      
      int offset = 0;
      int frameNum = 0;
      while (offset < samples.length) {
        final Int16List frame = Int16List(frameSamples);
        for (int j = 0; j < frameSamples && offset + j < samples.length; j++) {
          frame[j] = samples[offset + j];
        }
        
        final result = shineEncodeBufferInterleaved(handle, frame);
        builder.add(result.buffer);
        
        if (frameNum < 3) {
          print('Frame $frameNum: encoded ${result.length} bytes, first 5 samples: ${frame.take(5).toList()}');
        }
        
        offset += frameSamples;
        frameNum++;
      }
      
      final flush = shineFlush(handle);
      builder.add(flush.buffer);
      print('Flush: ${flush.length} bytes');
      
      final mp3Bytes = builder.toBytes();
      print('Total MP3 bytes: ${mp3Bytes.length}');
      
      final outputFile = File('/tmp/test_gemini_encoded.mp3');
      outputFile.writeAsBytesSync(mp3Bytes);
      print('Wrote to ${outputFile.path}');
      
      expect(mp3Bytes.length, greaterThan(1000));
    } finally {
      shineClose(handle);
    }
  });
}
