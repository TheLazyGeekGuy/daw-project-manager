import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:file_selector/file_selector.dart';

/// Shows a save dialog and writes [bytes] wherever the user chooses.
///
/// file_picker writes the file itself, on every platform: a phone has no
/// path for the app to write to, only what the system picker hands back.
/// Returns where it went ([savedLocation]), or null when cancelled.
Future<String?> saveBytesWithDialog({
  required String fileName,
  required Uint8List bytes,
  String? dialogTitle,
  FileType type = FileType.any,
  List<String>? allowedExtensions,
}) async {
  final uri = await FilePicker.saveFile(
    fileName: fileName,
    bytes: bytes,
    dialogTitle: dialogTitle,
    type: type,
    allowedExtensions: allowedExtensions,
  );
  return savedLocation(uri);
}

/// [saveBytesWithDialog] for text, written as UTF-8.
Future<String?> saveTextWithDialog({
  required String fileName,
  required String text,
  String? dialogTitle,
  FileType type = FileType.any,
  List<String>? allowedExtensions,
}) =>
    saveBytesWithDialog(
      fileName: fileName,
      bytes: utf8.encode(text),
      dialogTitle: dialogTitle,
      type: type,
      allowedExtensions: allowedExtensions,
    );

/// Asks only for a path to save to, for content too big to hold in memory
/// (zips streamed to disk), which file_picker can't do: its save dialog
/// writes bytes it is handed. Desktop only — file_selector has no save
/// dialog on phones — and without a title, which it can't set.
Future<String?> pickSavePath({
  required String fileName,
  List<String>? allowedExtensions,
}) async {
  final location = await getSaveLocation(
    suggestedName: fileName,
    acceptedTypeGroups: [
      if (allowedExtensions != null) XTypeGroup(extensions: allowedExtensions),
    ],
  );
  return location?.path;
}

/// Where a save dialog put a file, for showing to the user: a filesystem
/// path, or — on a phone, where the system picker decides — its URI.
String? savedLocation(Uri? uri) {
  if (uri == null) return null;
  return uri.scheme == 'file' ? uri.toFilePath() : uri.toString();
}
