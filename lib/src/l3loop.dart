import 'dart:math' as math;
import 'dart:typed_data';

import 'constants.dart';
import 'fixed_point.dart';
import 'huffman.dart';
import 'reservoir.dart';
import 'tables.dart';
import 'types.dart';

const int _cbLimit = 21;
const int _sfbLmax = 22;
const int _enTotKrit = 10;
const int _enDifKrit = 100;
const int _enScfsiBandKrit = 10;
const int _xmScfsiBandKrit = 10;
const double _quantizeScale = 4.656612875e-10;

void shineLoopInitialise(ShineGlobalConfig config) {
  for (int i = 0; i < 128; i++) {
    final double step = math.pow(2.0, (127 - i) / 4.0).toDouble();
    config.l3loop.steptab[i] = step;
    final double scaled = step * 2.0;
    if (scaled > 0x7fffffff) {
      config.l3loop.steptabi[i] = 0x7fffffff;
    } else {
      config.l3loop.steptabi[i] = (scaled + 0.5).floor();
    }
  }

  for (int i = 0; i < 10000; i++) {
    final double value = math.sqrt(math.sqrt(i.toDouble()) * i.toDouble());
    config.l3loop.int2idx[i] = (value - 0.0946 + 0.5).floor();
  }
}

int shineInnerLoop(
  List<int> ix,
  int maxBits,
  GrInfo codInfo,
  int gr,
  int ch,
  ShineGlobalConfig config,
) {
  int bits;

  if (maxBits < 0) {
    codInfo.quantizerStepSize--;
  }

  do {
    while (quantize(ix, ++codInfo.quantizerStepSize, config) > 8192) {
      // Intentionally empty.
    }

    _calcRunlen(ix, codInfo);
    bits = _count1Bitcount(ix, codInfo);
    _subdivide(codInfo, config);
    _bigvTabSelect(ix, codInfo);
    bits += _bigvBitcount(ix, codInfo);
  } while (bits > maxBits);

  return bits;
}

int shineOuterLoop(
  int maxBits,
  ShinePsyXmin l3Xmin,
  List<int> ix,
  int gr,
  int ch,
  ShineGlobalConfig config,
) {
  final GrInfo codInfo = config.side_info.gr[gr][ch];

  codInfo.quantizerStepSize =
      _binSearchStepSize(maxBits, ix, codInfo, config);

  codInfo.part2_length = _part2Length(gr, ch, config);
  final int huffBits = maxBits - codInfo.part2_length;

  final int bits = shineInnerLoop(ix, huffBits, codInfo, gr, ch, config);
  codInfo.part2_3_length = codInfo.part2_length + bits;

  return codInfo.part2_3_length;
}

