import 'package:crypto/crypto.dart';
import 'package:shine_dart/shine.dart';
import 'package:test/test.dart';

import 'c_reference_digests.dart';
import 'support/configs.dart';
import 'support/encode.dart';
import 'support/signal.dart';

/// shine_dart is a translation of the C encoder: its output must be the C
/// output, byte for byte, on every platform (the VM, dart2js, dart2wasm).
void main() {
  test('the reference covers every supported configuration', () {
    final supported = <String>[
      for (final rate in kSampleRates)
        for (final channels in [1, 2])
          for (final bitrate in kBitrates)
            if (shineCheckConfig(rate, bitrate) >= 0)
              configKey(rate, channels, bitrate),
    ];
    expect(kCReferenceDigests.keys, unorderedEquals(supported));
  });

  for (final rate in kSampleRates) {
    for (final channels in [1, 2]) {
      test('$rate Hz ${channels == 2 ? 'stereo' : 'mono'}: same bytes as C',
          () {
        final pcm = testSignal(rate, channels, framesFor(rate));
        final mismatched = <String>[];
        for (final bitrate in kBitrates) {
          final key = configKey(rate, channels, bitrate);
          final expected = kCReferenceDigests[key];
          if (expected == null) continue;
          final mp3 = encodeLikeShineenc(pcm,
              sampleRate: rate, channels: channels, bitrate: bitrate);
          if ('${sha256.convert(mp3)}' != expected) mismatched.add(key);
        }
        expect(mismatched, isEmpty);
      });
    }
  }
}
