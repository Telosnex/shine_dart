// Utility functions that mimic the fixed-point helper macros defined in
// `mult_noarch_gcc.h`.

const int _int32SignBit = 0x80000000;
const int _uint32Mask = 0xffffffff;

int toInt32(int value) {
  value &= _uint32Mask;
  if ((value & _int32SignBit) != 0) {
    return value - 0x100000000;
  }
  return value;
}

int mul32(int a, int b) => toInt32((a * b) >> 32);

int muls32(int a, int b) => toInt32((a * b) >> 31);

int mul32r(int a, int b) => toInt32(((a * b) + 0x80000000) >> 32);

int muls32r(int a, int b) => toInt32(((a * b) + 0x40000000) >> 31);

int add32(int a, int b) => toInt32(a + b);

int sub32(int a, int b) => toInt32(a - b);

/// Returns the real and imaginary parts of the complex multiplication defined
/// by the `cmuls` macro.
List<int> cmuls(int are, int aim, int bre, int bim) {
  final int tre = toInt32(((are * bre) - (aim * bim)) >> 31);
  final int dim = toInt32(((are * bim) + (aim * bre)) >> 31);
  return <int>[tre, dim];
}
