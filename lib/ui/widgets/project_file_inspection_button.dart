import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import '../../generated/l10n/app_localizations.dart';
import '../../generated/l10n/app_localizations_en.dart';
import '../app_snack_bar.dart';
import 'project_inspection_dialog.dart';

/// Opens any supported project directly, including unindexed legacy songs.
class ProjectFileInspectionButton extends StatelessWidget {
  const ProjectFileInspectionButton({super.key, this.pickFile});
  final Future<File?> Function()? pickFile;
  static Future<File?> _pick() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['all', 'arr', 'cpr', 'npr', 'rpp', 'dawproject'],
    );
    final path = files.firstOrNull?.path;
    return path == null ? null : File(path);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context) ?? AppLocalizationsEn();
    return IconButton(
      tooltip: l.projectRepairOpen,
      icon: const Icon(Icons.fact_check_outlined),
      onPressed: () async {
        try {
          final file = await (pickFile ?? _pick)();
          if (file == null || !context.mounted) return;
          await showDialog<void>(
            context: context,
            builder: (_) => ProjectInspectionDialog(projectFile: file),
          );
        } catch (error) {
          if (context.mounted) {
            ScaffoldMessenger.maybeOf(context)?.showAppSnackBar(
              SnackBar(
                content: Text(l.projectInspectorFailed(error.toString())),
              ),
            );
          }
        }
      },
    );
  }
}
