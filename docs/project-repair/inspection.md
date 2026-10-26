# Read-only project and plug-in diagnostics

## Delivered behavior

The project detail inspection dialog performs file parsing in an isolate and
shows decoded tracks, saved DAW version, CPR chunk structure, serialized plug-in
UID evidence, limitations, and a copyable JSON report. File and byte-array entry
points reject inputs over 256 MiB. REAPER text is decoded as UTF-8.

A CPR UID group retains its serialized occurrence count. It is not an active
instance count: cached/offline records may repeat. The inspector does not
silently collapse dependencies with the same name and different declared IDs.

For legacy `.all` and `.arr` songs, the dialog presents the documented external
Cubase import steps and explicit losses. These inputs are identified by file
extension only, and DPM does not claim to parse or automatically convert them.
See [Legacy Cubase](legacy-cubase.md).

For validated CPR containers, **Preserve CPR and verify round trip** creates a
verified backup, an unchanged reconstructed CPR, and opaque chunk evidence in a
new managed workspace. This action uses `CubasePreservationService`; it does not
rename tracks or migrate plug-ins. A successful unchanged reconstruction does
not certify any mutation.

## Passive local inventory

The optional scan includes standard platform folders and user-entered extra
folders. It never executes plug-in code. Reports include scanned/requested roots,
unavailable directories, skipped links, malformed manifests, and explicit
entry/depth truncation. Names ending in `.dll` remain `VST2-candidate` entries.

Steinberg's optional `moduleinfo.json` supplies factory/class metadata without
loading a component. DPM checks `Contents/Resources/moduleinfo.json`, then the
older `Contents/moduleinfo.json` location. Only `Audio Module Class` processor
entries are inventoried as VST3 identities; controller classes are excluded.
One bundle may supply several processor classes. Vendor, version, class ID and
manifest location are retained. The optional `Compatibility` declarations are
reported as replacement candidates, not proof of preset compatibility.

Primary references:

- [Steinberg module information](https://steinbergmedia.github.io/vst3_dev_portal/pages/Technical%2BDocumentation/VST%2BModule%2BArchitecture/ModuleInfo-JSON.html)
- [Steinberg plug-in bundle structure](https://steinbergmedia.github.io/vst3_dev_portal/pages/Technical%2BDocumentation/Locations%2BFormat/Plugin%2BFormat.html)

The manifest reader accepts JSON with SDK-style comments and trailing commas,
using string-aware processing so URLs and quoted punctuation survive. Other
JSON5 extensions are deliberately rejected and surfaced as unverified rather
than guessed. Reads are bounded to 1 MiB, 64 nesting levels, 1,024 classes and
bounded compatibility entries. Linked roots, manifests, and linked ancestors
are skipped. Bounds and link checks reduce accidental traversal; this passive
filesystem reader does not claim adversarial filesystem race isolation.

## Match evidence

| State | Meaning |
|---|---|
| `identifierPresent` | A serialized ID equals one scanned VST3 processor declaration. |
| `ambiguous` | Several installation or name candidates remain. |
| `compatibilityCandidate` | A manifest declares a replacement for the requested ID. |
| `identifierNotFound` | The ID was not found in inspected manifests; same-name hints may be shown. |
| `candidatePresent` | A name matched, but no stable identifier was supplied. |
| `notFoundByName` | No name matched in the folders scanned. |
| `unknown` | Identity is absent or its encoding is unsupported. |

GUID/CID comparison normalizes case, standard braces and hyphen separators. It
does not invent byte-order conversions or infer an AU/CLAP/VST2 identity from a
filename. If a project supplies an identifier, a different-ID same-name binary
cannot satisfy it. A CPR serialized GUID can match a VST3 manifest CID, but this
remains declared-identifier evidence: neither the source namespace nor the
binary/vendor authenticity is independently certified.

All results retain `identity_verified: false`, `loadability: untested`,
`license_status: unknown`, and `absence_is_conclusive: false`. A missing manifest,
custom install location, unavailable drive or platform-specific binary can
explain an unresolved dependency. In-process plug-in loading, licensing checks,
architecture verification and native DAW reopening remain separate acceptance
gates. No optional load-probe worker is bundled by this increment.

## Verification

Focused tests cover manifest classes/versions/aliases, comments and commas,
malformed/oversized metadata, duplicate identities, symlinks, scan bounds,
identifier/name conflicts, replacement declarations, Unicode REAPER names,
legacy import guidance, explicit user-triggered scans and custom roots. Tests
use synthetic metadata and never load a third-party plug-in binary.
