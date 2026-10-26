import 'release_workflow_validator.dart';

class ReleaseWorkflowIssue {
  const ReleaseWorkflowIssue({
    required this.code,
    required this.message,
    required this.severity,
    this.recordId,
  });
  final String code, message, severity;
  final String? recordId;
  Map<String, Object?> toJson() => {
    'code': code,
    'message': message,
    'severity': severity,
    'record_id': recordId,
  };
}

/// Local readiness only. No organization, distributor or social service is
/// contacted, and manually entered external states remain unverified.
class ReleaseWorkflowEvaluation {
  const ReleaseWorkflowEvaluation({
    required this.issues,
    required this.nextAction,
    required this.blockedTaskIds,
    required this.overdueTaskIds,
    required this.tracksWithoutPromotion,
    required this.assetsRequiringVerification,
    required this.promotionCalendar,
  });
  final List<ReleaseWorkflowIssue> issues;
  final String nextAction;
  final List<String> blockedTaskIds,
      overdueTaskIds,
      tracksWithoutPromotion,
      assetsRequiringVerification;
  final List<Map<String, Object?>> promotionCalendar;
  bool get readyForManualReview =>
      issues.every((issue) => issue.severity == 'info');
  String get readiness =>
      readyForManualReview ? 'ready_for_manual_review' : 'needs_attention';
  Map<String, Object?> toJson() => {
    'readiness': readiness,
    'next_action': nextAction,
    'issues': [for (final issue in issues) issue.toJson()],
    'blocked_task_ids': blockedTaskIds,
    'overdue_task_ids': overdueTaskIds,
    'tracks_without_promotion': tracksWithoutPromotion,
    'assets_requiring_verification': assetsRequiringVerification,
    'promotion_calendar': promotionCalendar,
    'external_statuses_verified': false,
  };
}

class ReleaseWorkflowEngine {
  const ReleaseWorkflowEngine();

