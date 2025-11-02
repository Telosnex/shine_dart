import 'dart:typed_data';

import 'constants.dart';

/// Dart translation of `bitstream.c` from the original Shine project.
///
/// The implementation closely mirrors the C structure in order to make audits
/// against the upstream source straightforward.
class BitStream {
  BitStream({int initialSize = bufferSize})
      : assert(initialSize > 0, 'initialSize must be positive'),
        _data = Uint8List(initialSize),
        _dataSize = initialSize;

  Uint8List _data;
  int _dataSize;

  /// Mirrors `data_position` in the original C struct.
  int dataPosition = 0;

  /// Bit-level cache used to pack up to 32 bits at a time.
  int _cache = 0;

  /// Number of free bits available in [_cache]. Starts at 32, matching the C
  /// implementation.
  int _cacheBits = 32;

  /// Ensures that the internal buffer can accommodate [requiredCapacity] bytes.
  void _ensureCapacity(int requiredCapacity) {
    if (requiredCapacity <= _dataSize) {
      return;
    }

    int newCapacity = _dataSize + (_dataSize >> 1);
    if (newCapacity < requiredCapacity) {
      newCapacity = requiredCapacity;
    }

    final Uint8List grown = Uint8List(newCapacity);
    grown.setRange(0, _data.length, _data);
    _data = grown;
    _dataSize = newCapacity;
  }

  /// Writes [numBits] lower bits from [value] into the bitstream.
  void putBits(int value, int numBits) {
    if (numBits == 0) {
      return;
    }
    if (numBits < 0 || numBits > 32) {
      throw RangeError.range(numBits, 1, 32, 'numBits');
    }

    value &= numBits == 32 ? 0xffffffff : (1 << numBits) - 1;

    if (_cacheBits > numBits) {
      _cacheBits -= numBits;
      _cache |= value << _cacheBits;
      return;
    }

    final int newBits = numBits - _cacheBits;
    _cache |= value >> newBits;

    _ensureCapacity(dataPosition + 4);
    _writeUint32BigEndian(dataPosition, _cache);
    dataPosition += 4;

    _cacheBits = 32 - newBits;
    if (newBits != 0) {
      _cache = (value << _cacheBits) & 0xffffffff;
    } else {
      _cache = 0;
    }
  }

  /// Returns the number of bits emitted so far.
  int get bitsCount => (dataPosition << 3) + 32 - _cacheBits;

  /// Provides direct access to the internal buffer.
  Uint8List get data => _data;

  /// Returns current capacity of the internal buffer in bytes.
  int get capacity => _dataSize;

  /// Returns a view over the currently written bytes.
  Uint8List get dataView => Uint8List.sublistView(_data, 0, dataPosition);

  /// Resets the bitstream so it can be reused for the next frame.
  void reset() {
    dataPosition = 0;
    _cache = 0;
    _cacheBits = 32;
  }

  /// Writes [value] as a big-endian 32-bit unsigned integer at [offset].
  void _writeUint32BigEndian(int offset, int value) {
    _data[offset] = (value >> 24) & 0xff;
    _data[offset + 1] = (value >> 16) & 0xff;
    _data[offset + 2] = (value >> 8) & 0xff;
    _data[offset + 3] = value & 0xff;
  }
}
