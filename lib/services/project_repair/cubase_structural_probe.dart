import 'dart:convert';
import 'dart:typed_data';

/// Bounded, read-only preflight for Cubase/Nuendo RIFF/NUND archives.
///
/// Unlike standard RIFF/WAVE, Steinberg stores the container and chunk sizes
/// in big-endian order. A valid chunk table does NOT imply writable support.
class CubaseContainerManifest {
  const CubaseContainerManifest({
    required this.totalBytes,
    required this.chunks,
  });

  final int totalBytes;
  final List<CubaseContainerChunk> chunks;

  int get archiveCount => chunks.where((chunk) => chunk.tag == 'ARCH').length;

  Map<String, Object?> toJson() => {
    'total_bytes': totalBytes,
    'archive_count': archiveCount,
    'chunks': [for (final chunk in chunks) chunk.toJson()],
    'safe_to_rewrite': false,
  };

  static CubaseContainerManifest inspect(Uint8List bytes) {
    const maxBytes = 256 * 1024 * 1024;
    const maxChunks = 100000;
    if (bytes.length < 20 || bytes.length > maxBytes) {
      throw const FormatException('Invalid or excessive CPR container length');
    }
    final view = ByteData.sublistView(bytes);
    if (_sliceAscii(bytes, 0, 4) != 'RIFF' ||
        _sliceAscii(bytes, 8, 4) != 'NUND') {
      throw const FormatException('Not a RIFF/NUND CPR container');
    }
    // The stored length excludes the 12-byte RIFF/NUND prefix.
    if (view.getUint32(4, Endian.big) != bytes.length - 12) {
      throw const FormatException('CPR container length does not match file');
    }
    final chunks = <CubaseContainerChunk>[];
    var offset = 12;
    while (offset < bytes.length) {
      if (bytes.length - offset < 8) {
        throw const FormatException('Truncated CPR chunk header');
      }
      if (chunks.length >= maxChunks) {
        throw const FormatException('Excessive CPR chunk count');
      }
      final tag = _sliceAscii(bytes, offset, 4);
      final size = view.getUint32(offset + 4, Endian.big);
      final remaining = bytes.length - offset - 8;
      if (size > remaining) {
        throw FormatException('Truncated CPR $tag chunk');
      }
      chunks.add(CubaseContainerChunk(
        tag: tag,
        offset: offset,
        length: size,
      ));
      offset += 8 + size;
    }
    if (!chunks.any((chunk) => chunk.tag == 'ARCH')) {
      throw const FormatException('CPR does not contain an ARCH block');
    }
    return CubaseContainerManifest(
      totalBytes: bytes.length,
      chunks: List.unmodifiable(chunks),
    );
  }
}

class CubaseContainerChunk {
  const CubaseContainerChunk({
    required this.tag,
    required this.offset,
    required this.length,
  });

  final String tag;
  final int offset;
  final int length;

  Map<String, Object> toJson() => {
    'tag': tag,
    'offset': offset,
    'length': length,
  };
}

/// A Cubase attribute declaration, not a validated VST2/VST3 vendor identity.
///
/// Occurrences count matching serialized records, not necessarily unique
/// loaded plug-in instances. Internal channel-strip devices are preserved.
class CubasePluginUidEvidence {
  const CubasePluginUidEvidence({
    required this.name,
    required this.uid,
    required this.occurrences,
    required this.internalDevice,
  });

  final String name;
  final String uid;
  final int occurrences;
  final bool internalDevice;

  Map<String, Object> toJson() => {
    'name': name,
    'declared_uid': uid,
    'occurrences': occurrences,
    'internal_device': internalDevice,
    'vendor_identity_verified': false,
    'plugin_loadability': 'untested',
  };
}

