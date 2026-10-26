import 'package:flutter_test/flutter_test.dart';
import 'package:daw_project_manager/services/release_workflow_engine.dart';

Map<String, dynamic> workspace() => {
  'schema_version': 2,
  'release_id': 'release',
  'collection_type': 'album',
  'artist_ids': <String>[],
  'tracks': [
    {'id': 'track', 'title': 'Track'},
  ],
  'rights_filings': <Map>[],
  'distribution': <Map>[],
  'communications': <Map>[],
  'assets': <Map>[],
  'campaigns': <Map>[],
  'tasks': <Map>[],
};

void main() {
  const engine = ReleaseWorkflowEngine();
  final now = DateTime(2026, 10, 26, 12);

  test('dependent tasks are blocked until their prerequisite is complete', () {
    final data = workspace()
      ..['tasks'] = [
        {
          'id': 'master',
          'title': 'Approve master',
          'status': 'todo',
          'depends_on': <String>[],
        },
        {
          'id': 'submit',
          'title': 'Submit delivery',
          'status': 'todo',
          'depends_on': ['master'],
        },
      ];
    var report = engine.evaluate(data, now: now);
    expect(report.blockedTaskIds, ['submit']);
    expect(report.nextAction, 'Complete task: Approve master');
    (data['tasks'] as List).first['status'] = 'done';
    report = engine.evaluate(data, now: now);
    expect(report.blockedTaskIds, isEmpty);
    expect(report.nextAction, 'Complete task: Submit delivery');
  });

  test(
    'completed tasks with unfinished dependencies do not imply readiness',
    () {
      final data = workspace()
        ..['tasks'] = [
          {'id': 'a', 'title': 'A', 'status': 'todo', 'depends_on': <String>[]},
          {
            'id': 'b',
            'title': 'B',
            'status': 'done',
            'depends_on': ['a'],
          },
        ];
      final report = engine.evaluate(data, now: now);
      expect(report.readyForManualReview, false);
      expect(
        report.issues.any(
          (issue) => issue.code == 'completed_task_dependencies',
        ),
        true,
      );
    },
  );

  test('date-only deadlines remain current through the whole day', () {
    final data = workspace()
      ..['tasks'] = [
        {
          'id': 'today',
          'title': 'Today',
          'status': 'todo',
          'due_at': '2026-10-26',
        },
        {
          'id': 'past',
          'title': 'Past',
          'status': 'todo',
          'due_at': '2026-10-25',
        },
      ];
    final report = engine.evaluate(data, now: now);
    expect(report.overdueTaskIds, ['past']);
    expect(report.nextAction, 'Complete task: Past');
  });

  test('campaign posts cover associated tracks and calendar sorts by time', () {
    final data = workspace()
      ..['campaigns'] = [
        {
          'id': 'launch',
          'title': 'Launch',
          'track_ids': ['track'],
        },
      ]
      ..['communications'] = [
        {
          'id': 'late',
          'title': 'Later',
          'platform': 'Video',
          'status': 'scheduled',
          'campaign_id': 'launch',
          'scheduled_at': '2026-11-02T15:00:00Z',
        },
        {
          'id': 'early',
          'title': 'Earlier',
          'platform': 'Social',
          'status': 'planned',
          'track_id': 'track',
          'scheduled_at': '2026-11-01T15:00:00Z',
        },
      ];
    final report = engine.evaluate(data, now: now);
    expect(report.tracksWithoutPromotion, isEmpty);
    expect(report.promotionCalendar.map((entry) => entry['id']), [
      'early',
      'late',
    ]);
    (data['communications'] as List).clear();
    expect(engine.evaluate(data).tracksWithoutPromotion, ['track']);
  });

  test('changed audio is blocking and never a verified master', () {
    final data = workspace()
      ..['assets'] = [
        {
          'id': 'master',
          'role': 'master',
          'path': '/music/master.wav',
          'track_id': 'track',
          'validation': 'changed',
        },
      ];
    final report = engine.evaluate(data, now: now);
    expect(report.assetsRequiringVerification, ['master']);
    expect(
      report.issues.any(
        (issue) =>
            issue.code == 'asset_integrity' && issue.severity == 'blocking',
      ),
      true,
    );
    expect(report.readyForManualReview, false);
  });

  test(
    'local completion remains manual review, never external publication proof',
    () {
      final data = workspace()
        ..['assets'] = [
          {
            'id': 'master',
            'role': 'master',
            'path': '/music/master.wav',
            'track_id': 'track',
            'validation': 'verified',
            'sha256': 'a' * 64,
            'bytes': 40,
            'verified_at': '2026-10-26T10:00:00Z',
          },
        ]
        ..['distribution'] = [
          {
            'id': 'direct',
            'distributor': 'Direct distribution',
            'status': 'draft',
          },
        ]
        ..['communications'] = [
          {
            'id': 'post',
            'title': 'Plan',
            'platform': 'Social',
            'status': 'idea',
            'track_id': 'track',
          },
        ];
      final report = engine.evaluate(data, now: now);
      expect(report.readyForManualReview, true);
      expect(report.toJson()['external_statuses_verified'], false);
      expect(report.readiness, 'ready_for_manual_review');
      expect(
        report.issues.any((issue) => issue.code == 'rights_required'),
        false,
      );
    },
  );

  test(
    'malformed records produce blocking metadata issues without crashing',
    () {
      final data = workspace()
        ..['tasks'] = [
          42,
          {'id': [], 'depends_on': 'not-a-list'},
        ];
      final report = engine.evaluate(data, now: now);
      expect(report.readyForManualReview, false);
      expect(report.nextAction, 'Review invalid release metadata');
    },
  );
}
