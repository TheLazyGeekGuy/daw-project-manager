# Executable conversion, recovery and evidence

## Native legacy ALL recovery in DPM

`LegacyAllConversionService.convert` provides a native, integrated DPM action
for recovering MIDI from the two `.ALL` layouts implemented by
[AllToMidi](https://github.com/OnjLouis/AllToMidi). Its decoder/writer was ported
to Dart under the upstream MIT license. It requires no Cubase 3 installation,
Windows executable, Python or .NET runtime. The same code can run on macOS
Apple Silicon/Intel and Windows; this increment's observed tests ran on Linux.

The service requires explicit acceptance of recovery limits, creates a
SHA-256-verified backup, decodes the input, validates its generated MIDI chunks
and events, and writes a new `recovered.mid` plus JSON report in a unique managed
export directory. It never overwrites the `.ALL` or previous exports.

The compatibility APIs share this guarded engine: `NativeLegacyAllReader`
adapts immutable recovered events and time signatures for the existing preview,
and `NativeLegacyAllConversion` delegates conversion to the same service while
retaining its public result and report format. Its report links to the canonical
safety report. Both expose skipped-part counts and defaulted-tempo evidence;
the preview cannot accept a layout that the conversion decoder rejects. The
standalone preview encoder remains a bounded SMF utility, not another file
conversion path. New callers should use the explicit-consent service.

Supported scope: selected compact/fixed event records, track names, part
positions, channels, notes/velocity/duration, controllers, program changes,
aftertouch, pitch bend, initial tempo, and the observed time-signature records.
Output is Standard MIDI File type 1 at 480 PPQ. Known limits include mid-song
tempo, fixed-layout time-signature changes, SysEx and unobserved variants. No
audio, VST instrument/effect state, mixer or native automation recovery is
claimed. `.ARR` and `.CPR` writing are explicitly unsupported.

The development command uses the same native DPM service:

```bash
dart run bin/project_repair_convert.dart \
  --engine native-all \
  --input /path/archive.ALL \
  --target midi \
  --accept-loss
```

Every output reports recovered tracks/notes/parts, skipped parts, whether the
initial tempo had to default, source/output hashes and the backup path. A file
with no recognized events is rejected. A structurally valid MIDI does not
establish equivalent playback to the original Cubase song.

### Evidence and known unsupported sample

- Unit tests cover synthetic compact/fixed records, exact expected tick deltas,
  repeated arrangement parts, channel and velocity, tempo, time signature,
  malformed input, MIDI framing, repeated exports and source preservation.
- `TABSAX.ALL`, publicly supplied in
  [the author's Steinberg forum discussion](https://forums.steinberg.net/t/free-tool-open-your-atari-st-cubase-songs-arr-all-in-cubase-nuendo-14/1043292),
  is a negative fixture: 23,826 bytes; SHA-256
  `3e21a5946814d5b8b999f3ade02530ca55f3e852d4940e4b6d7654e1ea717daf`.
  The upstream selection algorithm finds zero record candidates, and DPM
  refuses conversion. There is no paired reference MIDI. Its original Cubase
  version is unconfirmed. The music is not redistributed in this repository.
- No positive real `.ALL` compatibility corpus or DAW playback validation is
  claimed in this increment. See the attributed source revision and changes
  in `third_party/alltomidi/README.md`.

## DawVert execution

The local adapter uses DawVert's documented `-it`, `-i`, `-ot`, `-o` arguments.
The user chooses their trusted Python runtime and installed `dawvert_cmd.py`;
DPM does not automatically install tools. Native Cubase CPR is not a DawVert
input/output capability advertised by DPM.

```bash
dart run bin/project_repair_convert.dart \
  --input /path/session.rpp \
  --target dawproject \
  --script /path/DawVert/dawvert_cmd.py \
  --python /absolute/path/to/python \
  --accept-loss --timeout-seconds 300
```

The default root is `.project-repair-exports` beside the source. A run contains:

- `input/`: verified source clone and supported relative REAPER media.
- `runtime/`: bounded copy of the converter's Python modules and data folders.
- `output/`: converted project and materialized REAPER media where applicable.
- `conversion-report.json`: provenance, warnings and observed semantic diff.

DawVert reads `data_main` and discovers plug-ins relative to its working
directory. A snapshot is therefore necessary; simply launching its original
script with an empty export folder as cwd did not work. The adapter snapshots
the expected code/data folders, does not copy the user's configuration or
sample caches, and records each copied file's SHA-256. No upstream source is
vendored in DPM. Runtime, project, archive, media-count and byte limits apply.

REAPER source `FILE` references must be relative, present and unlinked.
Traversal/absolute host references fail before the converter starts. Generated
REAPER references must resolve inside that run; they are copied with hash
verification into `output/media/` and rewritten to relative paths. The source
RPP is never rewritten. Opaque plug-in dependencies remain unverified.

The child process receives staged files, no shell interpolation, closed stdin,
bounded output capture and a deadline that includes pipe draining. A process
that ignores termination is killed after a short grace period. This is not an
OS security sandbox; a locally supplied trusted executable can access host
files and the network. The adapter does not claim it can contain malicious code.

## DAWproject and MIDI preflight

DAWproject validation checks the ZIP central directory and local headers,
UTF-8 member names, duplicate/path/symlink hazards, member counts and sizes,
bounded XML/state decompression with CRC32, `project.xml`, `metadata.xml`, root
elements, version 1.0, application metadata, referenced files and duplicate IDs.
ZIP64 and encrypted archives are refused. XML DTD/entity declarations are
refused. Media is not decompressed just for inspection.

The read-only report lists tracks, plug-in IDs, bounded embedded state hashes,
notes, clips, automation points and unresolved/external references. Conversion
requires self-contained archives with no missing references or duplicate IDs.
This is structural preflight, not complete XSD validation or native reopening.

MIDI preflight validates MThd/MTrk sizes, format/division, variable-length
integers, running status, channel/meta/SysEx event framing and end-of-track.
It does not synthesize audio or prove the timing matches a proprietary source.

## Explicit multi-step routes

`ConversionPipeline` executes up to three explicitly selected DawVert steps,
keeps intermediate outputs/backups, stops at the first failure and writes a
cumulative report. For example, a diagnostic round-trip:

```bash
dart run bin/project_repair_convert.dart \
  --input /path/session.rpp --via dawproject --target reaper \
  --script /path/DawVert/dawvert_cmd.py \
  --python /absolute/path/to/python --accept-loss
```

Each step validates the actual output before passing it on. This executor
refuses manual and unknown adapters. Native ALL recovery currently runs as its
own DPM action; its generated MIDI can subsequently enter a supported route.
The planner can show manual legacy Steinberg/ProjectConverter paths and
experimental Atari paths, but those declarations never invoke DawVert for
`.ALL`, `.ARR` or CPR.

## Fidelity report

The report compares track count, a duplicate-preserving multiset of track
names, and observed plug-in instance counts where both readers support them.
Changes are reported as differences. Matching these observations never becomes
a claim of lossless conversion. Unknown note placement/duration, tempo maps,
state equivalence, automation, routing, side-chain, media playback, DAW reopen
and audio render checks remain explicitly unverified. Built-in or unsupported
device equivalence is not inferred from plug-in names or matching counts.

## Observed real converter check, 2026-10-26

A generated one-second mono WAV and one-track REAPER session were passed
through DPM's actual subprocess adapter using DawVert revision
`c6c8be9e0660d9e75a3acecce43a13b0dbe0029c`. Both RPP → DAWproject and the
two-step RPP → DAWproject → RPP pipeline completed. The original RPP hash was
unchanged, the track name/count survived, and the final referenced WAV was
byte-identical to the input (SHA-256
`ac8b253193999a1510dce352420a9c7ef8e407d0f714daf2393cf9bfaecbbc3c`).
The returned RPP uses a relative, hashed media path. No DAW was opened and no
plug-in, automation or mix-render equivalence was tested. A noisy synthetic
process ignoring termination also hit its configured deadline and produced a
failure report while retaining the source backup.

## Source roles and licensing

| Source | Verified role | Integration boundary |
|---|---|---|
| [bitwig/dawproject](https://github.com/bitwig/dawproject) at `ee4dcdde75940f30e14e55401a26955a58b8322b` | MIT XML/ZIP format specification and schemas | Structural validation and interchange; not a CPR decoder |
| [roex-audio/DAWproject-py](https://github.com/roex-audio/DAWproject-py) at `70e65aeb7b260cfec3871ca89ca8d80022c44496` | MIT Python DAWproject model/load/save/XSD API | Useful reference or optional future tooling, no proprietary conversion claim |
| [git-moss/ProjectConverter](https://github.com/git-moss/ProjectConverter) at `fd032b89948579d72dcf8b0da68d3bd6173a844e` | LGPL-3.0 REAPER ↔ DAWproject JavaFX application | Manual candidate; no invented headless CLI. Upstream documents limits for AU, parameter envelopes, complex routing and tempo ramps |
| [DawVert](https://github.com/DawVert/DawVert) | GPL-3.0 external converter CLI | User-installed separate runtime; no GPL code copied into the MIT host. Redistribution requires its own license review |
| [OnjLouis/AllToMidi](https://github.com/OnjLouis/AllToMidi) | MIT reverse-engineered `.ALL` MIDI recovery | Attributed native Dart port; no `.ARR`, CPR or full-session claim |

The complete production compatibility matrix still requires real sessions,
supported platform builds, destination DAW reopening and domain-specific
musical/audio comparisons.
