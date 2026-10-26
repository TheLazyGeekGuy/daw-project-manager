# Read-only inspection CLI

The inspection implementation reuses the existing Cubase and REAPER parsers in DAW Project Manager. It does **not** parse/serialize plug-in state or modify CPR files.

```sh
flutter pub get
dart run bin/project_repair_inspect.dart "/path/to/song.cpr"
dart run bin/project_repair_inspect.dart "/path/to/song.cpr" "/path/to/song.rpp" > report.json
flutter test test/services/project_repair/
```

Output JSON includes the format, track count when available, names of detected plug-ins and explicit inspection limitations. `plugin_loadability: untested` must never be interpreted as `missing` or `working`. Other formats may be recognized but detailed extraction remains unimplemented; their empty list is NOT evidence that a project has no plug-ins.

The CLI reads files only. No third-party code is loaded and no conversion is executed.

## Safety scope

The `VerifiedProjectBackup` helper is a building block, not yet an approved production write transaction. Project modification remains unavailable until filesystem durability, symbolic link safety, failure injection and true native-DAW validation are completed.
