import 'dart:async';
import 'dart:convert';

import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/auth_io.dart' as auth_io;
import 'package:http/http.dart' as http;

/// One file (or folder) in [FakeDrive].
class FakeDriveFile {
  FakeDriveFile({
    required this.id,
    required this.name,
    required this.parents,
    required this.mimeType,
    required this.modifiedTime,
    this.description,
    List<int>? content,
  }) : content = content ?? const [];

  final String id;
  String name;
  List<String> parents;
  String mimeType;
  DateTime modifiedTime;
  String? description;
  List<int> content;

  bool get isFolder => mimeType == FakeDrive.folderMimeType;

  String get text => utf8.decode(content);

  Map<String, dynamic> toJson() => {
        'kind': 'drive#file',
        'id': id,
        'name': name,
        'mimeType': mimeType,
        'parents': parents,
        'modifiedTime': modifiedTime.toUtc().toIso8601String(),
        if (description != null) 'description': description,
        'size': '${content.length}',
      };
}

/// An in-memory Google Drive, served through the real `googleapis` client.
///
/// Speaks just enough of the Drive v3 REST API for the sync service: list
/// with the `q` clauses it uses, get (metadata or `alt=media`), create and
/// update (plain JSON or multipart uploads), copy, delete, and about. Every
/// write moves a fake clock one second on, so `modifiedTime` is strictly
/// increasing and tests can tell writes apart.
class FakeDrive extends http.BaseClient {
  static const folderMimeType = 'application/vnd.google-apps.folder';

  final Map<String, FakeDriveFile> files = {};
  DateTime clock = DateTime.utc(2026, 1, 1, 12);
  String userEmail = 'musician@example.com';
  int _nextId = 1;

  /// When set, every request fails with this HTTP status.
  int? failWithStatus;

  /// Requests seen, as "METHOD path", for asserting what was called.
  final List<String> log = [];

  drive.DriveApi get api => drive.DriveApi(this);

  /// A desktop auth client over this Drive, so the service counts as
  /// signed in (it wants both an auth client and an API).
  auth_io.AutoRefreshingAuthClient get authClient => _FakeAuthClient(this);

  DateTime _tick() => clock = clock.add(const Duration(seconds: 1));

  FakeDriveFile? named(String name, {String? parent}) {
    for (final f in files.values) {
      if (f.name == name && (parent == null || f.parents.contains(parent))) {
        return f;
      }
    }
    return null;
  }

  List<FakeDriveFile> childrenOf(String parentId) =>
      files.values.where((f) => f.parents.contains(parentId)).toList();

  /// Puts a file straight into the fake, as another device would have.
  FakeDriveFile seed({
    required String name,
    required String parent,
    List<int>? content,
    String mimeType = 'application/json',
    String? description,
  }) {
    final existing = named(name, parent: parent);
    if (existing != null) {
      existing
        ..content = content ?? existing.content
        ..description = description ?? existing.description
        ..modifiedTime = _tick();
      return existing;
    }
    final file = FakeDriveFile(
      id: 'f${_nextId++}',
      name: name,
      parents: [parent],
      mimeType: mimeType,
      modifiedTime: _tick(),
      description: description,
      content: content,
    );
    files[file.id] = file;
    return file;
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = await request.finalize().toBytes();
    final segments = request.url.pathSegments;
    log.add('${request.method} ${request.url.path}');
    if (failWithStatus != null) {
      return _json({
        'error': {'code': failWithStatus, 'message': 'fake failure'},
      }, status: failWithStatus!);
    }

    final isUpload = segments.isNotEmpty && segments.first == 'upload';
    final rest = isUpload ? segments.sublist(1) : segments;
    // rest: [drive, v3, files, {id}?, copy?] or [drive, v3, about]
    if (rest.length >= 3 && rest[2] == 'about') {
      return _json({
        'user': {'emailAddress': userEmail},
      });
    }
    if (rest.length < 3 || rest[2] != 'files') {
      return _json({'error': 'unsupported ${request.url}'}, status: 400);
    }
    final id = rest.length > 3 ? rest[3] : null;
    final params = request.url.queryParameters;

    switch (request.method) {
      case 'GET':
        if (id == null) return _json(_list(params));
        final file = files[id];
        if (file == null) return _notFound();
        if (params['alt'] == 'media') {
          return http.StreamedResponse(
            Stream.value(file.content),
            200,
            contentLength: file.content.length,
            headers: {'content-type': file.mimeType},
          );
        }
        return _json(file.toJson());
      case 'POST':
        if (id != null && rest.length > 4 && rest[4] == 'copy') {
          final source = files[id];
          if (source == null) return _notFound();
          final meta = _metadata(request, body);
          final copy = FakeDriveFile(
            id: 'f${_nextId++}',
            name: meta['name'] as String? ?? source.name,
            parents: (meta['parents'] as List?)?.cast<String>() ??
                List.of(source.parents),
            mimeType: source.mimeType,
            modifiedTime: _tick(),
            description: meta['description'] as String? ?? source.description,
            content: List.of(source.content),
          );
          files[copy.id] = copy;
          return _json(copy.toJson());
        }
        final upload = _parseUpload(request, body);
        final meta = upload.$1;
        final file = FakeDriveFile(
          id: 'f${_nextId++}',
          name: meta['name'] as String? ?? 'untitled',
          parents: (meta['parents'] as List?)?.cast<String>() ?? ['root'],
          mimeType: meta['mimeType'] as String? ??
              upload.$3 ??
              'application/octet-stream',
          modifiedTime: _tick(),
          description: meta['description'] as String?,
          content: upload.$2,
        );
        files[file.id] = file;
        return _json(file.toJson());
      case 'PATCH':
        final file = id == null ? null : files[id];
        if (file == null) return _notFound();
        final upload = _parseUpload(request, body);
        final meta = upload.$1;
        if (meta['name'] != null) file.name = meta['name'] as String;
        if (meta.containsKey('description')) {
          file.description = meta['description'] as String?;
        }
        if (upload.$2 != null) file.content = upload.$2!;
        file.modifiedTime = _tick();
        return _json(file.toJson());
      case 'DELETE':
        if (id == null || !files.containsKey(id)) return _notFound();
        _deleteTree(id);
        return http.StreamedResponse(const Stream.empty(), 204);
    }
    return _json({'error': 'unsupported method'}, status: 400);
  }

