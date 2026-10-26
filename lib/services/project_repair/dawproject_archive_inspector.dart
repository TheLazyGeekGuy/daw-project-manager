import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:xml/xml.dart';

/// Structural evidence from the open DAWproject 1.0 container.
///
/// This is a bounded ZIP/XML preflight, not complete XSD validation and not
/// evidence that a destination DAW has restored the session correctly.
class DawProjectSummary {
  const DawProjectSummary({
    required this.version,
    required this.applicationName,
    required this.tracks,
    required this.plugins,
    required this.entryCount,
    required this.externalReferences,
    required this.missingReferences,
    required this.duplicateIds,
    required this.noteCount,
    required this.clipCount,
    required this.automationPointCount,
  });

  final String version, applicationName;
  final List<DawProjectTrackSummary> tracks;
  final List<DawProjectPluginSummary> plugins;
  final int entryCount, noteCount, clipCount, automationPointCount;
  final List<String> externalReferences, missingReferences, duplicateIds;

  bool get selfContained =>
      externalReferences.isEmpty && missingReferences.isEmpty;

  Map<String, Object?> toJson() => {
    'format_version': version,
    'application': applicationName,
    'archive_entries': entryCount,
    'tracks': [for (final track in tracks) track.toJson()],
    'plugins': [for (final plugin in plugins) plugin.toJson()],
    'note_count': noteCount,
    'clip_count': clipCount,
    'automation_point_count': automationPointCount,
    'external_references': externalReferences,
    'missing_references': missingReferences,
    'duplicate_ids': duplicateIds,
    'self_contained': selfContained,
    'validation': 'bounded_container_and_xml_structure',
    'full_xsd_validation': false,
    'native_daw_reopen_verified': false,
  };
}

class DawProjectTrackSummary {
  const DawProjectTrackSummary(this.id, this.name, this.isMaster);
  final String? id;
  final String name;
  final bool isMaster;
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'is_master': isMaster,
  };
}

class DawProjectPluginSummary {
  const DawProjectPluginSummary({
    required this.id,
    required this.name,
    required this.format,
    required this.pluginId,
    required this.vendor,
    required this.statePath,
    required this.stateSha256,
  });
  final String? id, pluginId, vendor, statePath, stateSha256;
  final String name, format;
  Map<String, Object?> toJson() => {
    'instance_id': id,
    'name': name,
    'format': format,
    'plugin_id': pluginId,
    'vendor': vendor,
    'state_path': statePath,
    'state_sha256': stateSha256,
  };
}

class DawProjectArchiveInspector {
  static const maxArchiveBytes = 512 * 1024 * 1024;
  static const maxXmlBytes = 8 * 1024 * 1024;
  static const maxStateBytes = 16 * 1024 * 1024;

