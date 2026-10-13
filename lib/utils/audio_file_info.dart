import 'dart:io';
import 'dart:typed_data';

/// How long the audio file at [path] plays, read from its header alone —
/// for sorting thousands of samples into one-shots, loops and stems, where
/// loading each one in a player would take minutes.
///
/// Reads WAV (`RIFF`/`WAVE`), AIFF/AIFC (`FORM`) and FLAC (`STREAMINFO`).
/// Null for anything else (MP3, OGG…), a damaged header or an unreadable
/// file; never throws.
Future<Duration?> readAudioDuration(String path) async {
  RandomAccessFile? file;
  try {
    file = await File(path).open();
    final length = await file.length();
    final head = await file.read(12);
    if (head.length < 12) return null;
    final id = String.fromCharCodes(head.sublist(0, 4));
    final form = String.fromCharCodes(head.sublist(8, 12));
    if (id == 'RIFF' && form == 'WAVE') return await _wav(file, length);
    if (id == 'FORM' && (form == 'AIFF' || form == 'AIFC')) {
      return await _aiff(file, length);
    }
    if (id.startsWith('fLaC')) return await _flac(file);
    return null;
  } catch (_) {
    return null;
  } finally {
    await file?.close();
  }
}

/// Walks a chunked file from offset 12, calling [visit] with each chunk's
/// id, body offset and size until it returns non-null.
Future<T?> _chunks<T>(
  RandomAccessFile file,
  int length,
  Endian endian,
  Future<T?> Function(String id, int body, int size) visit,
) async {
  var pos = 12;
  for (var guard = 0; guard < 512 && pos + 8 <= length; guard++) {
    await file.setPosition(pos);
    final header = await file.read(8);
    if (header.length < 8) return null;
    final id = String.fromCharCodes(header.sublist(0, 4));
    final size = ByteData.sublistView(header).getUint32(4, endian);
    final result = await visit(id, pos + 8, size);
    if (result != null) return result;
    pos += 8 + size + (size.isOdd ? 1 : 0);
  }
  return null;
}

Future<Duration?> _wav(RandomAccessFile file, int length) async {
  int? byteRate;
  return _chunks<Duration>(file, length, Endian.little, (id, body, size) async {
    if (id == 'fmt ' && size >= 16) {
      await file.setPosition(body);
      final fmt = ByteData.sublistView(await file.read(16));
      byteRate = fmt.getUint32(8, Endian.little);
    } else if (id == 'data') {
      final rate = byteRate;
      if (rate == null || rate == 0) return null;
      // A recorder that never closed its file leaves the size at 0 or
      // past the end; what is actually there is the better guess.
      final available = length - body;
      final bytes = size == 0 || size > available ? available : size;
      return Duration(microseconds: (bytes * 1000000 / rate).round());
    }
    return null;
  });
}

Future<Duration?> _aiff(RandomAccessFile file, int length) =>
    _chunks<Duration>(file, length, Endian.big, (id, body, size) async {
      if (id != 'COMM' || size < 18) return null;
      await file.setPosition(body);
      final comm = ByteData.sublistView(await file.read(18));
      final frames = comm.getUint32(2);
      final rate = _extended(comm, 8);
      if (rate == null || rate <= 0) return null;
      return Duration(microseconds: (frames * 1000000 / rate).round());
    });

/// An 80-bit IEEE 754 extended float, which is how AIFF stores its rate.
double? _extended(ByteData data, int offset) {
  final exponent = data.getUint16(offset) & 0x7FFF;
  final mantissa = data.getUint32(offset + 2) * 4294967296.0 +
      data.getUint32(offset + 6);
  if (exponent == 0 && mantissa == 0) return 0;
  if (exponent == 0x7FFF) return null;
  return mantissa * _pow2(exponent - 16383 - 63);
}

double _pow2(int e) {
  var r = 1.0;
  if (e >= 0) {
    for (var i = 0; i < e; i++) {
      r *= 2;
    }
  } else {
    for (var i = 0; i < -e; i++) {
      r /= 2;
    }
  }
  return r;
}

Future<Duration?> _flac(RandomAccessFile file) async {
  // "fLaC", then the first metadata block, which is always STREAMINFO:
  // a 4-byte block header and 34 bytes of body.
  await file.setPosition(4);
  final block = await file.read(4 + 34);
  if (block.length < 38 || (block[0] & 0x7F) != 0) return null;
  final info = block.sublist(4);
  // Bits 80–99: sample rate (20), then channels (3), bits (5), and 36 bits
  // of total samples.
  final rate = (info[10] << 12) | (info[11] << 4) | (info[12] >> 4);
  final total = ((info[13] & 0x0F) * 4294967296) +
      ((info[14] << 24) | (info[15] << 16) | (info[16] << 8) | info[17]);
  if (rate == 0 || total == 0) return null;
  return Duration(microseconds: (total * 1000000 / rate).round());
}
