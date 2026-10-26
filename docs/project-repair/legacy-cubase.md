# Legacy Cubase songs and arrangements

Reviewed: 2026-10-26. Scope: `.ALL` and `.ARR` to `.CPR`, including the distinction between a documented conversion route and a validated, lossless migration.

## Official recovery route

Steinberg documents **Cubase SE 3, SL 3 and SX 3** as the last versions that import `.ALL`/`.ARR` songs. Its recommended compatibility choice is SE 3 when the appropriate edition is unclear. Import with **File > Import > Cubase Song**, then save a new CPR; gathering audio into a new project folder helps retain referenced media. The importer retains audio/MIDI tracks and parts but loses VST instruments, effects and mixer settings. It therefore cannot establish full-session fidelity. The old Mac versions require a PowerPC-compatible environment; installation on a current Mac is not an assumed route. [Official conversion instructions](https://helpcenter.steinberg.de/hc/en-us/articles/115000075750-Converting-Cubase-VST-songs-ALL-ARR-into-CPR-format).

The same article lists compatible legacy licenses, including selected Cubase editions through Pro 11. It does **not** establish that a current Cubase 12–15 license starts SE/SL/SX 3. Consult its edition-specific table before preparing the conversion workstation.

## Licensing after the eLicenser shutdown

The eLicenser service ended on **2025-05-20**. Existing licenses on a functioning USB-eLicenser or active Soft-eLicenser remain usable, but transfers between containers and reactivation of Soft-eLicensers are unavailable. eLicenser software cannot use the newer Steinberg Licensing system. These constraints make possession of a working licensed legacy installation a real conversion prerequisite. [Steinberg shutdown FAQ](https://helpcenter.steinberg.de/hc/en-us/articles/26707291820562-eLicenser-service-closed-down-on-May-20-2025).

Do not instruct users to perform online eLicenser maintenance as a prerequisite: activation, transfer, maintenance and license-database update operations have been removed. Installers remain available for compatible operating systems. [Current eLicenser Control Center documentation](https://helpcenter.steinberg.de/hc/en-us/articles/360008841379-eLicenser-Control-Center-License-Management-Details-Downloads).

## DPM integration boundary

The legacy route is a **manual, vendor-documented bridge**, not an internal ALL/ARR decoder or an unattended converter. File-extension recognition is a candidate format identification, not validation of a proprietary song structure. A conversion planner must keep the following fields separate:

DPM's separate experimental ALL-to-MIDI reader targets the record patterns
derived from AllToMidi. It does not implement this direct CPR bridge or establish
support for all Atari/PC ALL and ARR variants. See the
[native format research plan](legacy-reverse-engineering.md).

| Field | Value or evidence |
|---|---|
| Source formats | Cubase legacy song `.ALL` and arrangement `.ARR` |
| Bridge | Locally available, licensed Cubase SE/SL/SX 3 |
| Output | A new `.CPR` plus collected media |
| Execution mode | Manual host operation |
| Available in headless DPM | No |
| Documented loss | VST instrument/effect settings and mixer configuration |
| DPM-validated fidelity | Unknown until source and destination evidence are compared |
| Entitlement check | User confirms a functioning compatible legacy license |
| Follow-on work | Read-only CPR inspection, dependency report and target Cubase reopening |

Renaming an extension is never a conversion. Byte-preserving CPR reconstruction does not validate an ALL/ARR importer. A surviving track name does not prove preservation of MIDI events, instruments or automation.

## Recovery procedure and evidence

1. Copy the legacy song, its associated audio and any existing preset exports into a recovery workspace. Record SHA-256 fingerprints before importing.
2. If the original host still runs, collect a reference render, track list, tempo changes, screenshots of the mixer and exported plug-in presets. This evidence supports reconstruction of settings the importer cannot retain.
3. Import a working copy using the licensed legacy bridge. Keep a record of the host edition/version and any warnings.
4. Save under a distinct name and gather audio into the new project directory. Keep the original and its backup intact.
5. Inspect the produced CPR with DPM. Compare its decoded properties with the reference evidence and mark unsupported properties as unknown.
6. Open the CPR in the intended target Cubase installation. Check track order, event timing, tempo, media paths and audible output. Recreate missing instruments and mixer settings explicitly.
7. Record each adjustment and remaining difference. A successful open is one verification result; it is not an assertion that the project sounds identical.

These are engineering acceptance steps for the recovery workflow. They are not a claim that DPM has automated Steinberg's importer or verified any particular legacy song.

## Conditions for upgrading the route's status

A user-supplied, lawfully usable ALL/ARR test song is needed together with its companion assets and a reference render or equivalent semantic expectations. Record the exact importer, source hash, output hash and target reopening result. Classify audio/MIDI observations separately from known losses and manually reconstructed settings. Publish only provenance and results that may be shared; do not assume that the underlying song or media may be redistributed.

## Alternative discovered on 26 October 2026: Atari2Cubase

The author's [Steinberg forum announcement](https://forums.steinberg.net/t/free-tool-open-your-atari-st-cubase-songs-arr-all-in-cubase-nuendo-14/1043292), dated 10 October and updated 22 October 2026, describes [atari2cubase](https://atari2cubase.robert-068.workers.dev/): an in-browser converter from legacy Atari Cubase ALL/ARR to DAWproject and Standard MIDI. The author reports support for several Atari variants and says PC support is still being developed. These are author claims, not a DPM fixture-validated compatibility matrix.

This creates a possible path without SE/SL/SX 3: legacy file -> DAWproject -> import into compatible current Cubase -> Save As CPR. It does not itself write CPR. Cubase's [current DAWproject import documentation](https://www.steinberg.help/r/NlutMEjaYjAqk1bhdcAc5g/lLYXHFy~93TXcpLFJN0GoQ) describes the import step. MIDI is a more limited fallback and cannot retain audio or plug-in states.

As of this review no reusable open-source license or corresponding public GitHub repository was identified. The author said on 12 October that releasing the source was under consideration. DPM records this as an external, manual, experimental route; it does not bundle, copy or execute the web application's engine. The author's local-only processing claim has not been independently audited. A browser-delivered script is not by itself permission to redistribute its implementation.

Before a native ALL/ARR adapter can be enabled, collect version-labelled, redistributable fixtures; obtain a licensed reader or implement independently; compare tracks, part offsets, notes, controllers, tempo and SysEx; preserve undecoded data with explicit loss reports. Atari and Windows/Mac Cubase VST files require separate validation.