void shineIterationLoop(ShineGlobalConfig config) {
  final ShinePsyXmin l3Xmin = ShinePsyXmin();
  config.side_info.resvDrain = 0;

  for (int ch = config.wave.channels - 1; ch >= 0; ch--) {
    for (int gr = 0; gr < config.mpeg.granules_per_frame; gr++) {
      final List<int> ix = config.l3_enc[ch][gr];
      config.l3loop.xr = config.mdct_freq[ch][gr];
      final Int32List xrValues = config.l3loop.xr!;

      for (int i = granuleSize - 1; i >= 0; i--) {
        final int sample = xrValues[i];
        final int square = muls32r(sample, sample);
        config.l3loop.xrsq[i] = square;
        final int absolute = sample < 0 ? -sample : sample;
        config.l3loop.xrabs[i] = absolute;
        if (absolute > config.l3loop.xrmax) {
          config.l3loop.xrmax = absolute;
        }
      }

      final GrInfo codInfo = config.side_info.gr[gr][ch];
      codInfo.sfb_lmax = _sfbLmax - 1;

      _calcXmin(config.ratio, codInfo, l3Xmin, gr, ch);

      if (config.mpeg.version == 3) {
        _calcScfsi(l3Xmin, ch, gr, config);
      }

      final int maxBits =
          shineMaxReservoirBits(config.pe[ch][gr], config);

      for (int sfb = 0; sfb < _sfbLmax; sfb++) {
        config.scalefactor.l[gr][ch][sfb] = 0;
      }
      for (int window = 0; window < 13; window++) {
        for (int band = 0; band < 3; band++) {
          config.scalefactor.s[gr][ch][window][band] = 0;
        }
      }

      for (int i = 0; i < 4; i++) {
        codInfo.slen[i] = 0;
      }

      codInfo.part2_3_length = 0;
      codInfo.big_values = 0;
      codInfo.count1 = 0;
      codInfo.scalefac_compress = 0;
      codInfo.table_select[0] = 0;
      codInfo.table_select[1] = 0;
      codInfo.table_select[2] = 0;
      codInfo.region0_count = 0;
      codInfo.region1_count = 0;
      codInfo.part2_length = 0;
      codInfo.preflag = 0;
      codInfo.scalefac_scale = 0;
      codInfo.count1table_select = 0;

      if (config.l3loop.xrmax != 0) {
        codInfo.part2_3_length =
            shineOuterLoop(maxBits, l3Xmin, ix, gr, ch, config);
      }

      shineResvAdjust(codInfo, config);
      codInfo.global_gain = codInfo.quantizerStepSize + 210;
      config.l3loop.xrmax = 0;
    }
  }

  shineResvFrameEnd(config);
}

int quantize(List<int> ix, int stepsize, ShineGlobalConfig config) {
  final Int32List xrabs = config.l3loop.xrabs;
  final List<int> steptabi = config.l3loop.steptabi;
  final List<double> steptab = config.l3loop.steptab;
  final List<int> int2idx = config.l3loop.int2idx;

  final int scaleIndex = stepsize + 127;
  if (scaleIndex < 0 || scaleIndex >= steptabi.length) {
    return 16384;
  }

  final int scalei = steptabi[scaleIndex];
  if (mul32r(config.l3loop.xrmax, scalei) > 165140) {
    return 16384;
  }

  final double scale = steptab[scaleIndex];
  int max = 0;

  for (int i = 0; i < granuleSize; i++) {
    final int ln = mul32r(xrabs[i], scalei);
    if (ln < 10000) {
      ix[i] = int2idx[ln];
    } else {
      final double dbl = xrabs[i] * scale * _quantizeScale;
      ix[i] = math.sqrt(math.sqrt(dbl) * dbl).toInt();
    }
    if (max < ix[i]) {
      max = ix[i];
    }
  }

  return max;
}

