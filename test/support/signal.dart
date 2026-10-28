import 'dart:typed_data';

/// A test signal from integer arithmetic only (no `sin`, nothing above
/// 2^53), so it is the same on the VM, dart2js and dart2wasm.
/// tool/c_reference_digests.dart writes it as a WAV for the C encoder.
///
/// Per channel: a triangle wave, a square wave, noise from a Park-Miller
/// generator, and a slow envelope.
Int16List testSignal(int sampleRate, int channels, int frames) {
  final pcm = Int16List(frames * channels);
  var seed = 20261028;
  for (var i = 0; i < frames; i++) {
    final envelope = 256 + (i * 7 ~/ (sampleRate ~/ 100)) % 768;
    for (var c = 0; c < channels; c++) {
      seed = (seed * 48271) % 2147483647;
      final noise = (seed % 2001) - 1000;
      final period = 40 + 23 * c;
      final phase = i % period;
      final triangle =
          (phase < period ~/ 2 ? phase : period - phase) * 4000 ~/ period -
              1000;
      final square = (i ~/ (7 + 3 * c)) % 2 == 0 ? 600 : -600;
      final v = (triangle * 9 + square * 5 + noise * 4) * envelope ~/ 1024;
      pcm[i * channels + c] = v.clamp(-32768, 32767);
    }
  }
  return pcm;
}

/// [testSignal] as a 16-bit PCM WAV file.
Uint8List testSignalWav(int sampleRate, int channels, int frames) {
  final pcm = testSignal(sampleRate, channels, frames);
  final out = ByteData(44 + pcm.length * 2);
  void ascii(int at, String s) {
    for (var k = 0; k < 4; k++) {
      out.setUint8(at + k, s.codeUnitAt(k));
    }
  }

  ascii(0, 'RIFF');
  out.setUint32(4, 36 + pcm.length * 2, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  out.setUint32(16, 16, Endian.little);
  out.setUint16(20, 1, Endian.little);
  out.setUint16(22, channels, Endian.little);
  out.setUint32(24, sampleRate, Endian.little);
  out.setUint32(28, sampleRate * channels * 2, Endian.little);
  out.setUint16(32, channels * 2, Endian.little);
  out.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  out.setUint32(40, pcm.length * 2, Endian.little);
  for (var k = 0; k < pcm.length; k++) {
    out.setInt16(44 + k * 2, pcm[k], Endian.little);
  }
  return out.buffer.asUint8List();
}
