import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../daw_parsers/cubase_project_parser.dart';
import 'cubase_structural_probe.dart';

/// An immutable, lossless view of the outer RIFF/NUND container.
///
/// ARCH payloads remain opaque. Rebuilding the outer framing proves only that
/// these bytes can be preserved; it does not validate object references or
/// authorize renaming tracks, replacing plug-ins, or resizing ARCH payloads.
class CubaseLosslessContainer {
  CubaseLosslessContainer._(this._source, this.manifest);

  final Uint8List _source;
  final CubaseContainerManifest manifest;

  factory CubaseLosslessContainer.parse(Uint8List bytes) {
    final manifest = CubaseContainerManifest.inspect(bytes);
    return CubaseLosslessContainer._(Uint8List.fromList(bytes), manifest);
  }

  String get sourceSha256 => sha256.convert(_source).toString();
  String? get savedDawVersion => CubaseProjectParser.appVersion(_source);

  /// Returns a copy, so callers cannot alter the preserved source snapshot.
  Uint8List chunkPayload(int index) {
    final chunk = manifest.chunks[index];
    return Uint8List.fromList(
      _source.sublist(chunk.offset + 8, chunk.offset + 8 + chunk.length),
    );
  }

  /// Reconstructs every container/chunk length and retains raw tags/payloads.
  ///
  /// No mutable object serializer is exposed. Unknown chunk names and embedded
  /// binary state, including trailing bytes inside chunks, remain unchanged.
  Uint8List serializeUnchanged() {
    final result = Uint8List(manifest.totalBytes);
    final view = ByteData.sublistView(result);
    result.setRange(0, 4, _source, 0);
    view.setUint32(4, result.length - 12, Endian.big);
    result.setRange(8, 12, _source, 8);
    var destination = 12;
    for (final chunk in manifest.chunks) {
      result.setRange(destination, destination + 4, _source, chunk.offset);
      view.setUint32(destination + 4, chunk.length, Endian.big);
      result.setRange(
        destination + 8,
        destination + 8 + chunk.length,
        _source,
        chunk.offset + 8,
      );
      destination += 8 + chunk.length;
    }
    CubaseContainerManifest.inspect(result);
    return result;
  }

  Map<String, Object?> verificationReport() {
    final rebuilt = serializeUnchanged();
    final rebuiltHash = sha256.convert(rebuilt).toString();
    return {
      'schema_version': 1,
      'operation': 'cpr-container-roundtrip',
      'saved_daw_version': savedDawVersion,
      'source_sha256': sourceSha256,
      'reconstructed_sha256': rebuiltHash,
      'byte_identical': sourceSha256 == rebuiltHash,
      'container': manifest.toJson(),
      'chunks': [
        for (var i = 0; i < manifest.chunks.length; i++)
          {
            'index': i,
            ...manifest.chunks[i].toJson(),
            'payload_sha256': sha256.convert(chunkPayload(i)).toString(),
            'interpretation': 'opaque-preserved-bytes',
          },
      ],
      'validation': {
        'outer_container': 'verified',
        'unchanged_byte_preservation': sourceSha256 == rebuiltHash
            ? 'verified'
            : 'failed',
        'object_graph_completeness': 'unverified',
        'reference_rebasing': 'unsupported',
        'plugin_state_translation': 'unsupported',
        'native_daw_reopen': 'not-run',
        'audio_render_equivalence': 'not-run',
      },
      'mutations_enabled': false,
    };
  }
}
