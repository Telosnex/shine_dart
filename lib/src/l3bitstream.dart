import 'dart:typed_data';

import 'bitstream.dart';
import 'constants.dart';
import 'huffman.dart';
import 'tables.dart';
import 'types.dart';

void shineFormatBitstream(ShineGlobalConfig config) {
  for (int ch = 0; ch < config.wave.channels; ch++) {
    for (int gr = 0; gr < config.mpeg.granules_per_frame; gr++) {
      final List<int> pi = config.l3_enc[ch][gr];
      final Int32List pr = config.mdct_freq[ch][gr];
      for (int i = 0; i < granuleSize; i++) {
        if (pr[i] < 0 && pi[i] > 0) {
          pi[i] = -pi[i];
        }
      }
    }
  }

  _encodeSideInfo(config);
  _encodeMainData(config);
}

void _encodeMainData(ShineGlobalConfig config) {
  final BitStream bs = config.bs;
  final ShineSideInfo sideInfo = config.side_info;

  for (int gr = 0; gr < config.mpeg.granules_per_frame; gr++) {
    for (int ch = 0; ch < config.wave.channels; ch++) {
      final GrInfo gi = sideInfo.gr[gr][ch];
      final int slen1 = shineSlen1Table[gi.scalefac_compress];
      final int slen2 = shineSlen2Table[gi.scalefac_compress];
      final List<int> scalefactors = config.scalefactor.l[gr][ch];
      final List<int> ix = config.l3_enc[ch][gr];

      if (gr == 0 || sideInfo.scfsi[ch][0] == 0) {
        for (int sfb = 0; sfb < 6; sfb++) {
          bs.putBits(scalefactors[sfb], slen1);
        }
      }
      if (gr == 0 || sideInfo.scfsi[ch][1] == 0) {
        for (int sfb = 6; sfb < 11; sfb++) {
          bs.putBits(scalefactors[sfb], slen1);
        }
      }
      if (gr == 0 || sideInfo.scfsi[ch][2] == 0) {
        for (int sfb = 11; sfb < 16; sfb++) {
          bs.putBits(scalefactors[sfb], slen2);
        }
      }
      if (gr == 0 || sideInfo.scfsi[ch][3] == 0) {
        for (int sfb = 16; sfb < 21; sfb++) {
          bs.putBits(scalefactors[sfb], slen2);
        }
      }

      _huffmanCodeBits(config, ix, gi);
    }
  }
}

void _encodeSideInfo(ShineGlobalConfig config) {
  final BitStream bs = config.bs;
  final ShineSideInfo si = config.side_info;

  bs.putBits(0x7ff, 11);
  bs.putBits(config.mpeg.version, 2);
  bs.putBits(config.mpeg.layer, 2);
  bs.putBits(config.mpeg.crc == 0 ? 1 : 0, 1);
  bs.putBits(config.mpeg.bitrate_index, 4);
  bs.putBits(config.mpeg.samplerate_index % 3, 2);
  bs.putBits(config.mpeg.padding, 1);
  bs.putBits(config.mpeg.ext, 1);
  bs.putBits(config.mpeg.mode, 2);
  bs.putBits(config.mpeg.mode_ext, 2);
  bs.putBits(config.mpeg.copyright, 1);
  bs.putBits(config.mpeg.original, 1);
  bs.putBits(config.mpeg.emph, 2);

  if (config.mpeg.version == 3) {
    bs.putBits(0, 9);
    if (config.wave.channels == 2) {
      bs.putBits(si.private_bits, 3);
    } else {
      bs.putBits(si.private_bits, 5);
    }
  } else {
    bs.putBits(0, 8);
    if (config.wave.channels == 2) {
      bs.putBits(si.private_bits, 2);
    } else {
      bs.putBits(si.private_bits, 1);
    }
  }

  if (config.mpeg.version == 3) {
    for (int ch = 0; ch < config.wave.channels; ch++) {
      for (int band = 0; band < 4; band++) {
        bs.putBits(si.scfsi[ch][band], 1);
      }
    }
  }

  for (int gr = 0; gr < config.mpeg.granules_per_frame; gr++) {
    for (int ch = 0; ch < config.wave.channels; ch++) {
      final GrInfo gi = si.gr[gr][ch];

      bs.putBits(gi.part2_3_length, 12);
      bs.putBits(gi.big_values, 9);
      bs.putBits(gi.global_gain, 8);
      if (config.mpeg.version == 3) {
        bs.putBits(gi.scalefac_compress, 4);
      } else {
        bs.putBits(gi.scalefac_compress, 9);
      }
      bs.putBits(0, 1);

      for (int region = 0; region < 3; region++) {
        bs.putBits(gi.table_select[region], 5);
      }

      bs.putBits(gi.region0_count, 4);
      bs.putBits(gi.region1_count, 3);

      if (config.mpeg.version == 3) {
        bs.putBits(gi.preflag, 1);
      }
      bs.putBits(gi.scalefac_scale, 1);
      bs.putBits(gi.count1table_select, 1);
    }
  }
}

