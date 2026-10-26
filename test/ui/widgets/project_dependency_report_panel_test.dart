import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daw_project_manager/services/project_repair/project_dependency_inspector.dart';
import 'package:daw_project_manager/ui/widgets/project_dependency_report_panel.dart';

void main() {
  testWidgets('displays unknown dependency status without claiming success',
      (tester) async {
    const report = ProjectDependencyReport(
      path: 'demo.cpr',
      formatId: 'cubase',
      pluginNames: ['Mystic'],
      trackCount: 2,
      limitations: ['Preset state: not verified'],
    );
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ProjectDependencyReportPanel(report: report),
        ),
      ),
    ));
    expect(find.text('Mystic'), findsOneWidget);
    expect(find.text('Installation and loadability: not tested'), findsOneWidget);
    expect(find.text('Preset state: not verified'), findsOneWidget);
  });
}
