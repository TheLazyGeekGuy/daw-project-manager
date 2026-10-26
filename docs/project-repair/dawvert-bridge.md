# Opt-in external conversion: DawVert bridge

Status: **experimental, executable CLI; native DAW fidelity not verified**.

This integration is deliberately independent of the Cubase CPR writer. It does
not add support for CPR inputs or promise preservation of routing, plug-in
states, sidechains, clip positions, media references or automation.

## User-selected prerequisites

- An installed, trusted Python interpreter given by **absolute path**.
- A separately obtained and installed DawVert checkout. Select its local
  `dawvert_cmd.py` script. DPM does not download, bundle or update DawVert.
- An explicit acceptance of possible conversion losses.
- The user must verify the result in the **destination DAW**, including MIDI,
  automation, plug-in presets, channel routing and an audio render.

DawVert documents `-it`, `-i`, `-ot`, `-o` command-line options.
Supported local bridge format identifiers: `reaper`, `dawproject`,
`flstudio`, `ableton`, `lmms`, `midi`. The bridge attempts only a
**one-hop** conversion. The selected DawVert build may support only particular
format versions; there is no blanket compatibility or fidelity guarantee.

Example (paths are illustrative, not supplied executables):

```sh
dart run bin/project_repair_convert.dart \
  --input "/music/demo.rpp" \
  --target dawproject \
  --script "/tools/DawVert/dawvert_cmd.py" \
  --python "/usr/bin/python3" \
  --accept-loss
```

The command will:

1. Check extension/signature, bounded source size, script/runtime and explicit
   acceptance.
2. Create and SHA-256 verify a copy in
   `.project-repair-backups/backup-*/`. Backups are never removed by DPM.
3. Copy the input into an independently named
   `.project-repair-exports/dpm-dawvert-*/` directory.
4. For REAPER, stage each relative `FILE` audio/MIDI sidecar by its original
   relative path, verify hashes and stop on missing, linked, absolute,
   parent-relative or excessive references. Opaque plug-in media remains
   unverified. Other input formats do not yet have sidecar staging.
5. Execute the user-supplied script with the staged input, using
   `Process.start` without a shell and a bounded timeout.
6. Inspect the output's format magic where available and verify the source
   project is unchanged. REAPER sidecar checksums are also rechecked.
7. Write `conversion-report.json` with SHA-256 evidence, warning flags and
   explicit `native_daw_reopen_verified=false`. Outputs are not overwritten
   into source folders or automatically indexed as finished projects.

On failure, the backup and isolated run directory are retained for inspection.
The interface does **not** activate a native CPR writer.

## Security and scope limits

- `Process.start` is **not an operating-system sandbox**. A malicious or
  compromised locally installed script can still access user files. Use only
  a trusted, reviewed installation. DPM cannot claim third-party process
  containment.
- The converter may produce a syntactically recognizable yet musically wrong
  output. Signature checking is **not** semantic, sound-render or loadability
  verification.
- REAPER `FILE` extraction is conservative. Embedded paths in binary plug-in
  states are not translated or rewritten. If a project relies on absolute
  media paths or cross-drive libraries, relocate those files manually before
  attempting a conversion.
- The original is never rewritten by DPM. The backup provides a recoverable
  snapshot if an external process changes it, but DPM cannot guarantee a
  user-supplied executable will behave safely.
- Neither DawVert nor ProjectConverter is bundled. Review GPL-3.0 / LGPL-3.0
  licensing and packaging constraints before shipping integrations.
- ProjectConverter documents a GUI workflow for REAPER ↔ DAWproject; it is not
  invoked by this CLI because a stable headless contract is not confirmed.

Reference documentation:
- https://github.com/DawVert/DawVert
- https://github.com/DawVert/DawVert/blob/main/docs/input_plugins.md
- https://github.com/DawVert/DawVert/blob/main/docs/output_plugins.md
- https://github.com/git-moss/ProjectConverter

## Acceptance tests still required

Dart/Flutter analyzer and tests on Windows/macOS/Linux, successful local
DawVert runs against licensed fixtures, native DAW reopen/render comparison,
versioned compatibility matrix and full plug-in state / automation /
sidechain fidelity checks.

**Do not mark TASK-012 or TASK-013 complete solely on the existence of this
bridge.** All converter output remains experimental until verified.
