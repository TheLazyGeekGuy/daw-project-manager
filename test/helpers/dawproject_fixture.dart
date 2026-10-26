import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

Uint8List dawProjectFixture({
  String project =
      '<Project version="1.0"><Application name="Fixture" version="1"/></Project>',
  String metadata = '<MetaData><Title>Fixture</Title></MetaData>',
  Map<String, List<int>> files = const {},
}) {
  final archive = Archive();
  for (final entry in {
    'project.xml': utf8.encode(project),
    'metadata.xml': utf8.encode(metadata),
    ...files,
  }.entries) {
    archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}
