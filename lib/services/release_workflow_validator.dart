/// Offline validation of local music metadata. Declared rights and delivery
/// states are user records, not confirmations from external organizations.
class ReleaseWorkflowValidator {
  const ReleaseWorkflowValidator();

  static const rightsStatuses = {
    'draft',
    'ready',
    'submitted',
    'acknowledged',
    'accepted',
    'rejected',
    'needs_review',
    'unknown',
  };
  static const deliveryStatuses = {
    'draft',
    'prepared',
    'submitted',
    'in_review',
    'accepted',
    'delivered',
    'live',
    'rejected',
    'taken_down',
    'unknown',
  };
  static const promotionStatuses = {
    'idea',
    'planned',
    'creating',
    'ready',
    'scheduled',
    'published',
    'cancelled',
    'unknown',
  };
  static const taskStatuses = {'todo', 'doing', 'done', 'blocked'};
  static const assetRoles = {
    'master',
    'mix',
    'preview',
    'stem',
    'artwork',
    'lyrics',
    'midi',
    'document',
    'video',
    'image',
    'teaser',
    'press_kit',
    'audio_snippet',
    'text',
    'evidence',
  };
  static const assetValidationStates = {
    'verified',
    'missing',
    'changed',
    'unverified',
  };

  List<String> validate(
    Map<String, dynamic> workspace, {
    Map<String, dynamic>? catalog,
  }) {
    final errors = <String>[];
    final modern = workspace['schema_version'] == 2;
    if (!const {1, 2}.contains(workspace['schema_version'])) {
      errors.add('Unsupported release workspace schema');
    }
    if (modern && !_id(workspace['release_id'])) {
      errors.add('Release requires a stable ID');
    }
    if (!const {
      'album',
      'ep',
      'single',
      'compilation',
      'playlist',
    }.contains(workspace['collection_type'])) {
      errors.add('Unsupported collection type');
    }
    final tracks = _records(
      workspace['tracks'],
      'Tracks',
      errors,
      required: true,
    );
    final filings = _records(
      workspace['rights_filings'],
      'Rights filings',
      errors,
      required: true,
    );
    final deliveries = _records(
      workspace['distribution'],
      'Distribution entries',
      errors,
      required: true,
    );
    final posts = _records(
      workspace['communications'],
      'Communications',
      errors,
      required: true,
    );
    final assets = _records(workspace['assets'], 'Assets', errors);
    final campaigns = _records(workspace['campaigns'], 'Campaigns', errors);
    final tasks = _records(workspace['tasks'], 'Tasks', errors);
    final trackIds = _ids(tracks, 'track', errors);
    final assetIds = _ids(assets, 'asset', errors);
    final campaignIds = _ids(campaigns, 'campaign', errors);
    final taskIds = _ids(tasks, 'task', errors);
    _ids(filings, 'rights filing', errors, required: modern);
    _ids(deliveries, 'distribution entry', errors, required: modern);
    _ids(posts, 'communication entry', errors, required: modern);

    Set<String>? artistIds;
    Set<String>? workIds;
    if (catalog != null) {
      errors.addAll(validateCatalog(catalog));
      artistIds = _existingIds(catalog['artists']);
      workIds = _existingIds(catalog['works']);
    }
    final selectedArtists = _strings(
      workspace['artist_ids'],
      'Artist IDs',
      errors,
    );
    // Schema 1 may hold unresolved imported IDs. They remain visible to the
    // workflow engine; converting to schema 2 requires a real catalog record.
    if (modern && artistIds != null) {
      _references(selectedArtists, artistIds, 'artist', errors);
    }
    for (final track in tracks) {
      _validateTrack(
        track,
        errors,
        artistIds: artistIds,
        workIds: workIds,
        requireTitle: modern,
      );
    }

    for (final filing in filings) {
      if (!_nonEmpty(filing['organization']) ||
          !rightsStatuses.contains(filing['status'])) {
        errors.add('Invalid rights filing');
      }
      _optionalReference(filing['work_id'], workIds, 'work', errors);
      _references(
        _strings(filing['evidence_asset_ids'], 'Evidence asset IDs', errors),
        assetIds,
        'evidence asset',
        errors,
      );
      _optionalDate(filing['submitted_at'], 'Rights submission', errors);
      _history(filing['history'], rightsStatuses, 'Rights filing', errors);
    }
    for (final delivery in deliveries) {
      if (!_nonEmpty(delivery['distributor']) ||
          !deliveryStatuses.contains(delivery['status'])) {
        errors.add('Invalid distribution entry');
      }
      if (!_absent(delivery['upc']) && !validBarcode(delivery['upc'])) {
        errors.add('Invalid UPC/EAN check digit');
      }
      _history(delivery['history'], deliveryStatuses, 'Distribution', errors);
      final platforms = _records(delivery['platforms'], 'Platforms', errors);
      _ids(platforms, 'platform', errors, required: modern);
      for (final platform in platforms) {
        if (!_nonEmpty(platform['platform']) ||
            !deliveryStatuses.contains(platform['status'])) {
          errors.add('Invalid platform delivery');
        }
        _optionalUrl(platform['url'], 'Platform', errors);
        _optionalDate(platform['published_at'], 'Platform publication', errors);
        if (modern &&
            platform['status'] == 'live' &&
            _absent(platform['published_at'])) {
          errors.add('Live platform requires a publication timestamp');
        }
      }
    }
    for (final post in posts) {
      if (!_nonEmpty(post['platform']) ||
          !promotionStatuses.contains(post['status'])) {
        errors.add('Invalid communication entry');
      }
      if (modern && !_nonEmpty(post['title'])) {
        errors.add('Communication requires a title');
      }
      _optionalReference(post['track_id'], trackIds, 'promotion track', errors);
      _optionalReference(post['campaign_id'], campaignIds, 'campaign', errors);
      _references(
        _strings(post['asset_ids'], 'Promotion asset IDs', errors),
        assetIds,
        'promotion asset',
        errors,
      );
      _optionalDate(post['scheduled_at'], 'Scheduled publication', errors);
      _optionalDate(post['published_at'], 'Publication', errors);
      _optionalUrl(post['url'], 'Publication', errors);
      if (modern &&
          post['status'] == 'published' &&
          _absent(post['published_at'])) {
        errors.add('Published communication requires a publication timestamp');
      }
      if (modern &&
          post['status'] == 'scheduled' &&
          _absent(post['scheduled_at'])) {
        errors.add('Scheduled communication requires a scheduled timestamp');
      }
    }
    final assetParents = <String, List<String>>{};
    for (final asset in assets) {
      if (!assetRoles.contains(asset['role']) || !_nonEmpty(asset['path'])) {
        errors.add('Invalid asset role or path');
      }
      if (!assetValidationStates.contains(
        asset['validation'] ?? 'unverified',
      )) {
        errors.add('Invalid asset validation state');
      }
      _optionalReference(asset['track_id'], trackIds, 'asset track', errors);
      _optionalReference(
        asset['parent_asset_id'],
        assetIds,
        'parent asset',
        errors,
      );
      if (_id(asset['id'])) {
        assetParents[asset['id'] as String] = [
          if (_nonEmpty(asset['parent_asset_id']))
            asset['parent_asset_id'] as String,
        ];
      }
      if (!_absent(asset['sha256']) && !_digest(asset['sha256'])) {
        errors.add('Invalid asset SHA-256');
      }
      if (asset['bytes'] != null &&
          (asset['bytes'] is! int || (asset['bytes'] as int) < 0)) {
        errors.add('Invalid asset byte length');
      }
      _optionalDate(asset['verified_at'], 'Asset verification', errors);
      if (asset['validation'] == 'verified' &&
          (!_digest(asset['sha256']) ||
              asset['bytes'] is! int ||
              _absent(asset['verified_at']))) {
        errors.add(
          'Verified asset requires a digest, byte length and verification timestamp',
        );
      }
    }
    if (_hasCycle(assetParents)) errors.add('Asset lineage contains a cycle');
    for (final campaign in campaigns) {
      if (!_nonEmpty(campaign['title'])) {
        errors.add('Campaign requires a title');
      }
      _references(
        _strings(campaign['track_ids'], 'Campaign track IDs', errors),
        trackIds,
        'campaign track',
        errors,
      );
      _optionalDate(campaign['start_at'], 'Campaign start', errors);
      _optionalDate(campaign['end_at'], 'Campaign end', errors);
      final start = parseDate(campaign['start_at']);
      final end = parseDate(campaign['end_at']);
      if (start != null && end != null && end.isBefore(start)) {
        errors.add('Campaign ends before it starts');
      }
    }
    final graph = <String, List<String>>{};
    for (final task in tasks) {
      if (!_nonEmpty(task['title']) || !taskStatuses.contains(task['status'])) {
        errors.add('Invalid workflow task');
      }
      final dependencies = _strings(
        task['depends_on'],
        'Task dependencies',
        errors,
      );
      _references(dependencies, taskIds, 'dependency task', errors);
      if (_id(task['id'])) graph[task['id'] as String] = dependencies;
      _optionalDate(task['due_at'], 'Task due date', errors);
    }
    if (_hasCycle(graph)) errors.add('Task dependencies contain a cycle');
    return errors.toSet().toList(growable: false);
  }

