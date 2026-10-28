// Utility functions that mimic the fixed-point helper macros defined in
// `mult_noarch_gcc.h`.
//
// The macros take the 64-bit product of two 32-bit values. On the VM and
// dart2wasm, `int` is 64-bit. Under dart2js every number is a double, exact
// only up to 2^53, and a product of two 32-bit values needs up to 62 bits,
// so there the product is split: b = bHigh * 2^16 + bLow, and
// a * b = (a * bHigh + floor(a * bLow / 2^16)) * 2^16 + r, 0 <= r < 2^16.
// Every term stays under 2^48. Shifting right by 16 or more drops r without
// changing the floor, so floor(a * b / 2^k) = floor(m / 2^(k - 16)), where m
// is the parenthesised sum.

const int _int32SignBit = 0x80000000;
const int _uint32Mask = 0xffffffff;

/// True under dart2js, where every number is a JavaScript double.
const bool _jsNumbers = identical(1, 1.0);

const int _two16 = 65536;

int toInt32(int value) {
  value &= _uint32Mask;
  if ((value & _int32SignBit) != 0) {
    return value - 0x100000000;
  }
  return value;
}

/// floor(a * b / 2^16), exact for 32-bit a and b under dart2js.
int _productHigh(int a, int b) {
  final int bLow = b % _two16; // 0 <= bLow < 2^16, also for negative b.
  final int bHigh = (b - bLow) ~/ _two16;
  return a * bHigh + ((a * bLow) / _two16).floor();
}

/// floor(m / 2^shift) without bit operations (they truncate to 32 bits
/// under dart2js).
int _floorShift(int m, int shift) => (m / (1 << shift)).floor();

int mul32(int a, int b) => _jsNumbers
    ? toInt32(_floorShift(_productHigh(a, b), 16))
    : toInt32((a * b) >> 32);

int muls32(int a, int b) => _jsNumbers
    ? toInt32(_floorShift(_productHigh(a, b), 15))
    : toInt32((a * b) >> 31);

int mul32r(int a, int b) => _jsNumbers
    ? toInt32(_floorShift(_productHigh(a, b) + (1 << 15), 16))
    : toInt32(((a * b) + 0x80000000) >> 32);

int muls32r(int a, int b) => _jsNumbers
    ? toInt32(_floorShift(_productHigh(a, b) + (1 << 14), 15))
    : toInt32(((a * b) + 0x40000000) >> 31);

int add32(int a, int b) => toInt32(a + b);

int sub32(int a, int b) => toInt32(a - b);

/// Returns the real and imaginary parts of the complex multiplication defined
/// by the `cmuls` macro.
List<int> cmuls(int are, int aim, int bre, int bim) {
  if (_jsNumbers) {
    // _exactSum is already floor(sum / 2^16): 15 more bits make 31.
    final int tre = toInt32(_floorShift(_exactSum(are, bre, -aim, bim), 15));
    final int dim = toInt32(_floorShift(_exactSum(are, bim, aim, bre), 15));
    return <int>[tre, dim];
  }
  final int tre = toInt32(((are * bre) - (aim * bim)) >> 31);
  final int dim = toInt32(((are * bim) + (aim * bre)) >> 31);
  return <int>[tre, dim];
}

/// floor((a * b + c * d) / 2^16), exact for 32-bit operands under dart2js:
/// a * b + c * d = (a * bHigh + c * dHigh) * 2^16 + low, and every term
/// stays under 2^49.
int _exactSum(int a, int b, int c, int d) {
  final int bLow = b % _two16, bHigh = (b - bLow) ~/ _two16;
  final int dLow = d % _two16, dHigh = (d - dLow) ~/ _two16;
  final int low = a * bLow + c * dLow; // |low| < 2^48
  final int lowRest = low % _two16;
  return a * bHigh + c * dHigh + (low - lowRest) ~/ _two16;
}
