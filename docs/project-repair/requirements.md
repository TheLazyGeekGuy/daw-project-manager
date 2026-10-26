# Software requirements specification

Status: **proposed**. All MUST requirements are acceptance gates unless explicitly marked as future milestones.

## Safety and provenance

| ID | Requirement | Acceptance criterion |
|---|---|---|
| SAFE-001 | MUST keep every original project file immutable; outputs use distinct paths. | Hash and byte content of source remain unchanged after success, cancel and failures. |
| SAFE-002 | MUST create a complete, verified backup before any modification to project data. | Backup bytes and SHA-256 match input before the writer starts; fail closed on errors. |
| SAFE-003 | MUST prevent backup deletion by cleanup, retention, or bulk operations. | Automated cleanup skips managed backup directories; no delete action on managed backups. |
| SAFE-004 | MUST write to a temporary output, structurally validate it, then publish via safe replacement/rename if supported. | Crashes or validation failures leave no misleading final output. |
| SAFE-005 | MUST preserve unknown source objects and binary plug-in states as opaque evidence when reading/writing. | No decoded-to-unknown field is silently dropped; unsupported edits blocked. |
| SAFE-006 | MUST record source fingerprint, target fingerprint, converter versions, rules and losses in a machine-readable manifest. | JSON report reproducible and attributable to exact project/version. |
| SAFE-007 | MUST support explicit restore from verified backup, without overwriting newer files silently. | Restore requires target conflict handling and hash verification. |

## Inspection and diagnosis

| ID | Requirement | Acceptance criterion |
|---|---|---|
| INSP-001 | MUST discover and index supported native project formats and application versions. | Correct format detection using file signatures where known; unknown is reported as unknown. |
| INSP-002 | MUST enumerate tracks, identities, routing, media references, plug-ins and their instance identities where safely decoded. | Repeated same-named tracks remain distinct; unsupported fields visibly unknown. |
| INSP-003 | SHOULD identify missing, disabled, incompatible, failed-to-load and license-blocked plug-ins separately. | Present-on-disk is never equated with loadable; status includes evidence source. |
| INSP-004 | SHOULD scan installed plug-in manifests/bundles for VST2, VST3, AU and CLAP subject to platform support. | Identifiers, architecture, vendor and formats reported; no arbitrary plug-in execution during passive scan. |
| INSP-005 | MUST support read-only recursive project inventory and dependency reports. | Scanning does not change source files. |

## Repair and preset migration

| ID | Requirement | Acceptance criterion |
|---|---|---|
| REPR-001 | MUST offer preview and user approval before a plug-in substitution. | No automatic unsupported substitution; preview lists instance, UID, target and impact. |
| REPR-002 | SHOULD support VST2-to-VST3 migration without depending solely on Steinberg compatibility declarations. | Version-specific mapping profiles can be selected and verified independently. |
| REPR-003 | SHOULD allow replacement with a different instrument/effect while retaining original state in the report/archive. | Replacement is flagged non-equivalent if parameters cannot be reconstructed. |
| REPR-004 | SHOULD prefix affected track names with configurable markers (e.g. [REPLACED], [PRESET UNVERIFIED]). | Old names recorded; duplicate track names remain distinct. |
| REPR-005 | MUST differentiate exact state transfer, translated state, approximated state, reset state and unverified state. | Status never implies preset preservation without verification. |
| REPR-006 | SHOULD map automation by stable parameter identities and normalized/unit-aware values. | Unsupported lanes explicitly listed; no silent reassignment by numeric index. |
| REPR-007 | SHOULD validate bus layout, side-chain, latency and routing after replacement. | Broken/incompatible buses flagged with evidence. |

## Conversion and fidelity

| ID | Requirement | Acceptance criterion |
|---|---|---|
| CONV-001 | MUST expose multiple independently versioned import/export adapters. | Adapter declares read/write capabilities and supported source versions. |
| CONV-002 | MUST consider direct native-to-native conversions before intermediate conversions. | Route selection can rank direct and pivot paths based on declared support. |
| CONV-003 | MAY use DAWproject, AAF, MIDI or stems as fallback routes; never as mandatory canonical transport. | Route provenance and losses included in report. |
| CONV-004 | MUST preserve unrepresentable source information in a sidecar where legally and technically possible. | Source blocks retained byte-for-byte with object association. |
| CONV-005 | MUST provide a per-object and per-field fidelity report, including not-tested and unknown statuses. | Conversion cannot be reported 100% faithful without comparison evidence. |
| CONV-006 | SHOULD provide bidirectional adapters only where read and write both pass validation. | Matrix shows each direction separately. |
| CONV-007 | SHOULD support project batches with per-item isolation and recoverable failure. | One damaged project does not affect others. |

## Platforms, security and quality

| ID | Requirement | Acceptance criterion |
|---|---|---|
| PLAT-001 | MUST support read-only inventory and analysis on Windows/macOS/Linux. | CI runs available reader fixtures on three OSes. |
| PLAT-002 | MUST make plug-in load tests optional and sandboxed in a separately killed worker. | Malfunctioning plug-in does not crash main process. |
| PLAT-003 | MUST state when platform-specific plug-in probing or DAW reopening is unavailable. | Linux cannot claim verification of macOS AU/Windows-only VST binaries. |
| SEC-001 | MUST treat project files, presets and converter executables as untrusted. | Bounded parsing, decompression limits, timeouts and path traversal safeguards. |
| SEC-002 | MUST use explicit opt-in before running external converter binaries. | Invocation and permissions visible; no implicit download-and-execute. |
| QUAL-001 | MUST require byte-identical read/write roundtrip on known supported fixtures before enabling edits for that format/version. | Tests compare SHA-256 and full byte diff. |
| QUAL-002 | MUST require reopen in the target DAW and functional assertions for a converter to be called validated. | Corpus includes real DAW acceptance, track/automation/plugin checks and optional audio render comparison. |
| QUAL-003 | MUST run regression tests for parser crashes, malformed inputs, duplicate track names and missing assets. | CI and fuzz/property tests; no false success. |

## Status vocabulary

Use **verified**, **converted**, **approximated**, **lost**, **unsupported**, **unknown**, **untested**. The last three MUST remain distinct. A missing value in an inspector output does not prove that the project lacks that element.
