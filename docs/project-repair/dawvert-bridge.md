# Opt-in external conversion: DawVert bridge

Status, **2026-10-26**: executable experimental adapter with observed real
converter execution. DPM also supports explicit pipelines of up to three
DawVert steps. The canonical implementation, validation and evidence contract
is [Conversion execution](conversion-execution.md); this page is a quick start.

## User-selected prerequisites

Supply a trusted installed Python interpreter by absolute path, the local
`dawvert_cmd.py` from a separately installed DawVert checkout, and explicit
acceptance of possible conversion losses. DPM does not download, bundle or
update the converter. The app can start and inspect files without this runtime.

The adapter uses documented `-it`, `-i`, `-ot` and `-o` arguments. Its declared
format identifiers include `reaper`, `dawproject`, `flstudio`, `ableton`, `lmms`
and `midi`; a selected upstream version may support only particular variants
or directions. CPR/ALL/ARR are not delegated to DawVert. Native ALL recovery is
a separate integrated DPM engine, not a Python dependency.

Example, with illustrative paths:

```sh
dart run bin/project_repair_convert.dart \
  --input "/music/demo.rpp" \
  --target dawproject \
  --script "/tools/DawVert/dawvert_cmd.py" \
  --python "/usr/bin/python3" \
  --accept-loss
```

For an explicitly requested RPP → DAWproject → RPP diagnostic route, use
`--via dawproject --target reaper`. Each step validates the actual output before
passing it onward. Intermediate artifacts and backups are retained, failures
stop the pipeline, and a cumulative report records the results. Manual and
unknown adapters are refused rather than treated as executable steps.

## Output and trust boundaries

A run creates a verified backup and unique export workspace. Supported relative
REAPER media are staged and hashed; generated REAPER media references are
materialized within the output and rewritten to relative paths. A bounded
runtime snapshot supplies DawVert's required modules/data without changing the
installed checkout. Sources are not overwritten. See the canonical document
for path/link checks, byte/count limits, archive preflight and failure reports.

The subprocess uses no shell, has closed stdin, bounded log capture and a
deadline covering process exit and pipe draining. This is **not an operating-
system sandbox**: a user-selected executable can still access host resources.
It must be a trusted installation. Source preservation guards cannot guarantee
that an arbitrary external program will behave safely.

Reports compare supported structural/semantic observations and keep native DAW
reopening and audio-render verification explicitly unverified. Opaque plug-in
state dependencies, preset compatibility, tempo maps, automation and routing
need separate checks. ProjectConverter remains a manually operated candidate;
this bridge does not invent a headless interface for it.

## Observed result and remaining acceptance

The actual adapter completed RPP → DAWproject and the two-step return route with
a generated one-track/one-second audio fixture. The source RPP remained
unchanged, the track name/count survived, and the final referenced WAV had the
same SHA-256. The pinned converter revision and exact media hash are recorded in
[the measured result](conversion-execution.md#observed-real-converter-check-2026-10-26).
This is a real converter execution, not a native DAW reopen or mix-render test.

The whole Flutter suite passed locally on Linux: **4,744 passed, 12 skipped**.
See the [validation record](validation-2026-10-26.md) for commands and analysis
scope. Native macOS Apple Silicon, macOS Intel and Windows build/smoke checks
remain. Versioned real-session coverage, destination DAW
reopening and musical/audio comparisons are still required before claiming
production compatibility for a route. TASK-012/013 are not closed merely by an
export file or passing structural preflight.

Primary references: [DawVert](https://github.com/DawVert/DawVert),
[input adapters](https://github.com/DawVert/DawVert/blob/main/docs/input_plugins.md),
[output adapters](https://github.com/DawVert/DawVert/blob/main/docs/output_plugins.md),
and [ProjectConverter](https://github.com/git-moss/ProjectConverter).
