import 'dart:convert';
import 'dart:typed_data';

/// What a Windows shortcut launches.
class ShellLink {
  const ShellLink({required this.target, required this.arguments});

  /// The local path it points at, or null for a network target or a
  /// shortcut without link info.
  final String? target;
  final String arguments;
}

// LinkFlags (MS-SHLLINK 2.1.1).
const _hasLinkTargetIdList = 1 << 0;
const _hasLinkInfo = 1 << 1;
const _hasName = 1 << 2;
const _hasRelativePath = 1 << 3;
const _hasWorkingDir = 1 << 4;
const _hasArguments = 1 << 5;
const _hasIconLocation = 1 << 6;
const _isUnicode = 1 << 7;

// LinkInfoFlags (MS-SHLLINK 2.3).
const _volumeIdAndLocalBasePath = 1 << 0;

const _headerSize = 0x4C;

/// Reads a `.lnk` file's target path and arguments, or returns null when the
/// bytes aren't a shortcut. Just enough of MS-SHLLINK for the Startup folder
/// check: whether the shortcut still points where it should, and with which
/// flag. Reading it in Dart costs nothing at startup, where asking the
/// shell's COM object would mean spawning PowerShell on every launch.
///
/// An ANSI path is decoded as Latin-1 — exact for ASCII. A non-ASCII path in
/// another code page may read differently from the real one; Windows then
/// normally stores the Unicode copy as well, which is preferred.
ShellLink? parseShellLink(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  int? u16(int at) =>
      at >= 0 && at + 2 <= bytes.length ? data.getUint16(at, Endian.little) : null;
  int? u32(int at) =>
      at >= 0 && at + 4 <= bytes.length ? data.getUint32(at, Endian.little) : null;

  String? ansiZ(int at) {
    if (at < 0 || at >= bytes.length) return null;
    var end = at;
    while (end < bytes.length && bytes[end] != 0) {
      end++;
    }
    return latin1.decode(bytes.sublist(at, end));
  }

  String? unicodeZ(int at) {
    final units = <int>[];
    for (var i = at; ; i += 2) {
      final unit = u16(i);
      if (unit == null) return null;
      if (unit == 0) break;
      units.add(unit);
    }
    return String.fromCharCodes(units);
  }

  if (u32(0) != _headerSize) return null;
  final flags = u32(0x14);
  if (flags == null) return null;
  var offset = _headerSize;

  if (flags & _hasLinkTargetIdList != 0) {
    final idListSize = u16(offset);
    if (idListSize == null) return null;
    offset += 2 + idListSize;
  }

  String? target;
  if (flags & _hasLinkInfo != 0) {
    final start = offset;
    final size = u32(start);
    final infoHeaderSize = u32(start + 4);
    final infoFlags = u32(start + 8);
    final basePathOffset = u32(start + 16);
    final suffixOffset = u32(start + 24);
    if (size == null ||
        infoHeaderSize == null ||
        infoFlags == null ||
        basePathOffset == null ||
        suffixOffset == null) {
      return null;
    }
    if (infoFlags & _volumeIdAndLocalBasePath != 0) {
      String? base;
      String? suffix;
      if (infoHeaderSize >= 0x24) {
        final baseUnicode = u32(start + 28);
        final suffixUnicode = u32(start + 32);
        if (baseUnicode != null && baseUnicode != 0) {
          base = unicodeZ(start + baseUnicode);
        }
        if (suffixUnicode != null && suffixUnicode != 0) {
          suffix = unicodeZ(start + suffixUnicode);
        }
      }
      base ??= ansiZ(start + basePathOffset);
      suffix ??= suffixOffset == 0 ? '' : ansiZ(start + suffixOffset);
      if (base == null || suffix == null) return null;
      target = base + suffix;
    }
    offset = start + size;
  }

  // StringData, in this fixed order, each present only if flagged.
  final unicode = flags & _isUnicode != 0;
  var arguments = '';
  for (final flag in const [
    _hasName,
    _hasRelativePath,
    _hasWorkingDir,
    _hasArguments,
    _hasIconLocation,
  ]) {
    if (flags & flag == 0) continue;
    final count = u16(offset);
    if (count == null) return null;
    offset += 2;
    final length = unicode ? count * 2 : count;
    if (offset + length > bytes.length) return null;
    final text = unicode
        ? String.fromCharCodes([
            for (var i = 0; i < count; i++)
              data.getUint16(offset + i * 2, Endian.little),
          ])
        : latin1.decode(bytes.sublist(offset, offset + length));
    offset += length;
    if (flag == _hasArguments) arguments = text;
  }

  return ShellLink(target: target, arguments: arguments);
}