void _calcScfsi(
  ShinePsyXmin l3Xmin,
  int ch,
  int gr,
  ShineGlobalConfig config,
) {
  final ShineSideInfo sideInfo = config.side_info;
  final List<Int32List> xm = config.l3loop.xm;
  final List<Int32List> en = config.l3loop.en;
  final List<int> enTot = config.l3loop.en_tot;
  final List<int> xrmaxl = config.l3loop.xrmaxl;
  final Int32List xrsq = config.l3loop.xrsq;

  final List<int> scfsiBandLong = <int>[0, 6, 11, 16, 21];
  final List<int> scalefacBandLong =
      shineScaleFactorBandIndex[config.mpeg.samplerate_index];

  xrmaxl[gr] = config.l3loop.xrmax;

  int temp = 0;
  for (int i = granuleSize - 1; i >= 0; i--) {
    temp += xrsq[i] >> 10;
  }

  if (temp != 0) {
    enTot[gr] = (math.log(temp * 4.768371584e-7) / ln2).toInt();
  } else {
    enTot[gr] = 0;
  }

  for (int sfb = _cbLimit - 1; sfb >= 0; sfb--) {
    final int start = scalefacBandLong[sfb];
    final int end = scalefacBandLong[sfb + 1];

    temp = 0;
    for (int i = start; i < end; i++) {
      temp += xrsq[i] >> 10;
    }
    if (temp != 0) {
      en[gr][sfb] = (math.log(temp * 4.768371584e-7) / ln2).toInt();
    } else {
      en[gr][sfb] = 0;
    }

    if (l3Xmin.l[gr][ch][sfb] != 0) {
      xm[gr][sfb] =
          (math.log(l3Xmin.l[gr][ch][sfb]) / ln2).toInt();
    } else {
      xm[gr][sfb] = 0;
    }
  }

  if (gr == 1) {
    int condition = 0;

    if (xrmaxl[0] != 0) {
      condition++;
    }
    if (xrmaxl[1] != 0) {
      condition++;
    }
    condition += 2;

    if ((enTot[0] - enTot[1]).abs() < _enTotKrit) {
      condition++;
    }

    int tp = 0;
    for (int sfb = _cbLimit - 1; sfb >= 0; sfb--) {
      tp += (en[0][sfb] - en[1][sfb]).abs();
    }
    if (tp < _enDifKrit) {
      condition++;
    }

    if (condition == 6) {
      for (int band = 0; band < 4; band++) {
        final int start = scfsiBandLong[band];
        final int end = scfsiBandLong[band + 1];
        int sum0 = 0;
        int sum1 = 0;
        for (int sfb = start; sfb < end; sfb++) {
          sum0 += (en[0][sfb] - en[1][sfb]).abs();
          sum1 += (xm[0][sfb] - xm[1][sfb]).abs();
        }
        sideInfo.scfsi[ch][band] =
            (sum0 < _enScfsiBandKrit && sum1 < _xmScfsiBandKrit) ? 1 : 0;
      }
    } else {
      for (int band = 0; band < 4; band++) {
        sideInfo.scfsi[ch][band] = 0;
      }
    }
  }
}

int _part2Length(int gr, int ch, ShineGlobalConfig config) {
  final GrInfo gi = config.side_info.gr[gr][ch];

  final int slen1 = shineSlen1Table[gi.scalefac_compress];
  final int slen2 = shineSlen2Table[gi.scalefac_compress];

  int bits = 0;

  if (gr == 0 || config.side_info.scfsi[ch][0] == 0) {
    bits += 6 * slen1;
  }
  if (gr == 0 || config.side_info.scfsi[ch][1] == 0) {
    bits += 5 * slen1;
  }
  if (gr == 0 || config.side_info.scfsi[ch][2] == 0) {
    bits += 5 * slen2;
  }
  if (gr == 0 || config.side_info.scfsi[ch][3] == 0) {
    bits += 5 * slen2;
  }

  return bits;
}

int _binSearchStepSize(
  int desiredRate,
  List<int> ix,
  GrInfo codInfo,
  ShineGlobalConfig config,
) {
  int next = -120;
  int count = 120;

  while (count > 1) {
    final int half = count ~/ 2;
    int bitCount;

    if (quantize(ix, next + half, config) > 8192) {
      bitCount = 100000;
    } else {
      _calcRunlen(ix, codInfo);
      bitCount = _count1Bitcount(ix, codInfo);
      _subdivide(codInfo, config);
      _bigvTabSelect(ix, codInfo);
      bitCount += _bigvBitcount(ix, codInfo);
    }

    if (bitCount < desiredRate) {
      count = half;
    } else {
      next += half;
      count -= half;
    }
  }

  return next;
}

int _bigvBitcount(List<int> ix, GrInfo gi) {
  int bits = 0;

  if (gi.table_select[0] != 0) {
    bits += _countBit(ix, 0, gi.address1, gi.table_select[0]);
  }
  if (gi.table_select[1] != 0) {
    bits +=
        _countBit(ix, gi.address1, gi.address2, gi.table_select[1]);
  }
  if (gi.table_select[2] != 0) {
    bits +=
        _countBit(ix, gi.address2, gi.address3, gi.table_select[2]);
  }

  return bits;
}

