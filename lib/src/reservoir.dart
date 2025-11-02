import 'types.dart';

int shineMaxReservoirBits(double perceptualEntropy, ShineGlobalConfig config) {
  int meanBits = config.mean_bits;
  meanBits ~/= config.wave.channels;
  int maxBits = meanBits;

  if (maxBits > 4095) {
    maxBits = 4095;
  }
  if (config.ResvMax == 0) {
    return maxBits;
  }

  int moreBits = (perceptualEntropy * 3.1).toInt() - meanBits;
  int addBits = 0;
  if (moreBits > 100) {
    final int frac = (config.ResvSize * 6) ~/ 10;
    addBits = frac < moreBits ? frac : moreBits;
  }

  int overBits = config.ResvSize - ((config.ResvMax * 8) ~/ 10) - addBits;
  if (overBits > 0) {
    addBits += overBits;
  }

  maxBits += addBits;
  if (maxBits > 4095) {
    maxBits = 4095;
  }
  return maxBits;
}

void shineResvAdjust(GrInfo gi, ShineGlobalConfig config) {
  final int meanBitsPerChannel = config.mean_bits ~/ config.wave.channels;
  config.ResvSize += meanBitsPerChannel - gi.part2_3_length;
}

void shineResvFrameEnd(ShineGlobalConfig config) {
  final ShineSideInfo sideInfo = config.side_info;
  int ancillaryPad = 0;

  if (config.wave.channels == 2 && (config.mean_bits & 1) == 1) {
    config.ResvSize += 1;
  }

  int overBits = config.ResvSize - config.ResvMax;
  if (overBits < 0) {
    overBits = 0;
  }

  config.ResvSize -= overBits;
  int stuffingBits = overBits + ancillaryPad;

  final int remainder = config.ResvSize % 8;
  if (remainder != 0) {
    stuffingBits += remainder;
    config.ResvSize -= remainder;
  }

  if (stuffingBits == 0) {
    return;
  }

  final GrInfo firstGi = sideInfo.gr[0][0];
  if (firstGi.part2_3_length + stuffingBits < 4095) {
    firstGi.part2_3_length += stuffingBits;
    return;
  }

  int remaining = stuffingBits;
  for (int gr = 0; gr < config.mpeg.granules_per_frame; gr++) {
    bool done = false;
    for (int ch = 0; ch < config.wave.channels; ch++) {
      if (remaining == 0) {
        done = true;
        break;
      }
      final GrInfo gi = sideInfo.gr[gr][ch];
      final int extraBits = 4095 - gi.part2_3_length;
      final int bitsThisGranule = extraBits < remaining ? extraBits : remaining;
      gi.part2_3_length += bitsThisGranule;
      remaining -= bitsThisGranule;
    }
    if (done) {
      break;
    }
  }

  sideInfo.resvDrain = remaining;
}
