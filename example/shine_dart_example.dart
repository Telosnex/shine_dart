import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:shine_dart/shine_dart.dart';

/// Encodes one second of a 440 Hz tone as a 128 kbit/s mono MP3.
void main() {
  final encoder = shineInitialise(
    ShineConfig(
      wave: ShineWave(channels: Channels.pcmMono, samplerate: 44100),
      mpeg: ShineMpeg(mode: StereoMode.mono, bitr: 128),
    ),
  );
  if (encoder == null) throw StateError('Unsupported configuration');

  final perPass = shineSamplesPerPass(encoder);
  final mp3 = BytesBuilder();
  var t = 0;
  while (t < 44100) {
    final pcm = Int16List(perPass);
    for (var i = 0; i < perPass; i++, t++) {
      pcm[i] = (sin(2 * pi * 440 * t / 44100) * 8000).round();
    }
    mp3.add(shineEncodeBufferInterleaved(encoder, pcm).buffer);
  }
  mp3.add(shineFlush(encoder).buffer);
  shineClose(encoder);

  File('tone.mp3').writeAsBytesSync(mp3.takeBytes());
  print('Wrote tone.mp3');
}
