import 'package:material_ui/material_ui.dart';

import '../../generated/l10n/app_localizations.dart';

/// The record label that makes the app, as it is written everywhere: the
/// Windows executable's details, the Store and Flatpak listings, the
/// copyright lines. A name, so never translated.
const kLabelName = 'BandPass Records';

/// "by BandPass Records": a quiet signature under the app's name, on the
/// screens a user actually sees (welcome, What's New, the changelog), not
/// only in About.
class LabelCredit extends StatelessWidget {
  const LabelCredit({super.key, this.textAlign = TextAlign.center});

  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      AppLocalizations.of(context)!.byLabel(kLabelName),
      textAlign: textAlign,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
        letterSpacing: 0.4,
      ),
    );
  }
}
