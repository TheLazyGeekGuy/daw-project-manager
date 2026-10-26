# AllToMidi-derived legacy recovery

The native DPM implementation in
`lib/services/project_repair/legacy_all_midi_decoder.dart` is a Dart adaptation
of `AllConverter`, `AllEvent`, and `DecodedTrack` from
[OnjLouis/AllToMidi](https://github.com/OnjLouis/AllToMidi), revision
`ea2e985f680e020a8efd662085ac01b8edc03770`.

Copyright (c) 2026 AllToMidi contributors. Licensed under the MIT License;
the full notice is in [LICENSE.txt](LICENSE.txt) and the application's shipped
root `LICENSE` asset. The original WinForms interface, preferences, updater,
networking code, and Windows executable are not included.

## Adaptations

- Pure Dart decoder and Standard MIDI File writer, usable by DPM on macOS
  Apple Silicon, macOS Intel, Windows, and Linux without .NET or Cubase.
- Input, record-candidate, event, track and MIDI variable-length integer limits.
- Fixed records stop before the next part's header. Incomplete compact records
  fail rather than yielding silently truncated event lists.
- Stable ordering for simultaneous equal-priority MIDI events.
- Original track-name Windows-1252 bytes are retained in MIDI metadata.
- Explicit skipped-part counts, default-tempo evidence and uncertainty report.
- Separate source SHA-256 backup, validated output and unique export directory.

The port is experimental. Automated positive tests use explicitly synthetic
compact/fixed records. The public `TABSAX.ALL` sample is an unsupported negative
case: the upstream record-selection predicates find no candidate tracks in it.
That failure is not evidence that all `.ALL` variants are supported.

The upstream project does not support `.ARR` or write `.CPR`. DPM preserves
those boundaries. This is an integrated DPM feature; the development CLI calls
the same service and is not a separate macOS application.
