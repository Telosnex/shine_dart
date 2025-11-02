import 'dart:math' as math;
import 'dart:typed_data';

import 'constants.dart';
import 'fixed_point.dart';
import 'l3subband.dart';
import 'types.dart';

void shineMdctInitialise(ShineGlobalConfig config) {
  for (int m = 0; m < 18; m++) {
    final Int32List row = config.mdct.cosL[m];
    for (int k = 0; k < 36; k++) {
      final double value = math.sin(pi36 * (k + 0.5)) *
          math.cos((math.pi / 72.0) * (2 * k + 19) * (2 * m + 1));
      final double scaled = value * 0x7fffffff;
      row[k] = scaled >= 0 ? scaled.floor() : scaled.ceil();
    }
  }
}

void shineMdctSub(ShineGlobalConfig config, int stride) {
  final int channels = config.wave.channels;
  final int granules = config.mpeg.granules_per_frame;

  for (int ch = 0; ch < channels; ch++) {
    for (int gr = 0; gr < granules; gr++) {
      for (int k = 0; k < 18; k += 2) {
        shineWindowFilterSubband(
          config.buffer,
          config.l3_sb_sample[ch][gr + 1][k],
          ch,
          config,
          stride,
        );
        shineWindowFilterSubband(
          config.buffer,
          config.l3_sb_sample[ch][gr + 1][k + 1],
          ch,
          config,
          stride,
        );
        final Int32List oddBand = config.l3_sb_sample[ch][gr + 1][k + 1];
        for (int band = 1; band < sbLimit; band += 2) {
          oddBand[band] = -oddBand[band];
        }
      }

      final Int32List mdctOut = config.mdct_freq[ch][gr];
      final List<Int32List> prevSamples = config.l3_sb_sample[ch][gr];
      final List<Int32List> currSamples =
          config.l3_sb_sample[ch][gr + 1];
      final List<int> mdctIn = List<int>.filled(36, 0, growable: false);

      for (int band = 0; band < sbLimit; band++) {
        for (int k = 0; k < 18; k++) {
          mdctIn[k] = prevSamples[k][band];
          mdctIn[k + 18] = currSamples[k][band];
        }

        for (int k = 0; k < 18; k++) {
          int acc = 0;
          final Int32List cosRow = config.mdct.cosL[k];
          for (int j = 0; j < 36; j++) {
            acc = add32(acc, mul32(mdctIn[j], cosRow[j]));
          }
          mdctOut[band * 18 + k] = acc;
        }

        if (band != 0) {
          final int prevBase = (band - 1) * 18;
          final int currentBase = band * 18;
          for (int idx = 0; idx < 8; idx++) {
            final int upperIndex = currentBase + idx;
            final int lowerIndex = prevBase + (17 - idx);
            final int are = mdctOut[upperIndex];
            final int aim = mdctOut[lowerIndex];
            final List<int> rotated = cmuls(
              are,
              aim,
              _mdctCs[idx],
              _mdctCa[idx],
            );
            mdctOut[upperIndex] = rotated[0];
            mdctOut[lowerIndex] = rotated[1];
          }
        }
      }
    }

    final List<Int32List> latest =
        config.l3_sb_sample[ch][config.mpeg.granules_per_frame];
    final List<Int32List> target = config.l3_sb_sample[ch][0];
    for (int k = 0; k < 18; k++) {
      final Int32List dest = target[k];
      final Int32List src = latest[k];
      for (int band = 0; band < sbLimit; band++) {
        dest[band] = src[band];
      }
    }
  }
}

final List<int> _mdctCs = _buildMdctCoefficients(cs: true);
final List<int> _mdctCa = _buildMdctCoefficients(cs: false);

List<int> _buildMdctCoefficients({required bool cs}) {
  const List<double> coefficients = <double>[
    -0.6,
    -0.535,
    -0.33,
    -0.185,
    -0.095,
    -0.041,
    -0.0142,
    -0.0037,
  ];
  return coefficients
      .map((double coef) {
        final double value = cs
            ? (1.0 / math.sqrt(1.0 + coef * coef))
            : (coef / math.sqrt(1.0 + coef * coef));
        final double scaled = value * 0x7fffffff;
        return scaled >= 0 ? scaled.floor() : scaled.ceil();
      })
      .toList(growable: false);
}