  List<String> validateCatalog(Map<String, dynamic> catalog) {
    final errors = <String>[];
    if (catalog['schema_version'] != 1) {
      errors.add('Unsupported music catalog schema');
    }
    final artists = _records(catalog['artists'], 'Artists', errors);
    final holders = _records(catalog['holders'], 'Rights holders', errors);
    final works = _records(catalog['works'], 'Musical works', errors);
    final tracks = _records(catalog['tracks'], 'Catalog tracks', errors);
    final playlists = _records(catalog['playlists'], 'Playlists', errors);
    final artistIds = _ids(artists, 'artist', errors);
    final holderIds = _ids(holders, 'rights holder', errors);
    final workIds = _ids(works, 'work', errors);
    final trackIds = _ids(tracks, 'catalog track', errors);
    _ids(playlists, 'playlist', errors);
    for (final artist in artists) {
      if (!_nonEmpty(artist['name'])) errors.add('Artist requires a name');
      _strings(artist['aliases'], 'Artist aliases', errors);
      _strings(artist['roles'], 'Artist roles', errors);
    }
    for (final holder in holders) {
      if (!_nonEmpty(holder['name'])) {
        errors.add('Rights holder requires a name');
      }
      // Identifier assignment/registration is not validated by local syntax.
      for (final field in ['ipi', 'isni']) {
        if (!_absent(holder[field]) && holder[field] is! String) {
          errors.add('Invalid rights holder $field');
        }
      }
    }
    for (final work in works) {
      if (!_nonEmpty(work['title'])) {
        errors.add('Musical work requires a title');
      }
      if (!_absent(work['iswc']) && work['iswc'] is! String) {
        errors.add('Invalid ISWC value');
      }
      final shares = _records(work['shares'], 'Work shares', errors);
      var total = 0.0;
      for (final share in shares) {
        _optionalReference(
          share['holder_id'],
          holderIds,
          'rights holder',
          errors,
          required: true,
        );
        if (!_nonEmpty(share['role'])) errors.add('Share requires a role');
        final amount = share['percentage'];
        if (amount is! num || !amount.isFinite || amount < 0 || amount > 100) {
          errors.add('Invalid rights share percentage');
        } else {
          total += amount.toDouble();
        }
      }
      if (shares.isNotEmpty && (total - 100).abs() > 0.001) {
        errors.add('Shares must total 100% for ${work['id']}');
      }
    }
    for (final track in tracks) {
      _validateTrack(
        track,
        errors,
        artistIds: artistIds,
        workIds: workIds,
        requireTitle: true,
      );
    }
    for (final playlist in playlists) {
      if (!_nonEmpty(playlist['title'])) {
        errors.add('Playlist requires a title');
      }
      _references(
        _strings(playlist['track_ids'], 'Playlist track IDs', errors),
        trackIds,
        'playlist track',
        errors,
      );
    }
    return errors.toSet().toList(growable: false);
  }

