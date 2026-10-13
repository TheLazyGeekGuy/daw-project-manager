import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import '../../models/sample_reference.dart';
import '../daw_parsers/ableton_project_parser.dart';
import '../daw_parsers/cubase_project_parser.dart';
import '../daw_parsers/flp_project_parser.dart';
import '../daw_parsers/reaper_project_parser.dart';
import '../daw_parsers/studio_one_project_parser.dart';

/// Project formats whose sample references can be read.
const _readable = {'.cpr', '.npr', '.als', '.flp', '.rpp', '.song'};

/// Whether [readProjectSampleReferences] can read the project at [filePath].
bool canReadSampleReferences(String filePath) =>
    _readable.contains(p.extension(filePath).toLowerCase());

/// The audio files the project at [filePath] references, read in a
/// background isolate.
///
/// Throws when the file can't be read or isn't the project its extension
/// says; callers report that project rather than lose the rest. Check
/// [canReadSampleReferences] first — an unsupported format throws too.
Future<List<SampleReference>> readProjectSampleReferences(
  String filePath,
) async {
  final ext = p.extension(filePath).toLowerCase();
  if (!_readable.contains(ext)) {
    throw UnsupportedError('No sample reader for $ext');
  }
  final bytes = await File(filePath).readAsBytes();
  return Isolate.run(() {
    switch (ext) {
      case '.cpr':
      case '.npr':
        final parser = CubaseProjectParser(bytes);
        if (!parser.isCubaseFile) {
          throw const FormatException('Not a Cubase project');
        }
        return parser.readSampleReferences();
      case '.als':
        // Gzipped since Live 8; plain XML before.
        String xml;
        try {
          xml = utf8.decode(gzip.decode(bytes), allowMalformed: true);
        } on FormatException {
          xml = utf8.decode(bytes, allowMalformed: true);
        }
        return AbletonProjectParser(XmlDocument.parse(xml))
            .readSampleReferences();
      case '.flp':
        return FlpProjectParser(bytes).readSampleReferences();
      case '.rpp':
        return ReaperProjectParser(utf8.decode(bytes, allowMalformed: true))
            .readSampleReferences();
      default:
        return StudioOneProjectParser(bytes).readSampleReferences();
    }
  });
}
