import 'dart:typed_data';

/// Synthetic records matching the two reverse-engineered AllToMidi layouts.
/// This is not a Cubase-authored project or evidence of complete ALL support.
Uint8List legacyAllFixture({bool fixed = false, bool repeatedPart = false}) {
  final bytes = Uint8List(1400);
  final view = ByteData.sublistView(bytes);
  view.setUint32(0xa2, 120000, Endian.big);
  // A compact time-signature table with an explicit sentinel.
  bytes.setRange(192, 204, [0, 0, 0, 0, 2, 0, 3, 4, 127, 255, 255, 255]);
  void name(int at, int record) {
    view.setUint16(at - 18, record, Endian.big);
    view.setUint16(at - 16, 0, Endian.big);
    bytes[at - 8] = 0x99;
    bytes[at - 5] = 2;
    bytes.setRange(at, at + 4, 'Keys'.codeUnits);
  }

  name(256, 0); // Track definition.
  void part(int at, int record, int position) {
    name(at, record);
    bytes.setRange(at - 33, at - 30, [
      position >> 16 & 255,
      position >> 8 & 255,
      position & 255,
    ]);
    if (fixed) {
      bytes.setRange(at + 139, at + 155, [
        0,
        60,
        0,
        0x90,
        60,
        100,
        0,
        0,
        0,
        60,
        0,
        0,
        0,
        0,
        0,
        0,
      ]);
      bytes.setRange(at + 155, at + 163, [255, 255, 255, 0, 0, 0, 0, 0]);
    } else {
      bytes.setRange(at + 42, at + 54, [
        60,
        0,
        1,
        128,
        0x90,
        100,
        0,
        0,
        1,
        128,
        0,
        0,
      ]);
      bytes.setRange(at + 54, at + 58, [0, 255, 255, 255]);
    }
  }

  part(512, 1, 0);
  if (repeatedPart) part(900, 2, fixed ? 30720 : 768);
  return bytes;
}
