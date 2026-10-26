import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'release_workspace_migration.dart';

class ReleaseRevisionConflict implements Exception {
  const ReleaseRevisionConflict(this.expected, this.actual);

  final int expected;
  final int actual;

  @override
  String toString() =>
      'Release metadata changed: expected revision $expected, found $actual. Reload before saving.';
}

/// Profile-scoped release metadata independent of the legacy Hive adapter.
///
/// Schema migrations happen in memory. An explicit save preserves the previous
/// bytes, publishes a verified new revision, and leaves a recoverable journal
/// if publication is interrupted. No provider communication occurs here.
class ReleaseWorkspaceStore {
  const ReleaseWorkspaceStore(this.directory, {this.profileId});

  final Directory directory;
  final String? profileId;

  ReleaseJsonDocumentStore _store(String releaseId) {
    ReleaseJsonDocumentStore.safeId(releaseId);
    if (profileId != null) ReleaseJsonDocumentStore.safeId(profileId!);
    return ReleaseJsonDocumentStore(
      directory,
      releaseId,
      empty: () =>
          ReleaseWorkspaceMigration.empty(releaseId, profileId: profileId),
      normalize: (value) => ReleaseWorkspaceMigration.migrate(
        value,
        releaseId,
        profileId: profileId,
      ),
    );
  }

  Future<Map<String, dynamic>> read(String releaseId) =>
      _store(releaseId).read();

  /// Lists this profile's workspaces for reference checks before deletion.
  ///
  /// Hidden transaction files, snapshots and the catalog directory are excluded.
  /// This is a bounded inventory, not a transaction across every release.
  Future<List<String>> listReleaseIds() async {
    final root = await _store('index')._directory(create: false);
    if (root == null) return [];
    final ids = <String>[];
    var visited = 0;
    await for (final entity in root.list(followLinks: false)) {
      if (++visited > 100000) {
        throw const FileSystemException(
          'Profile metadata inventory exceeds its entry limit',
        );
      }
      final name = p.basename(entity.path);
      if (name.startsWith('.') || !name.endsWith('.json')) continue;
      final id = name.substring(0, name.length - 5);
      if (!RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(id)) continue;
      if (entity is Directory) continue;
      await ReleaseJsonDocumentStore.regularFile(File(entity.path));
      ids.add(id);
      if (ids.length > 10000) {
        throw const FileSystemException(
          'Profile metadata inventory exceeds its release limit',
        );
      }
    }
    return ids..sort();
  }

  Future<void> save(
    String releaseId,
    Map<String, dynamic> value, {
    int? expectedRevision,
    bool preserveTimestamps = false,
  }) => _store(releaseId).save(
    value,
    expectedRevision: expectedRevision,
    preserveTimestamps: preserveTimestamps,
  );

  /// Explicitly import one selected legacy file into the confirmed profile.
  ///
  /// The source is retained unchanged. Without an expected revision the
  /// destination must be new, so import cannot silently replace existing work.
  Future<void> importLegacy(
    File source, {
    required String releaseId,
    required String destinationProfileId,
    int? expectedRevision,
  }) async {
    ReleaseJsonDocumentStore.safeId(destinationProfileId);
    ReleaseJsonDocumentStore.safeId(releaseId);
    final expectedProfile =
        profileId ?? p.basename(p.normalize(directory.path));
    if (destinationProfileId != expectedProfile) {
      throw const FormatException('Legacy import destination profile mismatch');
    }
    await ReleaseJsonDocumentStore.regularFile(source);
    final bytes = await ReleaseJsonDocumentStore.readBounded(source);
    final value = ReleaseJsonDocumentStore.decode(bytes);
    final originalProfile = value.remove('profile_id');
    final migrated = ReleaseWorkspaceMigration.migrate(
      value,
      releaseId,
      profileId: destinationProfileId,
    );
    final destinationRoot = await directory.exists()
        ? await directory.resolveSymbolicLinks()
        : p.absolute(directory.path);
    final destination = p.normalize(p.join(destinationRoot, '$releaseId.json'));
    if (p.equals(await source.resolveSymbolicLinks(), destination)) {
      throw const FormatException('Legacy source and destination must differ');
    }
    await _store(releaseId).save(
      {
        ...migrated,
        'legacy_import': {
          'source_path': await source.resolveSymbolicLinks(),
          'source_sha256': sha256.convert(bytes).toString(),
          'source_profile_id': ?originalProfile,
          'destination_profile_id': destinationProfileId,
          'imported_at': DateTime.now().toUtc().toIso8601String(),
        },
      },
      expectedRevision: expectedRevision ?? 0,
      requireNewDocument: expectedRevision == null,
    );
  }
}

