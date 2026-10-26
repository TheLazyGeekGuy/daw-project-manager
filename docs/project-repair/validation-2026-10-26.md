# Validation record — 2026-10-26

Environment: **Linux, Flutter 3.47.8, Dart 3.13.7**. This records observed local
checks of the integrated DPM working tree after reconciliation with the updated
remote branch. It does not record a merge, GitHub Release publication or a
native macOS/Windows build. CI remains main-only by request.

## Automated checks

| Check | Observed result | Scope/evidence |
|---|---|---|
| Whole Flutter suite | **4,744 passed, 12 skipped** | `/tmp/dpm-full-tests.log` ends `02:40 +4744 ~12: All tests passed!`; skipped checks are not counted as executed passes. |
| Python corpus tooling | **14 passed** | Offline HTTP-range/ZIP extraction, bounds, hash and path safety tests; no demo downloads are required by this suite. |
| Broad changed-Dart analysis | **0 errors, 0 warnings, 91 infos; exit 0** | 77 changed paths; `--no-fatal-infos`. Includes 73 informational findings in existing large UI/Drive files and 18 new test underscore-style findings. This is not a blanket clean-analysis result. |
| Final scoped worker/dialog analysis | **No issues found** | Rechecked after the runtime fix; this narrower result does not erase the broad analyzer's informational findings. |

Commands, run from the repository root with the installed SDK:

```bash
/tmp/dpm-flutter/bin/flutter test --no-pub --concurrency 4 --reporter expanded
python3 -m unittest discover -s tools/project_repair -p 'test_*.py' -v
```

The broad analysis used `flutter analyze --no-pub --no-fatal-infos` with the
77-path list captured in `/tmp/dpm-analyzed-files.txt`; its output is
`/tmp/dpm-changed-analysis.log`. The same invocation can be replayed from that
captured list with:

```bash
xargs -a /tmp/dpm-analyzed-files.txt /tmp/dpm-flutter/bin/flutter analyze --no-pub --no-fatal-infos
```

Earlier focused runs included 29 store tests, 12 inspection/recovery/panel
widget tests, seven typed-form tests and 207 backup/Drive regression tests
(including 20 native metadata scenarios). The form suite also passed with
`TZ=Pacific/Kiritimati`, exercising date-only behavior at UTC+14. Backup/Drive
checks use temporary libraries and an in-memory Drive through production
service code; no live account was accessed. These focused counts are not added
to the whole-suite total.

## Real-file and converter evidence

**CPR:** all seven official Cubase 12–15 demo CPRs passed exact SHA-256 equality
after reconstruction of outer/top-level chunk framing with opaque payloads
retained. The recorded saved versions are 12.0.0, 13.0.0, 14.0.5 and 15.0.0.
Individual hashes are in [Sources and corpus](sources-and-corpus.md); the local
result is `/tmp/dpm-corpus/cpr-roundtrip-results.json`. This does not validate
modified CPR writing, pointer rebasing, presets, automation or Cubase reopening.

**DawVert:** the real subprocess adapter at revision
`c6c8be9e0660d9e75a3acecce43a13b0dbe0029c` completed RPP → DAWproject and
RPP → DAWproject → RPP using a generated one-track session and one-second WAV.
The source RPP stayed unchanged, the track name/count survived, and the final
referenced WAV retained SHA-256
`ac8b253193999a1510dce352420a9c7ef8e407d0f714daf2393cf9bfaecbbc3c`.
This is a media-byte check, not audio rendering or equivalent mix playback.
See [Conversion execution](conversion-execution.md) for the command and limits.

**Legacy ALL:** supported compact/fixed-layout recovery has positive synthetic
coverage. The publicly supplied `TABSAX.ALL` is a real negative sample: both the
upstream candidate predicate and DPM find no supported records, so recovery is
refused. There is **no positive real ALL compatibility result** or paired
reference-MIDI comparison. ARR/full-session recovery remains unsupported by the
native decoder. See [Legacy research](legacy-reverse-engineering.md) and
[Conversion execution](conversion-execution.md).

## Remaining acceptance gates

Native builds and smoke tests on **macOS Apple Silicon, macOS Intel and Windows**
remain unobserved. Native DAW reopening, plug-in/preset compatibility, automation,
routing, side-chain and render comparisons remain separate gates. Neither a
green application suite nor byte-identical copied media proves musical fidelity.
Catalog/workspace/Hive/Drive changes remain separate transactions; no global
atomicity or live-account test is implied. Rights, delivery and promotional
publication states are still manually recorded.

The `/tmp` files above are local evidence locations, not committed fixtures or
durable public downloads. Reproducible commands, source pins, hashes and scope
are retained in these repository documents; proprietary demo projects and music
are not redistributed.
