import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

import 'package:daw_project_manager/models/sample_reference.dart';
import 'package:daw_project_manager/services/daw_parsers/ableton_project_parser.dart';
import 'package:daw_project_manager/services/daw_parsers/flp_project_parser.dart';
import 'package:daw_project_manager/services/daw_parsers/reaper_project_parser.dart';
import 'package:daw_project_manager/services/daw_parsers/studio_one_project_parser.dart';

/// Hex of [text] as UTF-16LE, the way Live 9/10 on Windows writes a
/// `FileRef`'s `Data`.
String _utf16Hex(String text) => [
      for (final unit in text.codeUnits) ...[unit & 0xFF, unit >> 8],
      0,
      0,
    ].map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

void main() {
  group('Ableton', () {
    List<SampleReference> read(String tracks) => AbletonProjectParser(
          XmlDocument.parse(
            '<Ableton><LiveSet><Tracks>$tracks</Tracks></LiveSet></Ableton>',
          ),
        ).readSampleReferences();

    test('Live 11+: Path and RelativePath, with what Live says the file is',
        () {
      final refs = read('''
<AudioTrack><DeviceChain><MainSequencer><Sample><ArrangerAutomation><Events>
  <AudioClip><SampleRef><FileRef>
    <RelativePathType Value="3" />
    <RelativePath Value="Samples/Recorded/Vox 0001.wav" />
    <Path Value="C:/Live/Song Project/Samples/Recorded/Vox 0001.wav" />
    <OriginalFileSize Value="1234" />
  </FileRef></SampleRef></AudioClip>
  <AudioClip><SampleRef><FileRef>
    <RelativePath Value="Samples/Processed/Consolidate/Drums.wav" />
    <Path Value="C:/Live/Song Project/Samples/Processed/Consolidate/Drums.wav" />
  </FileRef></SampleRef></AudioClip>
  <AudioClip><SampleRef><FileRef>
    <RelativePath Value="../../Library/Kicks/Kick 1.wav" />
    <Path Value="D:/Library/Kicks/Kick 1.wav" />
  </FileRef></SampleRef></AudioClip>
</Events></ArrangerAutomation></Sample></MainSequencer></DeviceChain></AudioTrack>''');
      expect(refs, hasLength(3));
      expect(refs[0].fileName, 'Vox 0001.wav');
      expect(refs[0].candidates, [
        'C:/Live/Song Project/Samples/Recorded/Vox 0001.wav',
        'Samples/Recorded/Vox 0001.wav',
      ]);
      expect(refs[0].kind, SampleKind.recorded);
      expect(refs[0].sizeBytes, 1234);
      expect(refs[0].use, SampleUse.audio);
      expect(refs[1].kind, SampleKind.processed);
      expect(refs[2].kind, isNull);
    });

    test('Live 9: path elements (empty = ..), Name, and the UTF-16 Data', () {
      const absolute = r'I:\Projects\Song Project\Samples\Imported\RIM15.wav';
      final refs = read('''
<MidiTrack><DeviceChain><Devices><OriginalSimpler><Player><MultiSampleMap>
<SampleParts><MultiSamplePart><SampleRef><FileRef>
  <HasRelativePath Value="true" />
  <RelativePathType Value="3" />
  <RelativePath>
    <RelativePathElement Dir="Samples" />
    <RelativePathElement Dir="Imported" />
  </RelativePath>
  <Name Value="RIM15.wav" />
  <Data>${_utf16Hex(absolute)}</Data>
  <SearchHint><FileSize Value="44474" /></SearchHint>
</FileRef></SampleRef></MultiSamplePart>
<MultiSamplePart><SampleRef><FileRef>
  <RelativePath>
    <RelativePathElement Dir="" />
    <RelativePathElement Dir="" />
    <RelativePathElement Dir="Samples" />
    <RelativePathElement Dir="Claps" />
  </RelativePath>
  <Name Value="CLAP23.wav" />
  <Data>0011AABB</Data>
</FileRef></SampleRef></MultiSamplePart></SampleParts>
</MultiSampleMap></Player></OriginalSimpler></Devices></DeviceChain></MidiTrack>''');
      expect(refs, hasLength(2));
      expect(refs[0].candidates, [absolute, 'Samples/Imported/RIM15.wav']);
      expect(refs[0].kind, SampleKind.imported);
      expect(refs[0].sizeBytes, 44474);
      expect(refs[0].use, SampleUse.sampler, reason: 'Simpler, not a clip');
      expect(refs[1].candidates, ['../../Samples/Claps/CLAP23.wav'],
          reason: 'a Data blob that is no path (a macOS alias) is skipped');
    });

    test('preset references and analysis files are not samples', () {
      final refs = read('''
<MidiTrack><SampleRef><FileRef>
  <RelativePath Value="Presets/Lead.adg" />
</FileRef></SampleRef></MidiTrack>''');
      expect(refs, isEmpty);
    });

    test("finds paths in a plug-in's saved state", () {
      final state = [
        1, 2, 3,
        ...latin1.encode(r'C:\Kontakt\Pads\Air.wav'),
        0,
      ];
      final refs = read('''
<MidiTrack><PluginDevice><Buffer>${_hex(state)}</Buffer></PluginDevice></MidiTrack>''');
      expect(refs, hasLength(1));
      expect(refs.single.use, SampleUse.plugin);
      expect(refs.single.candidates, [r'C:\Kontakt\Pads\Air.wav']);
    });
  });

  group('FL Studio', () {
    Uint8List flp(List<int> events) {
      final out = BytesBuilder()
        ..add(ascii.encode('FLhd'))
        ..add([6, 0, 0, 0, 0, 0, 2, 0, 96, 0])
        ..add(ascii.encode('FLdt'));
      final len = events.length;
      out.add([len & 255, (len >> 8) & 255, (len >> 16) & 255, len >> 24]);
      out.add(events);
      return out.toBytes();
    }

    List<int> word(int id, int v) => [id, v & 255, v >> 8];
    List<int> byte(int id, int v) => [id, v];
    List<int> data(int id, List<int> payload) {
      // FL's variable-length size: 7 bits a byte, low first.
      final size = <int>[];
      var n = payload.length;
      do {
        final b = n & 0x7F;
        n >>= 7;
        size.add(n > 0 ? b | 0x80 : b);
      } while (n > 0);
      return [id, ...size, ...payload];
    }

    List<int> utf16(String s) => [
          for (final unit in s.codeUnits) ...[unit & 0xFF, unit >> 8],
          0,
          0,
        ];

    test("reads each channel's sample: sampler and audio clip channels", () {
      final refs = FlpProjectParser(flp([
        ...word(64, 0),
        ...byte(21, 0),
        ...data(196, utf16(r'C:\Users\me\Desktop\Song\Kick 2013.wav')),
        ...word(64, 1),
        ...byte(21, 4),
        ...data(196, utf16(r'C:\Users\me\Desktop\Song\Vocal Chop.wav')),
        ...word(64, 2),
        ...byte(21, 0),
        // FL 7: relative to the install's Data folder.
        ...data(196, latin1.encode(r'\Patches\Kicks\kick 15.wav')),
      ])).readSampleReferences();
      expect([for (final r in refs) r.fileName],
          ['Kick 2013.wav', 'Vocal Chop.wav', 'kick 15.wav']);
      expect([for (final r in refs) r.use],
          [SampleUse.sampler, SampleUse.audio, SampleUse.sampler]);
      expect(refs[2].candidates, [r'\Patches\Kicks\kick 15.wav']);
    });

    test('finds paths in plug-in data (Fruity Slicer and the like)', () {
      final refs = FlpProjectParser(flp([
        ...word(64, 0),
        ...byte(21, 2),
        ...data(213, [
          15, 0, 0, 0,
          ...latin1.encode(r'D:\Loops\Break 140.wav'),
          0,
        ]),
      ])).readSampleReferences();
      expect(refs, hasLength(1));
      expect(refs.single.use, SampleUse.plugin);
      expect(refs.single.candidates, [r'D:\Loops\Break 140.wav']);
    });
  });

  group('REAPER', () {
    final rs5kState = base64.encode([
      0, 0, 1,
      ...latin1.encode(r'C:\Samples\Snares\snare 3.wav'),
      0, 0,
    ]);
    final rpp = '''
<REAPER_PROJECT 0.1 "6.80" 1700000000
  RENDER_FILE "C:\\Renders\\mix.wav"
  <TRACK
    NAME Vox
    <ITEM
      <SOURCE WAVE
        FILE "Audio/Vox-001.wav"
      >
    >
    <ITEM
      <SOURCE SECTION
        <SOURCE FLAC
          FILE "D:\\Library\\Loops\\Top 140.flac"
        >
      >
    >
    <ITEM
      <SOURCE MIDI
        FILE "riff.mid"
      >
    >
  >
  <TRACK
    NAME Drums
    <FXCHAIN
      <VST "VSTi: ReaSamplOmatic5000 (Cockos)" reasamplomatic.dll 0 "" 1920167789
        $rs5kState
      >
    >
  >
>
''';

    test('reads audio sources, nested ones too, and never MIDI or renders',
        () {
      final refs = ReaperProjectParser(rpp).readSampleReferences();
      final audio = refs.where((r) => r.use == SampleUse.audio).toList();
      expect([for (final r in audio) r.candidates.single],
          ['Audio/Vox-001.wav', r'D:\Library\Loops\Top 140.flac']);
    });

    test("a take named after its track is a recording", () {
      final refs = ReaperProjectParser(rpp).readSampleReferences();
      expect(refs.first.kind, SampleKind.recorded);
      expect(refs[1].kind, isNull);
    });

    test("reads ReaSamplOmatic5000's sample from its base64 state", () {
      final sampler = ReaperProjectParser(rpp)
          .readSampleReferences()
          .where((r) => r.use == SampleUse.sampler)
          .toList();
      expect(sampler, hasLength(1));
      expect(sampler.single.candidates, [r'C:\Samples\Snares\snare 3.wav']);
    });
  });

  group('Studio One', () {
    Uint8List song(Map<String, String> files) {
      final archive = Archive();
      files.forEach((name, text) {
        final bytes = utf8.encode(text);
        archive.addFile(ArchiveFile(name, bytes.length, bytes));
      });
      return Uint8List.fromList(ZipEncoder().encode(archive));
    }

    test('reads the media pool URLs, decoded, with the Media folder too', () {
      final refs = StudioOneProjectParser(song({
        'Song/mediapool.xml': '''
<MediaPool><Attributes x:id="rootFolder"><MediaFolder name="Audio">
  <AudioClip useCount="30"><Url x:id="path" type="1" url="file:///G:/PSY PACK/Media/Psytrance%20Kick%20(1).wav"/></AudioClip>
  <AudioClip><Url x:id="path" type="1" url="file:///Users/me/Loops/Top.aif"/></AudioClip>
  <MusicClip><Url x:id="path" url="file:///G:/x/riff.mid"/></MusicClip>
</MediaFolder></Attributes></MediaPool>''',
        'Presets/Synths/1 - Sample One.preset':
            'xx C:\\Samples\\Stabs\\stab 4.wav\u0000',
      })).readSampleReferences();
      final pool = refs.where((r) => r.use == SampleUse.audio).toList();
      expect(pool[0].candidates, [
        'G:/PSY PACK/Media/Psytrance Kick (1).wav',
        'Media/Psytrance Kick (1).wav',
      ]);
      expect(pool[1].candidates.first, '/Users/me/Loops/Top.aif');
      expect(pool, hasLength(2), reason: 'MIDI in the pool is not audio');
      final sampler = refs.where((r) => r.use == SampleUse.sampler).toList();
      expect(sampler.single.candidates, [r'C:\Samples\Stabs\stab 4.wav']);
    });

    test('a file that is not a song reads as nothing', () {
      expect(
        StudioOneProjectParser(Uint8List.fromList([1, 2, 3]))
            .readSampleReferences(),
        isEmpty,
      );
    });
  });
}