  void _deleteTree(String id) {
    for (final child in childrenOf(id)) {
      _deleteTree(child.id);
    }
    files.remove(id);
  }

  Map<String, dynamic> _list(Map<String, String> params) {
    final clauses = (params['q'] ?? '')
        .split(' and ')
        .map((c) => c.trim())
        .where((c) => c.isNotEmpty)
        .toList();
    bool matches(FakeDriveFile f) {
      for (final c in clauses) {
        final name = RegExp(r"^name\s*=\s*'(.*)'$").firstMatch(c);
        final contains = RegExp(r"^name contains '(.*)'$").firstMatch(c);
        final mime = RegExp(r"^mimeType\s*=\s*'(.*)'$").firstMatch(c);
        final parentIn = RegExp(r"^parents in '(.*)'$").firstMatch(c);
        final inParents = RegExp(r"^'(.*)' in parents$").firstMatch(c);
        if (name != null) {
          if (f.name != name.group(1)) return false;
        } else if (contains != null) {
          if (!f.name.contains(contains.group(1)!)) return false;
        } else if (mime != null) {
          if (f.mimeType != mime.group(1)) return false;
        } else if (parentIn != null) {
          if (!f.parents.contains(parentIn.group(1))) return false;
        } else if (inParents != null) {
          if (!f.parents.contains(inParents.group(1))) return false;
        } else if (c == 'trashed=false' || c == 'trashed = false') {
          // Nothing is ever trashed here.
        } else {
          throw UnsupportedError('FakeDrive cannot read q clause: $c');
        }
      }
      return true;
    }

    final found = files.values.where(matches).toList();
    final orderBy = params['orderBy'];
    if (orderBy != null) {
      final desc = orderBy.endsWith(' desc');
      final key = orderBy.split(' ').first;
      int compare(FakeDriveFile a, FakeDriveFile b) => key == 'name'
          ? a.name.compareTo(b.name)
          : a.modifiedTime.compareTo(b.modifiedTime);
      found.sort((a, b) => desc ? compare(b, a) : compare(a, b));
    }
    return {
      'kind': 'drive#fileList',
      'files': [for (final f in found) f.toJson()],
    };
  }

  Map<String, dynamic> _metadata(http.BaseRequest request, List<int> body) {
    if (body.isEmpty) return {};
    return jsonDecode(utf8.decode(body)) as Map<String, dynamic>;
  }

  /// (metadata, media bytes or null, media content type or null)
  (Map<String, dynamic>, List<int>?, String?) _parseUpload(
    http.BaseRequest request,
    List<int> body,
  ) {
    final type = request.url.queryParameters['uploadType'];
    if (type == null) return (_metadata(request, body), null, null);
    if (type == 'media') {
      return ({}, body, request.headers['content-type']);
    }
    if (type != 'multipart') {
      throw UnsupportedError('FakeDrive cannot take uploadType=$type');
    }
    // See _discoveryapis_commons' MultipartMediaUploader: a JSON part, then
    // the media part base64-encoded.
    final text = utf8.decode(body);
    final boundary = RegExp(r'boundary="?([^";]+)"?')
        .firstMatch(request.headers['content-type']!)!
        .group(1)!;
    final parts = text
        .split('--$boundary')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty && p != '--')
        .toList();
    Map<String, dynamic> meta = {};
    List<int>? media;
    String? mediaType;
    for (final part in parts) {
      final split = part.indexOf('\r\n\r\n');
      final headers = part.substring(0, split);
      final content = part.substring(split + 4).trim();
      if (headers.contains('base64')) {
        media = base64Decode(content);
        mediaType = RegExp(r'Content-Type: ([^\r\n]+)')
            .firstMatch(headers)
            ?.group(1);
      } else {
        meta = jsonDecode(content) as Map<String, dynamic>;
      }
    }
    return (meta, media, mediaType);
  }

  http.StreamedResponse _json(Object data, {int status = 200}) {
    final bytes = utf8.encode(jsonEncode(data));
    return http.StreamedResponse(
      Stream.value(bytes),
      status,
      contentLength: bytes.length,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }

  http.StreamedResponse _notFound() => _json({
        'error': {'code': 404, 'message': 'File not found'},
      }, status: 404);
}

class _FakeAuthClient extends http.BaseClient
    implements auth_io.AutoRefreshingAuthClient {
  _FakeAuthClient(this._drive);
  final FakeDrive _drive;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _drive.send(request);

  @override
  auth_io.AccessCredentials get credentials => auth_io.AccessCredentials(
        auth_io.AccessToken('Bearer', 'fake', DateTime.utc(2100)),
        'refresh',
        const [],
      );

  @override
  Stream<auth_io.AccessCredentials> get credentialUpdates => const Stream.empty();
}