  /// Advisory only. A rights registration is not assumed to be mandatory for
  /// every release, and an ISRC/UPC syntax check does not prove assignment.
  String nextSuggestedStep(Map<String, dynamic> workspace) {
    if (validate(workspace).isNotEmpty) {
      return 'Review invalid release metadata';
    }
    final tracks = _records(workspace['tracks'], 'Tracks', []);
    if (tracks.isEmpty) return 'Add tracks to the release';
    if (tracks.any((track) => _absent(track['isrc']))) {
      return 'Review recording identifiers and ISRCs';
    }
    if (_records(workspace['distribution'], 'Distribution', []).isEmpty) {
      return 'Prepare distributor delivery';
    }
    if (_records(workspace['rights_filings'], 'Rights filings', []).isEmpty) {
      return 'Review rights registration requirements';
    }
    if (_records(workspace['communications'], 'Communications', []).isEmpty) {
      return 'Plan release communication';
    }
    return 'Review external statuses and outstanding tasks';
  }

  static bool validBarcode(Object? value) {
    if (value is! String ||
        !RegExp(r'^(?:[0-9]{12}|[0-9]{13})$').hasMatch(value)) {
      return false;
    }
    var sum = 0;
    var multiplier = 3;
    for (var i = value.length - 2; i >= 0; i--) {
      sum += int.parse(value[i]) * multiplier;
      multiplier = 4 - multiplier;
    }
    return (10 - sum % 10) % 10 == int.parse(value[value.length - 1]);
  }

