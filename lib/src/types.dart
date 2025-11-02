// ignore_for_file: non_constant_identifier_names

import 'dart:typed_data';

import 'bitstream.dart';
import 'constants.dart';

/// Translation of `types.h` from the Shine C implementation.
///
/// The structure definitions are intentionally kept close to the original code
/// to simplify auditing.

class PrivShineWave {
  PrivShineWave({required this.channels, required this.samplerate});

  int channels;
  int samplerate;
}

class PrivShineMpeg {
  PrivShineMpeg({
    this.version = 0,
    this.layer = 0,
    this.granules_per_frame = 0,
    this.mode = 0,
    this.bitr = 0,
    this.emph = 0,
    this.padding = 0,
    this.bits_per_frame = 0,
    this.bits_per_slot = 8,
    this.frac_slots_per_frame = 0.0,
    this.slot_lag = 0.0,
    this.whole_slots_per_frame = 0,
    this.bitrate_index = 0,
    this.samplerate_index = 0,
    this.crc = 0,
    this.ext = 0,
    this.mode_ext = 0,
    this.copyright = 0,
    this.original = 0,
  });

  int version;
  int layer;
  int granules_per_frame;
  int mode;
  int bitr;
  int emph;
  int padding;
  int bits_per_frame;
  int bits_per_slot;
  double frac_slots_per_frame;
  double slot_lag;
  int whole_slots_per_frame;
  int bitrate_index;
  int samplerate_index;
  int crc;
  int ext;
  int mode_ext;
  int copyright;
  int original;
}

class L3Loop {
  Int32List? xr;
  final Int32List xrsq = Int32List(granuleSize);
  final Int32List xrabs = Int32List(granuleSize);
  int xrmax = 0;
  final List<int> en_tot = List<int>.filled(maxGranules, 0);
  final List<Int32List> en =
      List<Int32List>.generate(maxGranules, (_) => Int32List(21));
  final List<Int32List> xm =
      List<Int32List>.generate(maxGranules, (_) => Int32List(21));
  final List<int> xrmaxl = List<int>.filled(maxGranules, 0);
  final List<double> steptab = List<double>.filled(128, 0.0);
  final List<int> steptabi = List<int>.filled(128, 0);
  final List<int> int2idx = List<int>.filled(10000, 0);
}

class Mdct {
  Mdct() : cosL = List.generate(18, (_) => Int32List(36));

  final List<Int32List> cosL;
}

class Subband {
  Subband()
      : off = Int32List(maxChannels),
        fl = List.generate(sbLimit, (_) => Int32List(64)),
        x = List.generate(maxChannels, (_) => Int32List(hanSize));

  final Int32List off;
  final List<Int32List> fl;
  final List<Int32List> x;
}

class GrInfo {
  int part2_3_length = 0;
  int big_values = 0;
  int count1 = 0;
  int global_gain = 0;
  int scalefac_compress = 0;
  final List<int> table_select = List<int>.filled(3, 0);
  int region0_count = 0;
  int region1_count = 0;
  int preflag = 0;
  int scalefac_scale = 0;
  int count1table_select = 0;
  int part2_length = 0;
  int sfb_lmax = 0;
  int address1 = 0;
  int address2 = 0;
  int address3 = 0;
  int quantizerStepSize = 0;
  final List<int> slen = List<int>.filled(4, 0);

  void reset() {
    part2_3_length = 0;
    big_values = 0;
    count1 = 0;
    global_gain = 0;
    scalefac_compress = 0;
    for (int i = 0; i < table_select.length; i++) {
      table_select[i] = 0;
    }
    region0_count = 0;
    region1_count = 0;
    preflag = 0;
    scalefac_scale = 0;
    count1table_select = 0;
    part2_length = 0;
    sfb_lmax = 0;
    address1 = 0;
    address2 = 0;
    address3 = 0;
    quantizerStepSize = 0;
    for (int i = 0; i < slen.length; i++) {
      slen[i] = 0;
    }
  }
}

class ShineSideInfo {
  int private_bits = 0;
  int resvDrain = 0;
  final List<List<int>> scfsi =
      List<List<int>>.generate(maxChannels, (_) => List<int>.filled(4, 0));
  final List<List<GrInfo>> gr = List<List<GrInfo>>.generate(
      maxGranules, (_) => List<GrInfo>.generate(maxChannels, (_) => GrInfo()));

  void reset() {
    private_bits = 0;
    resvDrain = 0;
    for (int ch = 0; ch < maxChannels; ch++) {
      for (int band = 0; band < 4; band++) {
        scfsi[ch][band] = 0;
      }
    }
    for (int granule = 0; granule < maxGranules; granule++) {
      for (int ch = 0; ch < maxChannels; ch++) {
        gr[granule][ch].reset();
      }
    }
  }
}

class ShinePsyRatio {
  ShinePsyRatio()
      : l = List.generate(maxGranules,
            (_) => List.generate(maxChannels, (_) => List<double>.filled(21, 0)));

  final List<List<List<double>>> l;
}

class ShinePsyXmin {
  ShinePsyXmin()
      : l = List.generate(maxGranules,
            (_) => List.generate(maxChannels, (_) => List<double>.filled(21, 0)));

  final List<List<List<double>>> l;
}

class ShineScalefac {
  ShineScalefac()
      : l = List.generate(maxGranules,
            (_) => List.generate(maxChannels, (_) => Int32List(22))),
        s = List.generate(
            maxGranules,
            (_) => List.generate(maxChannels,
                (_) => List.generate(13, (_) => Int32List(3))));

  final List<List<Int32List>> l;
  final List<List<List<Int32List>>> s;
}

class PcmPointer {
  PcmPointer(this.data, [this.position = 0]);

  final Int16List data;
  int position;

  int get length => data.length;

  PcmPointer copyWith({int? position}) => PcmPointer(data, position ?? this.position);
}

class ShineGlobalConfig {
  ShineGlobalConfig({
    required this.wave,
    required this.mpeg,
    BitStream? bitStream,
  })  : bs = bitStream ?? BitStream();

  final PrivShineWave wave;
  final PrivShineMpeg mpeg;
  final BitStream bs;
  final ShineSideInfo side_info = ShineSideInfo();
  int sideinfo_len = 0;
  int mean_bits = 0;
  final ShinePsyRatio ratio = ShinePsyRatio();
  final ShineScalefac scalefactor = ShineScalefac();
  final List<PcmPointer?> buffer = List<PcmPointer?>.filled(maxChannels, null);
  final List<List<double>> pe = List<List<double>>.generate(
      maxChannels, (_) => List<double>.filled(maxGranules, 0.0));
  final List<List<Int32List>> l3_enc = List<List<Int32List>>.generate(
      maxChannels, (_) => List<Int32List>.generate(maxGranules, (_) => Int32List(granuleSize)));
  final List<List<Int32List>> mdct_freq = List<List<Int32List>>.generate(
      maxChannels, (_) => List<Int32List>.generate(maxGranules, (_) => Int32List(granuleSize)));
  final List<List<List<Int32List>>> l3_sb_sample =
      List<List<List<Int32List>>>.generate(
          maxChannels,
          (_) => List<List<Int32List>>.generate(
              maxGranules + 1, (_) => List<Int32List>.generate(18, (_) => Int32List(sbLimit))));
  int ResvSize = 0;
  int ResvMax = 0;
  final L3Loop l3loop = L3Loop();
  final Mdct mdct = Mdct();
  final Subband subband = Subband();
}
