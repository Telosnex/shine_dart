const kSampleRates = [
  8000,
  11025,
  12000,
  16000,
  22050,
  24000,
  32000,
  44100,
  48000
];
const kBitrates = [
  8,
  16,
  24,
  32,
  40,
  48,
  56,
  64,
  80,
  96,
  112,
  128,
  144,
  160,
  192,
  224,
  256,
  320
];

/// About 1.2 seconds: enough frames for the padding pattern of 44.1 kHz and
/// for the bit reservoir to fill and drain.
int framesFor(int sampleRate) => sampleRate * 6 ~/ 5;

String configKey(int sampleRate, int channels, int bitrate) =>
    '$sampleRate/${channels == 2 ? 'stereo' : 'mono'}/$bitrate';