  static bool validIsrc(Object? value) =>
      value is String &&
      RegExp(r'^[A-Z]{2}[A-Z0-9]{3}[0-9]{7}$').hasMatch(value);

  static DateTime? parseDate(Object? value) {
    if (value is! String) return null;
    final match = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2})(?:[T ](\d{2}):(\d{2})(?::(\d{2})(?:\.\d{1,9})?)?(?:Z|[+-]\d{2}:?\d{2})?)?$',
    ).firstMatch(value);
    if (match == null) return null;
    final year = int.parse(match[1]!);
    final month = int.parse(match[2]!);
    final day = int.parse(match[3]!);
    if (month < 1 ||
        month > 12 ||
        day < 1 ||
        day > DateTime.utc(year, month + 1, 0).day) {
      return null;
    }
    if (int.parse(match[4] ?? '0') > 23 ||
        int.parse(match[5] ?? '0') > 59 ||
        int.parse(match[6] ?? '0') > 59) {
      return null;
    }
    return DateTime.tryParse(value);
  }

  static bool validUrl(Object? value) {
    if (value is! String || RegExp(r'[\x00-\x20]').hasMatch(value)) {
      return false;
    }
    final uri = Uri.tryParse(value);
    return uri != null &&
        const {'http', 'https'}.contains(uri.scheme) &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty;
  }

  static void _validateTrack(
    Map track,
    List<String> errors, {
    Set<String>? artistIds,
    Set<String>? workIds,
    bool requireTitle = false,
  }) {
    if (requireTitle && !_nonEmpty(track['title'])) {
      errors.add('Track requires a title');
    }
    if (!_absent(track['isrc']) && !validIsrc(track['isrc'])) {
      errors.add('Invalid ISRC for ${track['id']}');
    }
    _optionalReference(track['work_id'], workIds, 'track work', errors);
    if (!_absent(track['project_id']) && track['project_id'] is! String) {
      errors.add('Invalid project reference');
    }
    final credits = _records(track['credits'], 'Track credits', errors);
    for (final credit in credits) {
      _optionalReference(
        credit['artist_id'],
        artistIds,
        'credited artist',
        errors,
        required: true,
      );
      if (!_nonEmpty(credit['role'])) errors.add('Credit requires a role');
    }
  }

  static List<Map> _records(
    Object? value,
    String label,
    List<String> errors, {
    bool required = false,
  }) {
    if (value == null && !required) return const [];
    if (value is! List) {
      errors.add('$label must be a list');
      return const [];
    }
    if (value.length > 20000) errors.add('$label exceeds record limit');
    final records = <Map>[];
    for (final item in value.take(20000)) {
      if (item is Map && item.keys.every((key) => key is String)) {
        records.add(item);
      } else {
        errors.add('Invalid $label record');
        // Preserve legacy error wording used by consumers.
        if (label == 'Rights filings') errors.add('Invalid rights filing');
        if (label == 'Distribution entries') {
          errors.add('Invalid distribution entry');
        }
        if (label == 'Communications') {
          errors.add('Invalid communication entry');
        }
      }
    }
    return records;
  }

  static Set<String> _ids(
    List<Map> records,
    String label,
    List<String> errors, {
    bool required = true,
  }) {
    final ids = <String>{};
    for (final record in records) {
      final id = record['id'];
      if (id == null && !required) continue;
      if (!_id(id)) {
        errors.add(
          '${label[0].toUpperCase()}${label.substring(1)} requires an ID',
        );
        continue;
      }
      if (!ids.add(id as String)) errors.add('Duplicate $label ID: $id');
    }
    return ids;
  }

  static Set<String> _existingIds(Object? value) => value is List
      ? {
          for (final entry in value)
            if (entry is Map && entry['id'] is String) entry['id'] as String,
        }
      : {};

  static List<String> _strings(
    Object? value,
    String label,
    List<String> errors,
  ) {
    if (value == null) return const [];
    if (value is! List || value.any((entry) => !_nonEmpty(entry))) {
      errors.add('$label must be a list of non-empty strings');
      return const [];
    }
    if (value.length > 20000) errors.add('$label exceeds item limit');
    return value.take(20000).cast<String>().toList(growable: false);
  }

  static void _references(
    Iterable<String> values,
    Set<String> known,
    String label,
    List<String> errors,
  ) {
    for (final value in values) {
      if (!known.contains(value)) errors.add('Unknown $label: $value');
    }
  }

  static void _optionalReference(
    Object? value,
    Set<String>? known,
    String label,
    List<String> errors, {
    bool required = false,
  }) {
    if (_absent(value) && !required) return;
    if (!_id(value)) {
      errors.add('Invalid $label reference');
      return;
    }
    if (known != null && !known.contains(value)) {
      errors.add('Unknown $label: $value');
    }
  }

  static void _optionalDate(Object? value, String label, List<String> errors) {
    if (!_absent(value) && parseDate(value) == null) {
      errors.add('$label has an invalid date');
    }
  }

  static void _optionalUrl(Object? value, String label, List<String> errors) {
    if (!_absent(value) && !validUrl(value)) {
      errors.add('$label requires an HTTP(S) URL');
    }
  }

  static void _history(
    Object? value,
    Set<String> statuses,
    String label,
    List<String> errors,
  ) {
    for (final entry in _records(value, '$label history', errors)) {
      if (!statuses.contains(entry['to']) ||
          (!_absent(entry['from']) && !statuses.contains(entry['from'])) ||
          parseDate(entry['at']) == null) {
        errors.add('Invalid $label status history');
      }
    }
  }

  static bool _nonEmpty(Object? value) =>
      value is String && value.trim().isNotEmpty;
  static bool _absent(Object? value) => value == null || value == '';
  static bool _id(Object? value) =>
      value is String && RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(value);
  static bool _digest(Object? value) =>
      value is String && RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(value);

  static bool _hasCycle(Map<String, List<String>> graph) {
    final counts = <String, int>{};
    final dependants = <String, List<String>>{};
    for (final entry in graph.entries) {
      final dependencies = entry.value.where(graph.containsKey).toSet();
      counts[entry.key] = dependencies.length;
      for (final dependency in dependencies) {
        dependants.putIfAbsent(dependency, () => []).add(entry.key);
      }
    }
    final ready = [
      for (final entry in counts.entries)
        if (entry.value == 0) entry.key,
    ];
    var processed = 0;
    for (var index = 0; index < ready.length; index++) {
      final id = ready[index];
      processed++;
      for (final next in dependants[id] ?? const <String>[]) {
        final remaining = counts[next]! - 1;
        counts[next] = remaining;
        if (remaining == 0) ready.add(next);
      }
    }
    return processed != graph.length;
  }
}
