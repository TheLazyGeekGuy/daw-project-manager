import 'package:material_ui/material_ui.dart';

import '../generated/l10n/app_localizations.dart';

/// Every localization delegate the app needs: its own strings, then
/// Material's, Cupertino's and the widgets' from material_ui.
///
/// Use this, never `AppLocalizations.localizationsDelegates`: gen-l10n still
/// writes that list with flutter_localizations' delegates, which serve the
/// SDK's bundled Material library. A material_ui widget under them finds no
/// MaterialLocalizations in any locale but English (which has built-in
/// defaults), so a German dropdown threw where an English one worked.
final List<LocalizationsDelegate<Object?>> appLocalizationsDelegates = [
  AppLocalizations.delegate,
  ...GlobalMaterialLocalizations.delegates,
];
