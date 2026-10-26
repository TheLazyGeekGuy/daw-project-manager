/// Offline workflow validation for the native DPM release workspace.
///
/// It checks declared metadata, not external distributor / rights acceptance.
class ReleaseWorkflowValidator {
  const ReleaseWorkflowValidator();

  static const rightsStatuses = {
    'draft', 'ready', 'submitted', 'acknowledged', 'accepted',
    'rejected', 'needs_review', 'unknown',
  };
  static const deliveryStatuses = {
    'draft', 'prepared', 'submitted', 'in_review', 'accepted',
    'delivered', 'live', 'rejected', 'taken_down', 'unknown',
  };
  static const promotionStatuses = {
    'idea', 'planned', 'creating', 'ready', 'scheduled',
    'published', 'cancelled', 'unknown',
  };

  List<String> validate(Map<String, dynamic> workspace) {
    final problems = <String>[];
    if (workspace['schema_version'] != 1) {
      problems.add('Unsupported release workspace schema');
    }
    final type = workspace['collection_type'];
    if (!const {'album', 'ep', 'single', 'compilation', 'playlist'}.contains(type)) {
      problems.add('Unsupported collection type');
    }
    final tracks = workspace['tracks'];
    if (tracks is! List) {
      problems.add('Tracks must be a list');
    } else {
      final ids = <String>{};
      for (final track in tracks) {
        if (track is! Map || track['id'] is! String) {
          problems.add('Track requires an ID');
          continue;
        }
        if (!ids.add(track['id'] as String)) {
          problems.add('Duplicate track ID: ${track['id']}');
        }
        final isrc = track['isrc'];
        if (isrc != null && (isrc is! String ||
            !RegExp(r'^[A-Z]{2}[A-Z0-9]{3}[0-9]{7}$').hasMatch(isrc))) {
          problems.add('Invalid ISRC for ${track['id']}');
        }
      }
    }
    final rights = workspace['rights_filings'];
    if (rights is! List) {
      problems.add('Rights filings must be a list');
    } else {
      for (final filing in rights) {
        if (filing is! Map || filing['organization'] is! String ||
            filing['status'] is! String ||
            !rightsStatuses.contains(filing['status']) ||
            (filing['organization'] as String).trim().isEmpty) {
          problems.add('Invalid rights filing');
        }
      }
    }
    final distribution = workspace['distribution'];
    if (distribution is! List) {
      problems.add('Distribution entries must be a list');
    } else {
      for (final delivery in distribution) {
        if (delivery is! Map || delivery['distributor'] is! String ||
            delivery['status'] is! String ||
            !deliveryStatuses.contains(delivery['status']) ||
            (delivery['distributor'] as String).trim().isEmpty) {
          problems.add('Invalid distribution entry');
        }
      }
    }
    final communication = workspace['communications'];
    if (communication is! List) {
      problems.add('Communications must be a list');
    } else {
      for (final post in communication) {
        if (post is! Map || post['platform'] is! String ||
            post['status'] is! String ||
            !promotionStatuses.contains(post['status']) ||
            (post['platform'] as String).trim().isEmpty) {
          problems.add('Invalid communication entry');
        }
      }
    }
    return problems;
  }

  /// The next actionable stage is advisory and does not claim completion.
  String nextSuggestedStep(Map<String, dynamic> workspace) {
    final errors = validate(workspace);
    if (errors.isNotEmpty) return 'Review invalid release metadata';
    final tracks = workspace['tracks'] as List;
    if (tracks.isEmpty) return 'Add tracks to the release';
    if (tracks.any((t) => t is Map && (t['isrc'] == null || t['isrc'] == ''))) {
      return 'Review recording identifiers and ISRCs';
    }
    final distribution = workspace['distribution'] as List;
    if (distribution.isEmpty) return 'Prepare distributor delivery';
    final rights = workspace['rights_filings'] as List;
    if (rights.isEmpty) return 'Review rights registration requirements';
    final communication = workspace['communications'] as List;
    if (communication.isEmpty) return 'Plan release communication';
    return 'Review external statuses and outstanding tasks';
  }
}
