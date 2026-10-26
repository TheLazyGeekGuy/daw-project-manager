import 'dart:io';

import 'package:crypto/crypto.dart';

import 'package:path/path.dart' as p;

import 'project_dependency_inspector.dart';
import 'verified_project_backup.dart';

/// Two independently selected, operator-assisted legacy Cubase migration paths.
///
/// 1. Steinberg Cubase SE/SL/SX 3 import -> CPR (official, lossy).
/// 2. Atari2Cubase in the user's browser -> DAWproject -> Cubase 14+ -> CPR.
///
/// The second path is primarily supported for Atari versions. Windows
/// Cubase VST generations remain experimental in the third-party tool.
/// These manual routes remain separate from DPM's partial, MIT-attributed
/// native ALL-to-MIDI recovery. ARR parsing is not implemented in DPM.
/// Neither route certifies MIDI/audio, plug-in or mix fidelity.
class LegacyCubaseMigration {
  static const steinbergGuide =
      'https://helpcenter.steinberg.de/hc/en-us/articles/'
      '115000075750-Converting-Cubase-VST-songs-ALL-ARR-into-CPR-format';

  static const atariConverter = 'https://atari2cubase.robert-068.workers.dev/';
  static const modernImportApplication = 'Cubase/Nuendo 14 or later';
  static const modernImportInstructions =
      'In Cubase choose File > Import > DAWproject, open the resulting '
      'session, then save as a new CPR.';

  static const importApplication = 'Cubase SE 3, SL 3 or SX 3';
  static const recommendedApplication = 'Cubase SE 3';

  static const documentedLossRisks = <String>[
    'VST plug-in and instrument state is not retained by the official import.',
    'Original mixer parameters and mixing settings are not retained.',
    'Native ALL parsing is partial; source semantic equivalence is not certified and ARR parsing is unsupported.',
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

  /// Verify the operator-generated CPR and all immutable source invariants.
  ///
  /// This checks readable project metadata, never musical equivalence.
  static Future<LegacyCubaseValidation> validate(
    LegacyCubasePreparation preparation,
    File convertedCpr,
  ) => _validateOutput(
    preparation,
    convertedCpr,
    expectedExtension: '.cpr',
    expectedFormat: 'cubase',
  );

  /// Verify an intermediary DAWproject from an external converter.
  ///
  /// Checks the bounded ZIP/XML structure and the untouched original. Full XSD
  /// validation, musical equivalence and native reopening remain unverified.
  static Future<LegacyCubaseValidation> validateDawProject(
    LegacyCubasePreparation preparation,
    File convertedDawproject,
  ) => _validateOutput(
    preparation,
    convertedDawproject,
    expectedExtension: '.dawproject',
    expectedFormat: 'dawproject',
  );

  static Future<LegacyCubaseValidation> _validateOutput(
    LegacyCubasePreparation preparation,
    File converted, {
    required String expectedExtension,
    required String expectedFormat,
  }) async {
    final source = File(preparation.legacyPath);
    final backup = File(preparation.backupPath);
    final outputPath = p.normalize(converted.absolute.path);
    if (outputPath == p.normalize(source.absolute.path) ||
        outputPath == p.normalize(backup.absolute.path)) {
      throw const FormatException('The conversion output must be a new file');
    }
    if (p.extension(converted.path).toLowerCase() != expectedExtension) {
      throw FormatException(
        'Expected a $expectedExtension file from the external converter',
      );
    }
    await VerifiedProjectBackup.ensureNoSymlinkComponents(source.absolute.path);
    await VerifiedProjectBackup.ensureNoSymlinkComponents(backup.absolute.path);
    await VerifiedProjectBackup.ensureNoSymlinkComponents(
      converted.absolute.path,
    );
    if (!await backup.exists() ||
        await backup.length() != preparation.legacySize ||
        await _sha256(backup) != preparation.legacySha256) {
      throw const FileSystemException(
        'Legacy backup is missing or does not match the prepared source',
      );
    }
    if (!await source.exists() ||
        await source.length() != preparation.legacySize ||
        await _sha256(source) != preparation.legacySha256) {
      throw const FileSystemException(
        'Legacy source changed after preparation',
      );
    }
    if (!await converted.exists() || await converted.length() == 0) {
      throw const FormatException(
        'External conversion output is missing or empty',
      );
    }

    final report = await ProjectDependencyInspector.inspect(converted);
    if (report.formatId != expectedFormat) {
      throw FormatException(
        'Expected $expectedFormat project, got ${report.formatId}',
      );
    }
    // The external process may have run outside DPM. Do not treat this
    // read-only validation as evidence that the original stays immutable.
    if (await _sha256(source) != preparation.legacySha256 ||
        await _sha256(backup) != preparation.legacySha256) {
      throw const FileSystemException(
        'Legacy source or its verified backup changed during inspection',
      );
    }
    return LegacyCubaseValidation(
      source: preparation,
      converted: report,
      migrationRoute: expectedFormat == 'dawproject'
          ? 'atari2cubase-assisted-dawproject'
          : 'cubase3-or-modern-cubase-assisted-cpr',
    );
  }

  static Future<String> _sha256(File file) async =>
      (await sha256.bind(file.openRead()).first).toString();
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
    required this.migrationRoute,
  });

  final LegacyCubasePreparation source;
  final ProjectDependencyReport converted;
  final String migrationRoute;

  Map<String, Object?> toJson() => {
    'source_path': source.legacyPath,
    'source_sha256': source.legacySha256,
    'source_backup': source.backupPath,
    'converted_project': converted.toJson(),
    'migration_route': migrationRoute,
    'format_signature_only':
        converted.formatId == 'dawproject' &&
        converted.dawProjectSummary == null,
    if (converted.dawProjectSummary != null)
      'validation_scope': 'bounded_container_and_xml_structure',
    'native_daw_reopen_verified': false,
    'source_unchanged': true,
    'conversion_performed_by_dpm': false,
    'lossless_conversion_verified': false,
    'limitations': LegacyCubaseMigration.documentedLossRisks,
    'official_guide': LegacyCubaseMigration.steinbergGuide,
    'alternate_atari_converter': LegacyCubaseMigration.atariConverter,
    'modern_import': LegacyCubaseMigration.modernImportInstructions,
  };
}