  static DawProjectSummary inspect(Uint8List bytes) {
    final archive = _BoundedZip(bytes);
    final projectEntry = archive.entries['project.xml'];
    final metadataEntry = archive.entries['metadata.xml'];
    if (projectEntry == null || metadataEntry == null) {
      throw const FormatException(
        'DAWproject requires project.xml and metadata.xml',
      );
    }
    final project = _xml(archive.read(projectEntry, maxXmlBytes), 'Project');
    _xml(archive.read(metadataEntry, maxXmlBytes), 'MetaData');
    final root = project.rootElement;
    final version = root.getAttribute('version');
    if (version != '1.0') {
      throw const FormatException('Unsupported DAWproject format version');
    }
    final application = root.getElement('Application');
    if (application == null || application.getAttribute('name') == null) {
      throw const FormatException('DAWproject application metadata is missing');
    }
    final elements = root.descendants.whereType<XmlElement>().toList();
    if (elements.length > 200000) {
      throw const FormatException('DAWproject XML element count exceeds limit');
    }
    final external = <String>{};
    final missing = <String>{};
    final ids = <String>{};
    final duplicates = <String>{};
    for (final element in elements) {
      final id = element.getAttribute('id');
      if (id != null && !ids.add(id)) duplicates.add(id);
      if (!const {'File', 'State'}.contains(element.name.local)) continue;
      final path = element.getAttribute('path');
      if (path == null || path.isEmpty) {
        throw const FormatException('DAWproject file reference has no path');
      }
      final isExternal = element.getAttribute('external');
      if (isExternal != null &&
          !const {'true', 'false', '1', '0'}.contains(isExternal)) {
        throw const FormatException('Invalid external file reference flag');
      }
      if (isExternal == 'true' || isExternal == '1') {
        external.add(path);
      } else {
        _BoundedZip.validatePath(path);
        if (!archive.entries.containsKey(path)) missing.add(path);
      }
    }
    final tracks = <DawProjectTrackSummary>[
      for (final track in elements.where((e) => e.name.local == 'Track'))
        DawProjectTrackSummary(
          track.getAttribute('id'),
          track.getAttribute('name') ?? '',
          track.getElement('Channel')?.getAttribute('role') == 'master',
        ),
    ];
    const pluginFormats = {
      'Vst2Plugin': 'vst2',
      'Vst3Plugin': 'vst3',
      'ClapPlugin': 'clap',
      'AuPlugin': 'au',
    };
    final plugins = <DawProjectPluginSummary>[];
    var stateBudget = 64 * 1024 * 1024;
    for (final plugin in elements) {
      final format = pluginFormats[plugin.name.local];
      if (format == null) continue;
      final state = plugin.getElement('State');
      final statePath = state?.getAttribute('path');
      final stateEntry = archive.entries[statePath];
      String? stateHash;
      if (stateEntry != null &&
          !external.contains(statePath) &&
          stateEntry.size <= maxStateBytes &&
          stateEntry.size <= stateBudget) {
        stateHash = sha256
            .convert(archive.read(stateEntry, maxStateBytes))
            .toString();
        stateBudget -= stateEntry.size;
      }
      plugins.add(
        DawProjectPluginSummary(
          id: plugin.getAttribute('id'),
          name: plugin.getAttribute('deviceName') ?? '',
          format: format,
          pluginId: plugin.getAttribute('deviceID'),
          vendor: plugin.getAttribute('deviceVendor'),
          statePath: statePath,
          stateSha256: stateHash,
        ),
      );
    }
    return DawProjectSummary(
      version: version!,
      applicationName: application.getAttribute('name')!,
      tracks: List.unmodifiable(tracks),
      plugins: List.unmodifiable(plugins),
      entryCount: archive.entries.length,
      externalReferences: List.unmodifiable(external),
      missingReferences: List.unmodifiable(missing),
      duplicateIds: List.unmodifiable(duplicates),
      noteCount: elements.where((e) => e.name.local == 'Note').length,
      clipCount: elements.where((e) => e.name.local == 'Clip').length,
      automationPointCount: elements
          .where(
            (e) => const {
              'RealPoint',
              'IntegerPoint',
              'BoolPoint',
              'EnumPoint',
              'TimeSignaturePoint',
            }.contains(e.name.local),
          )
          .length,
    );
  }

  static XmlDocument _xml(Uint8List bytes, String root) {
    final text = utf8.decode(bytes);
    if (RegExp(r'<!\s*(DOCTYPE|ENTITY)', caseSensitive: false).hasMatch(text)) {
      throw const FormatException(
        'DTD and entity declarations are not allowed',
      );
    }
    final document = XmlDocument.parse(text);
    if (document.rootElement.name.qualified != root) {
      throw FormatException('Expected $root XML document');
    }
    return document;
  }
}

