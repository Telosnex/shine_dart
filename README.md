# shine_dart

Pure Dart port of the Shine MP3 encoder C implementation.

## Status

Feature complete. Encoding functionality is implemented and tested.

## Example

```dart
import 'dart:typed_data';

import 'package:shine_dart/shine.dart';

void main() {
  final config = ShineConfig(
    wave: ShineWave(channels: Channels.pcmStereo, samplerate: 44100),
    mpeg: ShineMpeg()..bitr = 128,
  );

  final ShineT? encoder = shineInitialise(config);
  if (encoder == null) {
    throw StateError('Unsupported configuration');
  }

  // Supply 1152 samples per channel (interleaved in this example).
  final Int16List pcm = Int16List(shineSamplesPerPass(encoder) * 2);

  final ShineEncodeResult frame = shineEncodeBufferInterleaved(encoder, pcm);
  // Copy frame.buffer before the next encoding call if you need to retain it.

  final ShineEncodeResult flush = shineFlush(encoder);
  final Uint8List output = Uint8List(frame.length + flush.length)
    ..setAll(0, frame.buffer)
    ..setAll(frame.length, flush.buffer);

  shineClose(encoder);
  print('Encoded ${output.length} bytes');
}
```
