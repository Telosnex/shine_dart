/// Public API surface for the work-in-progress Shine MP3 encoder port.
///
/// The classes exported here mirror the key data structures from the original
/// C implementation located under `shine/src/lib`. Only a subset of the
/// encoder pipeline has been implemented in pure Dart so far.
library shine_dart;

export 'src/constants.dart';
export 'src/types.dart';
export 'src/bitstream.dart';
export 'src/layer3.dart';
export 'src/tables.dart';