/// ZIP32 only. Metadata is checked before any payload inflation. Media entries
/// are never decompressed; XML and state decoding have enforced output limits.
class _BoundedZip {
  _BoundedZip(this.bytes) : view = ByteData.sublistView(bytes) {
    if (bytes.length < 22 ||
        bytes.length > DawProjectArchiveInspector.maxArchiveBytes) {
      throw const FormatException('DAWproject archive outside size limits');
    }
    var end = -1;
    final min = bytes.length > 65557 ? bytes.length - 65557 : 0;
    for (var i = bytes.length - 22; i >= min; i--) {
      if (_u32(i) == 0x06054b50 && i + 22 + _u16(i + 20) == bytes.length) {
        end = i;
        break;
      }
    }
    if (end < 0) throw const FormatException('ZIP directory not found');
    final count = _u16(end + 10);
    final size = _u32(end + 12);
    var offset = _u32(end + 16);
    if (_u16(end + 4) != 0 ||
        _u16(end + 6) != 0 ||
        count != _u16(end + 8) ||
        count > 10000 ||
        count == 0 ||
        size == 0xffffffff ||
        offset == 0xffffffff ||
        offset + size != end) {
      throw const FormatException('Unsupported or excessive ZIP directory');
    }
    final foldedNames = <String>{};
    var totalSize = 0;
    for (var i = 0; i < count; i++) {
      if (offset + 46 > end || _u32(offset) != 0x02014b50) {
        throw const FormatException('Truncated ZIP central directory');
      }
      final flags = _u16(offset + 8);
      final method = _u16(offset + 10);
      final crc = _u32(offset + 16);
      final compressed = _u32(offset + 20);
      final expanded = _u32(offset + 24);
      final nameLength = _u16(offset + 28);
      final extraLength = _u16(offset + 30);
      final commentLength = _u16(offset + 32);
      final local = _u32(offset + 42);
      final next = offset + 46 + nameLength + extraLength + commentLength;
      if (next > end ||
          nameLength == 0 ||
          compressed == 0xffffffff ||
          expanded == 0xffffffff ||
          local == 0xffffffff ||
          (flags & 1) != 0 ||
          !const {0, 8}.contains(method) ||
          _u16(offset + 34) != 0) {
        throw const FormatException('Unsupported ZIP member');
      }
      final name = utf8.decode(
        bytes.sublist(offset + 46, offset + 46 + nameLength),
      );
      validatePath(name);
      if (!foldedNames.add(name.toLowerCase())) {
        throw const FormatException('Duplicate or case-colliding ZIP member');
      }
      final unixMode = (_u32(offset + 38) >> 16) & 0xf000;
      if (unixMode == 0xa000) {
        throw const FormatException('ZIP symlinks are not allowed');
      }
      totalSize += expanded;
      if (totalSize > 4 * 1024 * 1024 * 1024 ||
          local + 30 > _u32(end + 16) ||
          _u32(local) != 0x04034b50 ||
          _u16(local + 6) != flags ||
          _u16(local + 8) != method) {
        throw const FormatException('Invalid ZIP member bounds');
      }
      final localNameLength = _u16(local + 26);
      final dataOffset = local + 30 + localNameLength + _u16(local + 28);
      if (dataOffset + compressed > _u32(end + 16) ||
          local + 30 + localNameLength > _u32(end + 16) ||
          utf8.decode(
                bytes.sublist(local + 30, local + 30 + localNameLength),
              ) !=
              name) {
        throw const FormatException('ZIP local and directory entries disagree');
      }
      if (!name.endsWith('/')) {
        entries[name] = _ZipEntry(
          dataOffset,
          compressed,
          expanded,
          method,
          crc,
        );
      }
      offset = next;
    }
    if (offset != end) {
      throw const FormatException('ZIP directory size mismatch');
    }
  }

  final Uint8List bytes;
  final ByteData view;
  final entries = <String, _ZipEntry>{};
  int _u16(int at) => view.getUint16(at, Endian.little);
  int _u32(int at) => view.getUint32(at, Endian.little);

  static void validatePath(String path) {
    if (path.isEmpty ||
        path.startsWith('/') ||
        path.contains('\\') ||
        path.contains(':') ||
        path.contains('\u0000') ||
        path.split('/').any((part) => part == '..' || part == '.')) {
      throw const FormatException('Unsafe DAWproject archive path');
    }
  }

  Uint8List read(_ZipEntry entry, int limit) {
    if (entry.size > limit) {
      throw const FormatException('ZIP payload exceeds limit');
    }
    final input = Uint8List.sublistView(
      bytes,
      entry.offset,
      entry.offset + entry.compressed,
    );
    final sink = _BoundedBytesSink(limit);
    if (entry.method == 0) {
      sink.add(input);
    } else {
      final converter = ZLibDecoder(raw: true).startChunkedConversion(sink);
      converter.add(input);
      converter.close();
    }
    final result = sink.builder.takeBytes();
    if (result.length != entry.size || _crc32(result) != entry.crc) {
      throw const FormatException('ZIP payload checksum or length mismatch');
    }
    return result;
  }

  static int _crc32(Uint8List bytes) {
    var crc = 0xffffffff;
    for (final byte in bytes) {
      crc ^= byte;
      for (var bit = 0; bit < 8; bit++) {
        crc = (crc >> 1) ^ ((crc & 1) == 1 ? 0xedb88320 : 0);
      }
    }
    return crc ^ 0xffffffff;
  }
}

class _ZipEntry {
  const _ZipEntry(
    this.offset,
    this.compressed,
    this.size,
    this.method,
    this.crc,
  );
  final int offset, compressed, size, method, crc;
}

class _BoundedBytesSink implements Sink<List<int>> {
  _BoundedBytesSink(this.limit);
  final int limit;
  final builder = BytesBuilder(copy: false);
  @override
  void add(List<int> data) {
    if (builder.length + data.length > limit) {
      throw const FormatException('ZIP decompression exceeds limit');
    }
    builder.add(data);
  }

  @override
  void close() {}
}
