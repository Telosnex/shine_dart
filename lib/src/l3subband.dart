import 'dart:math' as math;
import 'dart:typed_data';

import 'constants.dart';
import 'fixed_point.dart';
import 'tables.dart';
import 'types.dart';

void shineSubbandInitialise(ShineGlobalConfig config) {
  for (int ch = 0; ch < maxChannels; ch++) {
    config.subband.off[ch] = 0;
    final Int32List delayLine = config.subband.x[ch];
    for (int i = 0; i < hanSize; i++) {
      delayLine[i] = 0;
    }
  }

  for (int i = 0; i < sbLimit; i++) {
    final Int32List filter = config.subband.fl[i];
    for (int j = 0; j < 64; j++) {
      final double angle = (2 * i + 1) * (16 - j) * pi64;
      double value = math.cos(angle) * 1e9;
      value = value >= 0 ? value + 0.5 : value - 0.5;
      final double rounded = value.truncateToDouble();
      final double scaled = rounded * (0x7fffffff * 1e-9);
      filter[j] = scaled.toInt();
    }
  }
}

void shineWindowFilterSubband(
  List<PcmPointer?> buffer,
  Int32List s,
  int channel,
  ShineGlobalConfig config,
  int stride,
) {
  final PcmPointer pointer = buffer[channel]!;
  final Int16List data = pointer.data;
  int position = pointer.position;

  final Int32List delayLine = config.subband.x[channel];
  final int offset = config.subband.off[channel];
  final int mask = hanSize - 1;

  for (int i = 31; i >= 0; i--) {
    final int sample = position < data.length ? data[position] : 0;
    delayLine[offset + i] = toInt32(sample << 16);
    position += stride;
  }
  pointer.position = position;

  final Int32List y = Int32List(64);
  for (int i = 63; i >= 0; i--) {
    int acc = mul32(delayLine[(offset + i + (0 << 6)) & mask], shineEnwindow[i + (0 << 6)]);
    acc = add32(acc, mul32(delayLine[(offset + i + (1 << 6)) & mask], shineEnwindow[i + (1 << 6)]));
    acc = add32(acc, mul32(delayLine[(offset + i + (2 << 6)) & mask], shineEnwindow[i + (2 << 6)]));
    acc = add32(acc, mul32(delayLine[(offset + i + (3 << 6)) & mask], shineEnwindow[i + (3 << 6)]));
    acc = add32(acc, mul32(delayLine[(offset + i + (4 << 6)) & mask], shineEnwindow[i + (4 << 6)]));
    acc = add32(acc, mul32(delayLine[(offset + i + (5 << 6)) & mask], shineEnwindow[i + (5 << 6)]));
    acc = add32(acc, mul32(delayLine[(offset + i + (6 << 6)) & mask], shineEnwindow[i + (6 << 6)]));
    acc = add32(acc, mul32(delayLine[(offset + i + (7 << 6)) & mask], shineEnwindow[i + (7 << 6)]));
    y[i] = acc;
  }

  config.subband.off[channel] = (offset + 480) & mask;

  for (int i = sbLimit - 1; i >= 0; i--) {
    int acc = mul32(config.subband.fl[i][63], y[63]);
    for (int j = 63; j > 0; j -= 7) {
      acc = add32(acc, mul32(config.subband.fl[i][j - 1], y[j - 1]));
      acc = add32(acc, mul32(config.subband.fl[i][j - 2], y[j - 2]));
      acc = add32(acc, mul32(config.subband.fl[i][j - 3], y[j - 3]));
      acc = add32(acc, mul32(config.subband.fl[i][j - 4], y[j - 4]));
      acc = add32(acc, mul32(config.subband.fl[i][j - 5], y[j - 5]));
      acc = add32(acc, mul32(config.subband.fl[i][j - 6], y[j - 6]));
      acc = add32(acc, mul32(config.subband.fl[i][j - 7], y[j - 7]));
    }
    s[i] = acc;
  }
}
