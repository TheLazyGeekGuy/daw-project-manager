import 'project_format_registry.dart';

/// A documented manual import path, not a native legacy Cubase converter.
class LegacyCubaseConversion {
  static const sourceUrl =
      'https://helpcenter.steinberg.de/hc/en-us/articles/115000075750-Converting-Cubase-VST-songs-ALL-ARR-into-CPR-format';

  static Map<String, Object?>? guideFor(String path) {
    final format = ProjectFormatRegistry.byExtension(path);
    if (format == null ||
        !const {'cubase-all', 'cubase-arr'}.contains(format.id)) {
      return null;
    }
    return {
      'source_format': format.id,
      'target_format': 'cubase',
      'detection_evidence': 'extension-only',
      'execution': 'manual-external-application',
      'supported_importers': ['Cubase SE 3', 'Cubase SL 3', 'Cubase SX 3'],
      'preferred_importer': 'Cubase SE 3',
      'source_url': sourceUrl,
      'steps': [
        'Keep a verified copy of the original song and all media.',
        'Open a compatible, already licensed Cubase SE 3, SL 3 or SX 3 installation.',
        'Choose File > Import > Cubase Song, then select the ALL or ARR file.',
        'Use Save Project to New Folder to gather media and save a new CPR.',
        'Inspect the new CPR in DPM and reopen it in the target Cubase version.',
        'Compare audio/MIDI parts and rebuild missing instruments, effects and mixer settings.',
      ],
      'documented_preservation': [
        'audio tracks and parts',
        'MIDI tracks and parts',
      ],
      'documented_losses': ['VST instruments', 'VST effects', 'mixer settings'],
      'requirements': [
        'A compatible legacy license and operating system are required.',
        'A current Cubase license alone does not prove legacy entitlement.',
        'The eLicenser service closed on May 20, 2025; new activations are unavailable.',
      ],
      'lossless': false,
      'automatic_conversion_supported': false,
      'alternative_routes': [
        {
          'name': 'atari2cubase',
          'url': 'https://atari2cubase.robert-068.workers.dev/',
          'evidence_url':
              'https://forums.steinberg.net/t/free-tool-open-your-atari-st-cubase-songs-arr-all-in-cubase-nuendo-14/1043292',
          'target_formats': ['dawproject', 'midi'],
          'execution': 'manual-external-browser-tool',
          'evidence': 'author-reported-not-validated-by-dpm',
          'intended_source': 'Atari ST Cubase; PC support remains experimental',
          'requires_legacy_cubase': false,
          'produces_cpr_directly': false,
          'cpr_step':
              'Import the DAWproject into a compatible current Cubase, then save as CPR.',
          'integration_license': 'not-established',
        },
      ],
    };
  }
}