void _huffmanCodeBits(ShineGlobalConfig config, List<int> ix, GrInfo gi) {
  final BitStream bs = config.bs;
  final List<int> scalefac =
      shineScaleFactorBandIndex[config.mpeg.samplerate_index];

  int previousBits = bs.bitsCount;

  final int bigvalues = gi.big_values << 1;
  int scalefacIndex = gi.region0_count + 1;
  final int region1Start = scalefac[scalefacIndex];
  scalefacIndex += gi.region1_count + 1;
  final int region2Start = scalefac[scalefacIndex];

  for (int i = 0; i < bigvalues; i += 2) {
    final int idx = (i >= region1Start ? 1 : 0) + (i >= region2Start ? 1 : 0);
    final int tableIndex = gi.table_select[idx];
    if (tableIndex != 0) {
      int x = ix[i];
      int y = ix[i + 1];
      _shineHuffmanCode(bs, tableIndex, x, y);
    }
  }

  final HuffCodeTab h = shineHuffmanTable[gi.count1table_select + 32];
  final int count1End = bigvalues + (gi.count1 << 2);
  for (int i = bigvalues; i < count1End; i += 4) {
    final int v = ix[i];
    final int w = ix[i + 1];
    final int x = ix[i + 2];
    final int y = ix[i + 3];
    _shineHuffmanCoderCount1(bs, h, v, w, x, y);
  }

  int bits = bs.bitsCount - previousBits;
  bits = gi.part2_3_length - gi.part2_length - bits;
  if (bits > 0) {
    final int stuffingWords = bits ~/ 32;
    final int remainingBits = bits % 32;
    for (int i = 0; i < stuffingWords; i++) {
      bs.putBits(0xffffffff, 32);
    }
    if (remainingBits != 0) {
      final int mask = (1 << remainingBits) - 1;
      bs.putBits(mask, remainingBits);
    }
  }
}

void _shineHuffmanCoderCount1(
  BitStream bs,
  HuffCodeTab table,
  int v,
  int w,
  int x,
  int y,
) {
  final _ValueSign sv = _absAndSign(v);
  final _ValueSign sw = _absAndSign(w);
  final _ValueSign sx = _absAndSign(x);
  final _ValueSign sy = _absAndSign(y);

  final int p = sv.value + (sw.value << 1) + (sx.value << 2) + (sy.value << 3);
  bs.putBits(table.table[p], table.hlen[p]);

  int code = 0;
  int cbits = 0;
  if (sv.value != 0) {
    code = sv.sign;
    cbits = 1;
  }
  if (sw.value != 0) {
    code = (code << 1) | sw.sign;
    cbits++;
  }
  if (sx.value != 0) {
    code = (code << 1) | sx.sign;
    cbits++;
  }
  if (sy.value != 0) {
    code = (code << 1) | sy.sign;
    cbits++;
  }
  if (cbits != 0) {
    bs.putBits(code, cbits);
  }
}

void _shineHuffmanCode(BitStream bs, int tableSelect, int x, int y) {
  final _ValueSign sx = _absAndSign(x);
  final _ValueSign sy = _absAndSign(y);

  final HuffCodeTab table = shineHuffmanTable[tableSelect];
  final int ylen = table.ylen;

  if (tableSelect > 15) {
    final int linbits = table.linbits;
    int ext = 0;
    int xbits = 0;

    int xVal = sx.value;
    int yVal = sy.value;

    if (xVal > 14) {
      ext |= xVal - 15;
      xbits += linbits;
      xVal = 15;
    }
    if (xVal != 0) {
      ext = (ext << 1) | sx.sign;
      xbits++;
    }
    if (yVal > 14) {
      ext = (ext << linbits) | (yVal - 15);
      xbits += linbits;
      yVal = 15;
    }
    if (yVal != 0) {
      ext = (ext << 1) | sy.sign;
      xbits++;
    }

    final int idx = (xVal * ylen) + yVal;
    bs.putBits(table.table[idx], table.hlen[idx]);
    if (xbits != 0) {
      bs.putBits(ext, xbits);
    }
  } else {
    int code = table.table[(sx.value * ylen) + sy.value];
    int cbits = table.hlen[(sx.value * ylen) + sy.value];

    if (sx.value != 0) {
      code = (code << 1) | sx.sign;
      cbits++;
    }
    if (sy.value != 0) {
      code = (code << 1) | sy.sign;
      cbits++;
    }
    bs.putBits(code, cbits);
  }
}

class _ValueSign {
  const _ValueSign(this.value, this.sign);

  final int value;
  final int sign;
}

_ValueSign _absAndSign(int input) {
  if (input > 0) {
    return _ValueSign(input, 0);
  } else if (input < 0) {
    return _ValueSign(-input, 1);
  }
  return const _ValueSign(0, 0);
}
