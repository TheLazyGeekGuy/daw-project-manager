import 'dart:typed_data';

/// A read-only capability declaration, not a claim of lossless conversion.
class ProjectFormatDescriptor {
  final String id;
  final String daw;
  final Set<String> extensions;
  final bool inspectionSupported;
  final bool nativeWritingVerified;
  final String? signature;

  const ProjectFormatDescriptor({
    required this.id,
    required this.daw,
    required this.extensions,
    this.inspectionSupported = false,
    this.nativeWritingVerified = false,
    this.signature,
  });
}

/// Registry of native project formats and safely detectable file signatures.
///
/// Extensions are hints; byte signatures take precedence when available.
class ProjectFormatRegistry {
  static const formats = <ProjectFormatDescriptor>[
    ProjectFormatDescriptor(id: 'cubase', daw: 'Cubase', extensions: {'.cpr'}, inspectionSupported: true, signature: 'RIFF/NUND'),
    ProjectFormatDescriptor(id: 'nuendo', daw: 'Nuendo', extensions: {'.npr'}, inspectionSupported: true, signature: 'RIFF/NUND'),
    ProjectFormatDescriptor(id: 'ableton', daw: 'Ableton Live', extensions: {'.als'}, inspectionSupported: true, signature: 'GZIP'),
    ProjectFormatDescriptor(id: 'flstudio', daw: 'FL Studio', extensions: {'.flp'}, inspectionSupported: true, signature: 'FLhd'),
    ProjectFormatDescriptor(id: 'reaper', daw: 'REAPER', extensions: {'.rpp'}, inspectionSupported: true, signature: '<REAPER_PROJECT'),
    ProjectFormatDescriptor(id: 'logic', daw: 'Logic Pro', extensions: {'.logicx'}),
    ProjectFormatDescriptor(id: 'bitwig', daw: 'Bitwig Studio', extensions: {'.bwproject'}),
    ProjectFormatDescriptor(id: 'studioone', daw: 'Studio One', extensions: {'.song'}, inspectionSupported: true),
    ProjectFormatDescriptor(id: 'protools', daw: 'Pro Tools', extensions: {'.ptx'}),
    ProjectFormatDescriptor(id: 'ardour', daw: 'Ardour', extensions: {'.ardour'}),
    ProjectFormatDescriptor(id: 'lmms', daw: 'LMMS', extensions: {'.mmp', '.mmpz'}),
    ProjectFormatDescriptor(id: 'waveform', daw: 'Tracktion Waveform', extensions: {'.tracktionedit'}),
    ProjectFormatDescriptor(id: 'renoise', daw: 'Renoise', extensions: {'.xrns'}),
    ProjectFormatDescriptor(id: 'dawproject', daw: 'DAWproject', extensions: {'.dawproject'}),
    ProjectFormatDescriptor(id: 'aaf', daw: 'AAF interchange', extensions: {'.aaf'}),
    ProjectFormatDescriptor(id: 'midi', daw: 'Standard MIDI', extensions: {'.mid', '.midi'}, signature: 'MThd'),
  ];

  static ProjectFormatDescriptor? byExtension(String path) {
    final file = path.replaceAll('\\', '/').split('/').last.toLowerCase();
    for (final format in formats) {
      if (format.extensions.any(file.endsWith)) return format;
    }
    return null;
  }

  /// Return null for conflicting signatures rather than mislabeling a project.
  /// This method does not read from disk or execute any plug-ins.
  static ProjectFormatDescriptor? detect(String path, Uint8List header) {
    final candidate = byExtension(path);
    if (candidate == null) return null;
    bool starts(String s, [int offset = 0]) {
      final bytes = s.codeUnits;
      if (header.length < offset + bytes.length) return false;
      for (var i = 0; i < bytes.length; i++) {
        if (header[offset + i] != bytes[i]) return false;
      }
      return true;
    }

    switch (candidate.signature) {
      case 'RIFF/NUND':
        return starts('RIFF') && starts('NUND', 8) ? candidate : null;
      case 'GZIP':
        return header.length >= 2 && header[0] == 0x1f && header[1] == 0x8b ? candidate : null;
      case 'FLhd':
        return starts('FLhd') ? candidate : null;
      case '<REAPER_PROJECT':
        return starts('<REAPER_PROJECT') ? candidate : null;
      case 'MThd':
        return starts('MThd') ? candidate : null;
      default:
        return candidate;
    }
  }
}