/// Only accepts the exact typed attribute sequence:
/// "Plugin UID" -> "GUID" (32 uppercase/lowercase hex) -> "Plugin Name".
///
/// No binary values are patched, and no guessed GUID is emitted. This record
/// layout is observed on Cubase 10.5 specimens; other releases may use a
/// different encoding, in which case the result is incomplete, not empty.
class CubasePluginUidProbe {
  static const _internalNames = {
    'Standard Panner',
    'Stereo Combined Panner',
    'Stereo Panner',
    'Mono Panner',
    'VST MultiPanner',
    'Input Filter',
    'EQ',
    'Channel Strip',
    'Sampler Track',
  };
  static final _hex32 = RegExp(r'^[A-Fa-f0-9]{32}$');
  static final _uidKey = ascii.encode('Plugin UID\x00');

  static List<CubasePluginUidEvidence> inspect(Uint8List bytes) {
    const maxRecords = 30000;
    final view = ByteData.sublistView(bytes);
    final keys = <String, ({String name, String uid, int count})>{};
    var inspected = 0;
    for (var i = 4; i + 96 < bytes.length; i++) {
      if (bytes[i] != 0x50 || !_matches(bytes, i, _uidKey)) continue;
      if (++inspected > maxRecords) {
        throw const FormatException('Excessive CPR plug-in UID attributes');
      }
      if (view.getUint32(i - 4, Endian.big) != _uidKey.length) continue;
      final meta = i + _uidKey.length;
      if (meta + 8 > bytes.length ||
          view.getUint16(meta, Endian.big) != 2 ||
          view.getUint16(meta + 2, Endian.big) != 6 ||
          view.getUint32(meta + 4, Endian.big) != 1) {
        continue;
      }
      final guid = _taggedString(bytes, view, meta + 8, 'GUID');
      if (guid == null || !_hex32.hasMatch(guid.value)) continue;
      final plugin = _taggedString(bytes, view, guid.end, 'Plugin Name');
      if (plugin == null || plugin.value.isEmpty) continue;

      final key = plugin.value + '\x00' + guid.value.toUpperCase();
      final previous = keys[key];
      keys[key] = (
        name: plugin.value,
        uid: guid.value.toUpperCase(),
        count: (previous?.count ?? 0) + 1,
      );
    }

    return List.unmodifiable([
      for (final match in keys.values)
        CubasePluginUidEvidence(
          name: match.name,
          uid: match.uid,
          occurrences: match.count,
          internalDevice: _internalNames.contains(match.name.trim()),
        ),
    ]);
  }

  static ({String value, int end})? _taggedString(
    Uint8List bytes,
    ByteData view,
    int offset,
    String tag,
  ) {
    // The 4-byte key length includes its NUL terminator.
    final keyBytes = ascii.encode(tag + '\x00');
    final size = 4 + keyBytes.length + 2 + 4;
    if (offset < 0 || offset + size > bytes.length ||
        view.getUint32(offset, Endian.big) != keyBytes.length ||
        !_matches(bytes, offset + 4, keyBytes) ||
        view.getUint16(offset + 4 + keyBytes.length, Endian.big) != 8) {
      return null;
    }
    final lengthOffset = offset + 4 + keyBytes.length + 2;
    final length = view.getUint32(lengthOffset, Endian.big);
    if (length < 2 || length > 512 ||
        length > bytes.length - (lengthOffset + 4)) {
      return null;
    }
    final valueStart = lengthOffset + 4;
    final raw = bytes.sublist(valueStart, valueStart + length);
    final nul = raw.indexOf(0);
    // Accept Cubase's NUL-terminated UTF-8 BOM or legacy bare text.
    final textBytes = nul >= 0 ? raw.sublist(0, nul) : raw;
    final value = utf8.decode(textBytes, allowMalformed: true).trim();
    if (value.isEmpty || value.contains(RegExp(r'[\x00-\x1f]'))) {
      return null;
    }
    return (value: value, end: valueStart + length);
  }

  static bool _matches(Uint8List bytes, int offset, List<int> expected) {
    if (offset < 0 || offset + expected.length > bytes.length) return false;
    for (var j = 0; j < expected.length; j++) {
      if (bytes[offset + j] != expected[j]) return false;
    }
    return true;
  }
}

String _sliceAscii(Uint8List bytes, int start, int length) =>
    ascii.decode(bytes.sublist(start, start + length), allowInvalid: true);