typedef ReleaseDocumentNormalizer =
    Map<String, dynamic> Function(Map<String, dynamic> value);

/// Shared single-document transaction implementation for release stores.
///
/// This is not a transaction across the catalog and a release workspace. OS
/// locks and an in-process queue serialize cooperating readers and writers.
class ReleaseJsonDocumentStore {
  const ReleaseJsonDocumentStore(
    this.directory,
    this.documentId, {
    required this.empty,
    required this.normalize,
    this.subdirectory,
  });

  static const maxDocumentBytes = 8 * 1024 * 1024;
  static final Map<String, Future<void>> _queues = {};

  final Directory directory;
  final String documentId;
  final String? subdirectory;
  final Map<String, dynamic> Function() empty;
  final ReleaseDocumentNormalizer normalize;

  static String safeId(String value) {
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(value)) {
      throw const FormatException('Invalid release metadata identifier');
    }
    return value;
  }

  static Future<void> regularFile(
    File file, {
    bool allowMissing = false,
  }) async {
    final type = await FileSystemEntity.type(file.path, followLinks: false);
    if (type == FileSystemEntityType.file ||
        (allowMissing && type == FileSystemEntityType.notFound)) {
      return;
    }
    throw FileSystemException('Expected a regular metadata file', file.path);
  }

  static Future<List<int>> readBounded(File file) async {
    await regularFile(file);
    if (await file.length() > maxDocumentBytes) {
      throw const FormatException('Release document exceeds its size limit');
    }
    final result = <int>[];
    await for (final chunk in file.openRead()) {
      if (result.length + chunk.length > maxDocumentBytes) {
        throw const FormatException('Release document exceeds its size limit');
      }
      result.addAll(chunk);
    }
    return result;
  }

  static Map<String, dynamic> decode(List<int> bytes) {
    final value = jsonDecode(utf8.decode(bytes));
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Release document must be a JSON object');
    }
    return value;
  }

  Future<Directory?> _directory({required bool create}) async {
    safeId(documentId);
    if (subdirectory != null) safeId(subdirectory!);
    var root = directory.absolute;
    for (final child in [null, if (subdirectory != null) subdirectory]) {
      if (child != null) root = Directory(p.join(root.path, child));
      var type = await FileSystemEntity.type(root.path, followLinks: false);
      if (type == FileSystemEntityType.notFound) {
        if (!create) return null;
        await root.create(recursive: true);
        type = await FileSystemEntity.type(root.path, followLinks: false);
      }
      if (type != FileSystemEntityType.directory) {
        throw FileSystemException(
          'Metadata directory must not be a link',
          root.path,
        );
      }
      root = Directory(await root.resolveSymbolicLinks());
    }
    return root;
  }

  File _document(Directory root) => File(p.join(root.path, '$documentId.json'));
  File _journal(Directory root) =>
      File(p.join(root.path, '.$documentId.pending.json'));

  Future<T> _locked<T>(Directory root, Future<T> Function() operation) async {
    final key = p.join(root.path, documentId);
    final previous = _queues[key];
    final completion = Completer<void>();
    _queues[key] = completion.future;
    if (previous != null) await previous;
    RandomAccessFile? lock;
    var acquired = false;
    try {
      final lockFile = File(p.join(root.path, '.$documentId.lock'));
      await regularFile(lockFile, allowMissing: true);
      lock = await lockFile.open(mode: FileMode.append);
      await lock.lock(FileLock.blockingExclusive);
      acquired = true;
      await _recover(root);
      return await operation();
    } finally {
      try {
        if (acquired) await lock!.unlock();
      } finally {
        try {
          await lock?.close();
        } finally {
          completion.complete();
          if (identical(_queues[key], completion.future)) _queues.remove(key);
        }
      }
    }
  }

  Future<Map<String, dynamic>> _read(Directory root) async {
    final file = _document(root);
    await regularFile(file, allowMissing: true);
    return await file.exists()
        ? normalize(decode(await readBounded(file)))
        : empty();
  }

  Future<Map<String, dynamic>> read() async {
    final root = await _directory(create: false);
    if (root == null) return empty();
    return _locked(root, () => _read(root));
  }

  Future<void> save(
    Map<String, dynamic> value, {
    int? expectedRevision,
    bool requireNewDocument = false,
    bool preserveTimestamps = false,
  }) async {
    normalize(value);
    // Freeze the submitted snapshot before waiting for another editor or IO.
    final submittedBytes = utf8.encode(jsonEncode(value));
    if (submittedBytes.length > maxDocumentBytes) {
      throw const FormatException('Release document exceeds its size limit');
    }
    final submitted = decode(submittedBytes);
    normalize(
      submitted,
    ); // Reject invalid envelopes before touching the directory.
    if (expectedRevision != null && expectedRevision < 0) {
      throw const FormatException('Expected revision cannot be negative');
    }
    final root = (await _directory(create: true))!;
    await _locked(root, () async {
      final current = await _read(root);
      final actual = current['revision'] as int;
      if (expectedRevision != null && expectedRevision != actual) {
        throw ReleaseRevisionConflict(expectedRevision, actual);
      }
      if (requireNewDocument && await _document(root).exists()) {
        throw StateError(
          'Legacy import destination already exists; reload it and provide its revision explicitly.',
        );
      }
      // Unknown top-level fields survive callers which edit a smaller view.
      // List entries are full snapshots; record editors preserve nested fields.
      final next = normalize({
        ...current,
        ...submitted,
        'revision': actual + 1,
        if (!preserveTimestamps)
          'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
      final encoded = utf8.encode(
        const JsonEncoder.withIndent('  ').convert(next),
      );
      if (encoded.length > maxDocumentBytes) {
        throw const FormatException('Release document exceeds its size limit');
      }
      final destination = _document(root);
      final token = const Uuid().v4();
      final staging = File(p.join(root.path, '.$documentId-$token.tmp'));
      final journalStaging = File(
        p.join(root.path, '.$documentId-$token.journal.tmp'),
      );
      final journal = _journal(root);
      var prepared = false;
      try {
        await _writeExclusive(staging, encoded);
        final stagedBytes = await readBounded(staging);
        final newHash = sha256.convert(encoded).toString();
        if (sha256.convert(stagedBytes).toString() != newHash) {
          throw const FileSystemException('Staged release verification failed');
        }
        normalize(decode(stagedBytes));
        String? previousName;
        String? previousHash;
        if (await destination.exists()) {
          final previousBytes = await readBounded(destination);
          previousHash = sha256.convert(previousBytes).toString();
          final snapshot = File(
            p.join(root.path, '.$documentId-$token.previous.json'),
          );
          await _writeExclusive(snapshot, previousBytes);
          if (sha256.convert(await readBounded(snapshot)).toString() !=
              previousHash) {
            throw const FileSystemException(
              'Previous snapshot verification failed',
            );
          }
          previousName = p.basename(snapshot.path);
        }
        final transaction = {
          'schema_version': 1,
          'document': p.basename(destination.path),
          'staging': p.basename(staging.path),
          'sha256': newHash,
          'previous': previousName,
          'previous_sha256': previousHash,
        };
        await _writeExclusive(
          journalStaging,
          utf8.encode(jsonEncode(transaction)),
        );
        await regularFile(journal, allowMissing: true);
        if (await journal.exists()) {
          throw const FileSystemException('Unresolved release transaction');
        }
        await journalStaging.rename(journal.path);
        prepared = true;
        await staging.rename(destination.path);
        if (sha256.convert(await readBounded(destination)).toString() !=
            newHash) {
          throw const FileSystemException(
            'Published release verification failed',
          );
        }
        await journal.delete();
      } finally {
        // A prepared transaction retains the staging evidence for recovery.
        if (!prepared && await staging.exists()) await staging.delete();
        if (await journalStaging.exists()) await journalStaging.delete();
      }
    });
  }

  static Future<void> _writeExclusive(File file, List<int> bytes) async {
    await file.create(exclusive: true);
    await file.writeAsBytes(bytes, flush: true);
  }

  Future<void> _recover(Directory root) async {
    final journal = _journal(root);
    await regularFile(journal, allowMissing: true);
    if (!await journal.exists()) return;
    final transaction = decode(await readBounded(journal));
    final expectedHash = transaction['sha256'];
    final oldHash = transaction['previous_sha256'];
    if (transaction['schema_version'] != 1 ||
        transaction['document'] != '$documentId.json' ||
        expectedHash is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(expectedHash) ||
        (oldHash != null &&
            (oldHash is! String ||
                !RegExp(r'^[a-f0-9]{64}$').hasMatch(oldHash)))) {
      throw const FormatException('Invalid release recovery journal');
    }
    File artifact(dynamic name, String suffix) {
      if (name is! String ||
          !RegExp(
            '^\\.${RegExp.escape(documentId)}-[a-zA-Z0-9-]+${RegExp.escape(suffix)}\$',
          ).hasMatch(name)) {
        throw const FormatException('Unsafe release recovery artifact path');
      }
      return File(p.join(root.path, name));
    }

    final staging = artifact(transaction['staging'], '.tmp');
    final backup = transaction['previous'] == null
        ? null
        : artifact(transaction['previous'], '.previous.json');
    if ((backup == null) != (oldHash == null)) {
      throw const FormatException('Incomplete previous revision reference');
    }
    final destination = _document(root);
    for (final file in [staging, destination, ?backup]) {
      await regularFile(file, allowMissing: true);
    }
    Future<String?> fingerprint(File file) async => await file.exists()
        ? sha256.convert(await readBounded(file)).toString()
        : null;
    final destinationHash = await fingerprint(destination);
    if (destinationHash == expectedHash) {
      normalize(decode(await readBounded(destination)));
      if (await staging.exists()) await staging.delete();
      await journal.delete();
      return;
    }
    if (destinationHash != null && destinationHash != oldHash) {
      throw const FileSystemException(
        'Recovery found a conflicting metadata revision',
      );
    }
    final stagedHash = await fingerprint(staging);
    if (stagedHash == expectedHash) {
      normalize(decode(await readBounded(staging)));
      await staging.rename(destination.path);
      if (await fingerprint(destination) != expectedHash) {
        throw const FileSystemException(
          'Recovery publication verification failed',
        );
      }
      await journal.delete();
      return;
    }
    if (stagedHash != null) {
      throw const FileSystemException('Recovery staging hash mismatch');
    }
    if (oldHash != null && destinationHash == oldHash) {
      await journal.delete(); // The previous committed revision is intact.
      return;
    }
    if (destinationHash == null &&
        backup != null &&
        await fingerprint(backup) == oldHash) {
      final bytes = await readBounded(backup);
      normalize(decode(bytes));
      final restored = File(
        p.join(root.path, '.$documentId-${const Uuid().v4()}.tmp'),
      );
      await _writeExclusive(restored, bytes);
      await restored.rename(destination.path);
      if (await fingerprint(destination) != oldHash) {
        throw const FileSystemException(
          'Recovery rollback verification failed',
        );
      }
      await journal.delete();
      return;
    }
    throw const FileSystemException(
      'Release transaction needs manual recovery',
    );
  }
}