int _countBit(List<int> ix, int start, int end, int tableIndex) {
  if (tableIndex == 0) {
    return 0;
  }

  final HuffCodeTab table = shineHuffmanTable[tableIndex];
  final int ylen = table.ylen;
  final int linbits = table.linbits;

  int sum = 0;

  if (tableIndex > 15) {
    for (int i = start; i < end; i += 2) {
      int x = ix[i];
      int y = ix[i + 1];
      if (x > 14) {
        x = 15;
        sum += linbits;
      }
      if (y > 14) {
        y = 15;
        sum += linbits;
      }
      sum += table.hlen[(x * ylen) + y];
      if (x != 0) {
        sum++;
      }
      if (y != 0) {
        sum++;
      }
    }
  } else {
    for (int i = start; i < end; i += 2) {
      final int x = ix[i];
      final int y = ix[i + 1];
      sum += table.hlen[(x * ylen) + y];
      if (x != 0) {
        sum++;
      }
      if (y != 0) {
        sum++;
      }
    }
  }

  return sum;
}

int _newChooseTable(List<int> ix, int begin, int end) {
  final int max = _ixMax(ix, begin, end);
  if (max == 0) {
    return 0;
  }

  int choice = 0;

  if (max < 15) {
    for (int i = 14; i >= 0; i--) {
      if (shineHuffmanTable[i].xlen > max) {
        choice = i;
        break;
      }
    }
    int sum0 = _countBit(ix, begin, end, choice);
    int sum1;
    switch (choice) {
      case 2:
        sum1 = _countBit(ix, begin, end, 3);
        if (sum1 <= sum0) {
          choice = 3;
        }
        break;
      case 5:
        sum1 = _countBit(ix, begin, end, 6);
        if (sum1 <= sum0) {
          choice = 6;
        }
        break;
      case 7:
        sum1 = _countBit(ix, begin, end, 8);
        if (sum1 <= sum0) {
          choice = 8;
          sum0 = sum1;
        }
        sum1 = _countBit(ix, begin, end, 9);
        if (sum1 <= sum0) {
          choice = 9;
        }
        break;
      case 10:
        sum1 = _countBit(ix, begin, end, 11);
        if (sum1 <= sum0) {
          choice = 11;
          sum0 = sum1;
        }
        sum1 = _countBit(ix, begin, end, 12);
        if (sum1 <= sum0) {
          choice = 12;
        }
        break;
      case 13:
        sum1 = _countBit(ix, begin, end, 15);
        if (sum1 <= sum0) {
          choice = 15;
        }
        break;
    }
  } else {
    int bestTable = 15;
    int bestCount = 1000000;
    for (int i = 15; i < 24; i++) {
      if (shineHuffmanTable[i].linmax >= max - 15) {
        final int count = _countBit(ix, begin, end, i);
        if (count < bestCount) {
          bestCount = count;
          bestTable = i;
        }
      }
    }
    for (int i = 24; i < 32; i++) {
      if (shineHuffmanTable[i].linmax >= max - 15) {
        final int count = _countBit(ix, begin, end, i);
        if (count < bestCount) {
          bestCount = count;
          bestTable = i;
        }
      }
    }
    choice = bestTable;
  }

  return choice;
}

void _bigvTabSelect(List<int> ix, GrInfo codInfo) {
  codInfo.table_select[0] = 0;
  codInfo.table_select[1] = 0;
  codInfo.table_select[2] = 0;

  if (codInfo.address1 > 0) {
    codInfo.table_select[0] = _newChooseTable(ix, 0, codInfo.address1);
  }
  if (codInfo.address2 > codInfo.address1) {
    codInfo.table_select[1] =
        _newChooseTable(ix, codInfo.address1, codInfo.address2);
  }
  if ((codInfo.big_values << 1) > codInfo.address2) {
    codInfo.table_select[2] =
        _newChooseTable(ix, codInfo.address2, codInfo.big_values << 1);
  }
}

