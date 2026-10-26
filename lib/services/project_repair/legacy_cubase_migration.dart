import 'dart:io';

import 'package:path/path.dart' as p;

import 'project_dependency_inspector.dart';
import 'verified_project_backup.dart';

/// An operator-assisted bridge from classic .ALL/.ARR songs to .CPR.
///
/// DPM deliberately does NOT parse or serialize the proprietary legacy
/// formats. Steinberg's original Cubase SE/SL/SX 3 import is required.
/// Cubase's documented audio/MIDI preservation is NOT full mix fidelity.
class LegacyCubaseMigration {
  static const steinbergGuide =
      'https://helpcenter.steinberg.de/hc/en-us/articles/'
      '115000075750-Converting-Cubase-VST-songs-ALL-ARR-into-CPR-format';

  static const importApplication = 'Cubase SE 3, SL 3 or SX 3';
  static const recommendedApplication = 'Cubase SE 3';

  static const documentedLossRisks = <String>[
    'VST plug-in and instrument state is not retained by the official import.',
    'Original mixer parameters and mixing settings are not retained.',
    'Legacy file parsing by DPM is not implemented; source semantic equivalence cannot be measured.',
    'Media dependency gathering must be completed by the user inside Cubase.',
    'Official conversion requires compatible legacy software, OS and licence.',
  ];

  static bool accepts(String sourcePath) {
    final ext = p.extension(sourcePath).toLowerCase();
    return ext == '.all' || ext == '.arr';
  }

  /// Back up the untouched source before the user imports it in Cubase 3.
  /// A valid filename alone does not establish correct legacy file contents.
  static Future<LegacyCubasePreparation> prepare(File source) async {
    if (!accepts(source.path)) {
      throw const FormatException('Select a classic Cubase .ALL or .ARR song');
    }
    if (!await source.exists() || await source.length() == 0) {
      throw const FileSystemException('Legacy Cubase song is missing or empty');
    }
    final backup = await VerifiedProjectBackup.create(source);
    return LegacyCubasePreparation(
      legacyPath: source.absolute.path,
      legacySha256: backup.sha256Digest,
      backupPath: backup.backupPath,
      legacySize: backup.length,
    );
  }

  /// Validate only the resulting CPR and source invariant; never modify it.
  ///
  /// A successful report means only that DPM recognizes the CPR's structure
  /// and read-only metadata; it does NOT prove equivalent effects, mix or MIDI.
  static Future<LegacyCubaseValidation> validate(
    LegacyCubasePreparation preparation,
    File convertedCpr,
  ) async {
    final source = File(preparation.legacyPath);
    if (p.normalize(source.absolute.path) ==
        p.normalize(convertedCpr.absolute.path)) {
      throw const FormatException('Converted CPR must be a separate file');
    }
    if (p.extension(convertedCpr.path).toLowerCase() != '.cpr') {
      throw const FormatException('Select a .CPR file exported by Cubase');
    }
    if (!await File(preparation.backupPath).exists()) {
      throw const FileSystemException('Required immutable backup is missing');
    }

    // A second verified snapshot proves that the source has not changed.
    // Copies are retained intentionally; no cleanup runs on backup folders.
    final unchanged = await VerifiedProjectBackup.create(source);
    if (unchanged.sha256Digest != preparation.legacySha256 ||
        unchanged.length != preparation.legacySize) {
      throw const FileSystemException('Legacy source changed after preparation');
    }

    final converted = await ProjectDependencyInspector.inspect(convertedCpr);
    if (converted.formatId != 'cubase') {
      throw const FormatException('Converted project is not a valid CPR');
    }
    return LegacyCubaseValidation(
      source: preparation,
      converted: converted,
    );
  }
}

class LegacyCubasePreparation {
  const LegacyCubasePreparation({
    required this.legacyPath,
    required this.legacySha256,
    required this.backupPath,
    required this.legacySize,
  });

  final String legacyPath;
  final String legacySha256;
  final String backupPath;
  final int legacySize;
}

class LegacyCubaseValidation {
  const LegacyCubaseValidation({
    required this.source,
    required this.converted,
  });

  final LegacyCubasePreparation source;
  final ProjectDependencyReport converted;

  Map<String, Object?> toJson() => {
    'source_path': source.legacyPath,
    'source_sha256': source.legacySha256,
    'source_backup': source.backupPath,
    'converted_project': converted.toJson(),
    'source_unchanged': true,
    'conversion_performed_by_dpm': false,
    'lossless_conversion_verified': false,
    'limitations': LegacyCubaseMigration.documentedLossRisks,
    'official_guide': LegacyCubaseMigration.steinbergGuide,
  };
}