  ReleaseWorkflowEvaluation evaluate(
    Map<String, dynamic> workspace, {
    Map<String, dynamic>? catalog,
    DateTime? now,
  }) {
    final today = now ?? DateTime.now();
    final validation = const ReleaseWorkflowValidator().validate(
      workspace,
      catalog: catalog,
    );
    final issues = <ReleaseWorkflowIssue>[
      for (final error in validation)
        ReleaseWorkflowIssue(
          code: 'invalid_metadata',
          message: error,
          severity: 'blocking',
        ),
    ];
    void issue(
      String code,
      String message, {
      String severity = 'warning',
      String? id,
    }) {
      issues.add(
        ReleaseWorkflowIssue(
          code: code,
          message: message,
          severity: severity,
          recordId: id,
        ),
      );
    }

    final tracks = _records(workspace['tracks']);
    final tasks = _records(workspace['tasks']);
    final assets = _records(workspace['assets']);
    final posts = _records(workspace['communications']);
    final campaigns = _records(workspace['campaigns']);
    final taskMap = {
      for (final task in tasks)
        if (task['id'] is String) task['id'] as String: task,
    };
    final blocked = <String>[];
    final overdue = <String>[];
    final available = <Map>[];
    for (final task in tasks) {
      final id = _string(task['id']);
      final unmet = _strings(task['depends_on'])
          .where((dependency) => taskMap[dependency]?['status'] != 'done')
          .toList();
      if (task['status'] == 'done') {
        if (unmet.isNotEmpty) {
          blocked.add(id);
          issue(
            'completed_task_dependencies',
            'Completed task still has unfinished dependencies: ${task['title']}',
            severity: 'blocking',
            id: id,
          );
        }
        continue;
      }
      if (unmet.isNotEmpty || task['status'] == 'blocked') {
        blocked.add(id);
        issue('blocked_task', 'Task is blocked: ${task['title']}', id: id);
      } else if (const {'todo', 'doing'}.contains(task['status'])) {
        available.add(task);
      }
      if (_overdue(task['due_at'], today)) {
        overdue.add(id);
        issue('overdue_task', 'Task is overdue: ${task['title']}', id: id);
      }
    }
    available.sort((a, b) {
      final aDue = ReleaseWorkflowValidator.parseDate(a['due_at']);
      final bDue = ReleaseWorkflowValidator.parseDate(b['due_at']);
      if (aDue == null) return bDue == null ? 0 : 1;
      if (bDue == null) return -1;
      return aDue.compareTo(bDue);
    });

    final requiringVerification = <String>[];
    for (final asset in assets) {
      if (asset['validation'] != 'verified') {
        final id = _string(asset['id']);
        requiringVerification.add(id);
        final compromised = const {
          'changed',
          'missing',
        }.contains(asset['validation']);
        issue(
          'asset_integrity',
          'Asset needs verification: ${asset['path']}',
          severity: compromised ? 'blocking' : 'warning',
          id: id,
        );
      }
    }
    if (tracks.isEmpty) {
      issue('no_tracks', 'Add tracks to the release', severity: 'blocking');
    }
    final isPlaylist = workspace['collection_type'] == 'playlist';
    final missingMasters = <String>[];
    if (!isPlaylist) {
      for (final track in tracks) {
        if (!assets.any(
          (asset) =>
              asset['track_id'] == track['id'] &&
              asset['role'] == 'master' &&
              asset['validation'] == 'verified',
        )) {
          final id = _string(track['id']);
          missingMasters.add(id);
          issue(
            'no_verified_master',
            'No verified master is linked to ${track['title'] ?? id}',
            id: id,
          );
        }
      }
    }
    if (catalog != null && workspace['schema_version'] == 1) {
      final known = {
        for (final artist in _records(catalog['artists'])) artist['id'],
      };
      for (final id in _strings(workspace['artist_ids'])) {
        if (!known.contains(id)) {
          issue(
            'unresolved_legacy_artist',
            'Imported artist ID needs a catalog record: $id',
            id: id,
          );
        }
      }
    }

    final campaignMap = {
      for (final campaign in campaigns)
        if (campaign['id'] is String) campaign['id'] as String: campaign,
    };
    final promoted = <String>{};
    final calendar = <Map<String, Object?>>[];
    for (final post in posts) {
      if (post['status'] == 'cancelled') continue;
      if (post['track_id'] is String) promoted.add(post['track_id'] as String);
      final campaign = campaignMap[post['campaign_id']];
      if (campaign != null) promoted.addAll(_strings(campaign['track_ids']));
      final dateValue = post['status'] == 'published'
          ? post['published_at']
          : post['scheduled_at'];
      final date = ReleaseWorkflowValidator.parseDate(dateValue);
      if (date != null) {
        calendar.add({
          'id': post['id'],
          'title': post['title'],
          'platform': post['platform'],
          'status': post['status'],
          'at': date.toIso8601String(),
          'track_id': post['track_id'],
          'campaign_id': post['campaign_id'],
        });
        if (post['status'] != 'published' && _overdue(dateValue, today)) {
          issue(
            'overdue_communication',
            'Planned communication needs review: ${post['title'] ?? post['platform']}',
            id: _string(post['id']),
          );
        }
      }
    }
    calendar.sort(
      (a, b) => DateTime.parse(
        a['at'] as String,
      ).compareTo(DateTime.parse(b['at'] as String)),
    );
    final uncovered = <String>[
      for (final track in tracks)
        if (track['id'] is String && !promoted.contains(track['id']))
          track['id'] as String,
    ];
    if (uncovered.isNotEmpty) {
      issue(
        'promotion_coverage',
        '${uncovered.length} track(s) have no associated promotion plan',
      );
    }
    if (!isPlaylist && _records(workspace['distribution']).isEmpty) {
      issue(
        'distribution_plan',
        'Choose a distribution route or record your direct-release plan',
      );
    }
    for (final filing in _records(workspace['rights_filings'])) {
      if (const {'rejected', 'needs_review'}.contains(filing['status'])) {
        issue(
          'rights_followup',
          'Review rights filing for ${filing['organization']}',
          id: _string(filing['id']),
        );
      }
    }
    for (final delivery in _records(workspace['distribution'])) {
      if (const {'rejected', 'taken_down'}.contains(delivery['status'])) {
        issue(
          'distribution_followup',
          'Review delivery through ${delivery['distributor']}',
          id: _string(delivery['id']),
        );
      }
      for (final platform in _records(delivery['platforms'])) {
        if (const {'rejected', 'taken_down'}.contains(platform['status'])) {
          issue(
            'platform_followup',
            'Review delivery to ${platform['platform']}',
            id: _string(platform['id']),
          );
        }
      }
    }
    issue(
      'external_statuses_unverified',
      'Rights, distribution and publication statuses are manually recorded and require external verification.',
      severity: 'info',
    );

    final String nextAction;
    if (validation.isNotEmpty) {
      nextAction = 'Review invalid release metadata';
    } else if (tracks.isEmpty) {
      nextAction = 'Add tracks to the release';
    } else if (issues.any((entry) => entry.severity == 'blocking')) {
      nextAction = issues
          .firstWhere((entry) => entry.severity == 'blocking')
          .message;
    } else if (available.isNotEmpty) {
      nextAction = 'Complete task: ${available.first['title']}';
    } else if (requiringVerification.isNotEmpty) {
      nextAction = 'Verify linked release files';
    } else if (missingMasters.isNotEmpty) {
      nextAction = 'Link and verify the master audio for each track';
    } else if (blocked.isNotEmpty) {
      nextAction = 'Resolve blocked task dependencies';
    } else if (uncovered.isNotEmpty) {
      nextAction = 'Plan communication for tracks without promotion';
    } else {
      final warnings = issues.where((entry) => entry.severity == 'warning');
      nextAction = warnings.isEmpty
          ? 'Review release metadata and external confirmations'
          : warnings.first.message;
    }
    return ReleaseWorkflowEvaluation(
      issues: List.unmodifiable(issues),
      nextAction: nextAction,
      blockedTaskIds: List.unmodifiable(blocked),
      overdueTaskIds: List.unmodifiable(overdue),
      tracksWithoutPromotion: List.unmodifiable(uncovered),
      assetsRequiringVerification: List.unmodifiable(requiringVerification),
      promotionCalendar: List.unmodifiable(calendar),
    );
  }

  static List<Map> _records(Object? value) =>
      value is List ? value.whereType<Map>().take(20000).toList() : const [];
  static List<String> _strings(Object? value) =>
      value is List ? value.whereType<String>().take(20000).toList() : const [];
  static String _string(Object? value) =>
      value is String ? value : '(unidentified)';
  static bool _overdue(Object? raw, DateTime now) {
    final date = ReleaseWorkflowValidator.parseDate(raw);
    if (date == null) return false;
    // A date-only deadline remains due throughout that local calendar day.
    if (raw is String && raw.length == 10) {
      return !now.isBefore(DateTime(date.year, date.month, date.day + 1));
    }
    return date.isBefore(now);
  }
}
