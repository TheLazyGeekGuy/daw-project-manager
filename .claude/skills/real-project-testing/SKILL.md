---
name: real-project-testing
description: Find and fix bugs in DAW Project Manager's readers and features with real DAW projects — survey a whole library with the app's readers, add projects to the test collection (test/fixtures/projects), record and review their snapshots, and run features end to end over them (test/flows). Use when the user says "test with my projects", "find bugs in the parser", "add this project as a fixture", "survey my library", "is the FL/Cubase/Ableton reader right", or brings a project the app reads wrongly.
argument-hint: "[folder or project file]"
---

# Testing on real projects

Synthetic projects only test what someone thought to write. Real ones found,
in one pass: FL 7's 20-byte notes read as 2-billion-tick clips, a minute-long
scan, Cubase SX/4/5 with no tempo or MIDI in 51 projects, "C Major" on 58
Cubase 11 projects that never set a key, Live 8 with no tempo, preset names
listed as plug-ins.

Three tools, from widest to deepest:

| Tool | What it does |
|---|---|
| `tool/library_survey/library_survey_test.dart` | reads **every** project under a folder; flags errors, slow reads, absurd clips, no tempo |
| `test/fixtures/projects/` + `project_corpus_test.dart` | a curated collection, each project's reading snapshotted in `.expected.json` |
| `test/flows/` | whole features over copies of the collection, on a real database |

## 1. Survey a library

```bash
SURVEY_ROOT="D:\MusicProduction\Projects" SURVEY_OUT=survey_before.jsonl \
  flutter test tool/library_survey/library_survey_test.dart
```

Read only, but **every read downloads a cloud-drive file** (Proton Drive,
OneDrive placeholders): survey local folders; on a cloud drive list names
first and read a few.

Then group the JSON lines (`daw`, `ver`) and look for what's off: a version
where a whole generation reads nothing (`clips: 0`, `bpm: null`), one key
on everything, reads over 2 s. After a fix, survey again into another file
and diff: what changed should be exactly what you meant to change.

**Measure before you change a reader.** Before relaxing a byte check,
collect that byte across every candidate in every project (a short Python
script over the files is fine) — "byte 12 is 2 in 98% of 115,000 notes" is
a rule; one file is a guess. Check the result can't misfire on newer files
(gate on the app version the file states, not on a byte pattern).

## 2. Add a project to the collection

```powershell
scripts/add_test_fixture.ps1 -Daw cubase -Project "D:\...\Song\Song.cpr"
scripts/add_test_fixture.ps1 -Daw flstudio -Versions -MaxFileMB 1 -Name "Song (FL 10 + FL 20)" -Project "D:\...\Song.flp"
```

Pick for coverage, not count: a DAW version the collection lacks, a folder
of versions (stacks), samples beside the project (sample pack), MIDI.
`-MaxFileMB 1` keeps big audio out; then look at what was copied:

- **No commercial audio, no third-party MIDI** (song transcriptions,
  downloads) — even when the user owns everything else. Delete those.
- No caches (`.peak`, `.asd`, `.csh` — the script skips them).

Record and **read** the snapshot — it records a bug as faithfully as a
feature:

```bash
UPDATE_FIXTURES=1 flutter test test/fixtures/
```

Look at tempo, key, clip lengths in bars, plug-in names, track names.
Nonsense there is a reader bug: fix the reader, not the snapshot.

## 3. Flows

`FlowLibrary.open(only: ['<daw>/<name>'])` gives a database and a scan
folder of copies; `scan()`, `deepScan()`, `reopen()` (a relaunch),
`wipeDatabase()` (a new machine). Check what comes out the far end against
what went in — notes after a `.mid` round trip, bytes after an archive.

- A flow never reads the machine outside its temp folder: projects name
  paths that exist only where they were made (`_referencesWithin` in the
  sample pack flow). Otherwise local and CI runs see different files.
- Something in the way (a file dialog) means the work should be split
  from it, as `BackupService.buildBackupJson` was.

## 4. Every fix

A regression test in the reader's unit test, built the way the real file
is laid out (comment which real project showed it), the snapshots
regenerated and read, `flutter test` green, then commit — one commit per
kind of bug, saying which projects it was found in.
