# Testing

[← README](../README.md) · [Development](development.md) · **Testing** · [Architecture](architecture.md) · [Releasing](releasing.md)

```bash
flutter test                              # everything, ~3 minutes
flutter test test/services/               # a folder
flutter test --plain-name "Cubase SX"     # tests whose name matches
```

No device or window needed — CI runs the same suite on Windows, macOS and Linux.

## What's in it

| Folder | Tests |
|---|---|
| `test/models`, `test/services`, `test/utils`, … | units, against a real Hive database in a temp folder |
| `test/fixtures/projects/` | **real DAW projects** — Cubase SX 3 → 13, Ableton Live 8 → 11, FL Studio 7 → 20, REAPER — each read and compared with its `.expected.json` |
| `test/fixtures/midi/` | real `.mid` files, imported and exported again |
| `test/flows/` | **whole features** over copies of those projects: scan → MIDI → `.mid`, version stacks, archive, sample pack, backup, profile moves |

## Adding a real project

```powershell
scripts/add_test_fixture.ps1 -Daw cubase -Project "D:\Music\Song\Song.cpr"          # one project
scripts/add_test_fixture.ps1 -Daw flstudio -Versions -MaxFileMB 1 -Project "…\Song.flp"  # a folder of versions
```

Then record what the app reads from it, and **read the diff** — a snapshot records a bug as faithfully as a feature:

```bash
UPDATE_FIXTURES=1 flutter test test/fixtures/
```

Only projects you own; no commercial audio or MIDI transcriptions.

## Writing a flow

A flow opens a `FlowLibrary` (`test/flows/flow_library.dart`) — a database and a scan folder of fixture copies — drives the app's services, and checks what comes out the far end. If something stands in the way (a file dialog), split the work from it, as `BackupService.buildBackupJson` was.