void _subdivide(GrInfo codInfo, ShineGlobalConfig config) {
  if (codInfo.big_values == 0) {
    codInfo.region0_count = 0;
    codInfo.region1_count = 0;
    codInfo.address1 = 0;
    codInfo.address2 = 0;
    codInfo.address3 = 0;
    return;
  }

  final List<int> scalefacBand =
      shineScaleFactorBandIndex[config.mpeg.samplerate_index];
  final List<List<int>> subdivTable = <List<int>>[
    <int>[0, 0],
    <int>[0, 0],
    <int>[0, 0],
    <int>[0, 0],
    <int>[0, 0],
    <int>[0, 1],
    <int>[1, 1],
    <int>[1, 1],
    <int>[1, 2],
    <int>[2, 2],
    <int>[2, 3],
    <int>[2, 3],
    <int>[3, 4],
    <int>[3, 4],
    <int>[3, 4],
    <int>[4, 5],
    <int>[4, 5],
    <int>[4, 6],
    <int>[5, 6],
    <int>[5, 6],
    <int>[5, 7],
    <int>[6, 7],
    <int>[6, 7],
  ];

  final int bigvaluesRegion = codInfo.big_values << 1;
  int scfbAnz = 0;
  while (scfbAnz < scalefacBand.length &&
      scalefacBand[scfbAnz] < bigvaluesRegion) {
    scfbAnz++;
  }
  if (scfbAnz >= subdivTable.length) {
    scfbAnz = subdivTable.length - 1;
  }

  int region0Count = subdivTable[scfbAnz][0];
  while (region0Count > 0) {
    if (scalefacBand[region0Count + 1] <= bigvaluesRegion) {
      break;
    }
    region0Count--;
  }
  codInfo.region0_count = region0Count;
  codInfo.address1 = scalefacBand[region0Count + 1];

  int region1Count = subdivTable[scfbAnz][1];
  int index = region0Count + 1;
  while (region1Count > 0) {
    if (index + region1Count + 1 < scalefacBand.length &&
        scalefacBand[index + region1Count + 1] <= bigvaluesRegion) {
      break;
    }
    region1Count--;
  }
  codInfo.region1_count = region1Count;
  codInfo.address2 = scalefacBand[index + region1Count + 1];
  codInfo.address3 = bigvaluesRegion;
}

int _count1Bitcount(List<int> ix, GrInfo codInfo) {
  int i = codInfo.big_values << 1;
  int sum0 = 0;
  int sum1 = 0;

  for (int k = 0; k < codInfo.count1; k++) {
    final int v = ix[i];
    final int w = ix[i + 1];
    final int x = ix[i + 2];
    final int y = ix[i + 3];
    final int p = v + (w << 1) + (x << 2) + (y << 3);

    int signbits = 0;
    if (v != 0) signbits++;
    if (w != 0) signbits++;
    if (x != 0) signbits++;
    if (y != 0) signbits++;

    sum0 += shineHuffmanTable[32].hlen[p] + signbits;
    sum1 += shineHuffmanTable[33].hlen[p] + signbits;
    i += 4;
  }

  if (sum0 < sum1) {
    codInfo.count1table_select = 0;
    return sum0;
  } else {
    codInfo.count1table_select = 1;
    return sum1;
  }
}

void _calcRunlen(List<int> ix, GrInfo codInfo) {
  int i = granuleSize;
  while (i > 1) {
    if (ix[i - 1] == 0 && ix[i - 2] == 0) {
      i -= 2;
    } else {
      break;
    }
  }

  codInfo.count1 = 0;
  while (i > 3) {
    if (ix[i - 1] <= 1 &&
        ix[i - 2] <= 1 &&
        ix[i - 3] <= 1 &&
        ix[i - 4] <= 1) {
      codInfo.count1++;
      i -= 4;
    } else {
      break;
    }
  }

  codInfo.big_values = i >> 1;
}

void _calcXmin(
  ShinePsyRatio _,
  GrInfo codInfo,
  ShinePsyXmin l3Xmin,
  int gr,
  int ch,
) {
  for (int sfb = codInfo.sfb_lmax - 1; sfb >= 0; sfb--) {
    l3Xmin.l[gr][ch][sfb] = 0;
  }
}

int _ixMax(List<int> ix, int begin, int end) {
  int max = 0;
  for (int i = begin; i < end; i++) {
    if (ix[i] > max) {
      max = ix[i];
    }
  }
  return max;
}
