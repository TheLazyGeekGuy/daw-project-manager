# Architecture

[← README](../README.md) · [Development](development.md) · [Testing](testing.md) · **Architecture** · [Releasing](releasing.md)

Flutter, [Riverpod](https://riverpod.dev) for state, [Hive CE](https://pub.dev/packages/hive_ce) for storage. One codebase for Windows, macOS, Linux, Android and iOS.

```
lib/
├── models/          data: MusicProject, Release, MidiClip, …
├── repository/      Hive boxes: projects, MIDI clips, collections, trash
├── providers/       Riverpod providers (providers.dart)
├── services/        scanning, metadata, Drive sync, backup, archive, sample pack
│   ├── daw_parsers/ one reader per DAW format
│   └── midi/        .mid read/write, preview synth
├── ui/              pages, dialogs, widgets
├── utils/           pure helpers
└── l10n/            UI strings, 9 languages
```

**How a project gets in:** `ScannerService` finds project files → `ProjectRepository` stores a row → Deep Scan runs `MetadataExtractor`, which hands each format to its reader in `daw_parsers/`.

**How the UI gets it:** `repositoryProvider` → `allProjectsStreamProvider` → `projectsProvider` (filtered, sorted) → both dashboard views.

The rules that keep it together — what syncs, how deletions travel, why a version stack has no file — are in [`CLAUDE.md`](../CLAUDE.md). Read the parts you touch.
