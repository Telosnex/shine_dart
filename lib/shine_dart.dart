/// A pure Dart port of the Shine MP3 encoder.
///
/// [shineInitialise] makes an encoder from a [ShineConfig].
/// [shineEncodeBuffer] or [shineEncodeBufferInterleaved] encodes one pass of
/// [shineSamplesPerPass] samples per channel, and [shineFlush] returns the
/// last bytes. The other classes mirror the data structures of the C code.
library shine_dart;

export 'src/constants.dart';
export 'src/types.dart';
export 'src/bitstream.dart';
export 'src/layer3.dart';
export 'src/tables.dart';
