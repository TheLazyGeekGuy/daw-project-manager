# Project Repair & Inter-DAW Conversion

Status: **architecture proposal / not implemented**. Target application: DAW Project Manager (Flutter). Target contribution model: small upstream-friendly pull requests, with separately maintained conversion engines where appropriate.

## Goals

1. Inspect DAW project dependencies, missing plug-ins and session integrity without opening the DAW.
2. Recover broken Cubase projects and replace VST2/VST3 plug-ins when explicitly approved.
3. Preserve presets, automation and routing where demonstrably supported; report everything unknown or lost.
4. Convert projects among DAWs using the most faithful available path, not a mandatory DAWproject intermediate.
5. Support Windows, macOS and Linux, including inspection on systems that cannot host a particular DAW.
6. **Never overwrite an original project and never write a modified project until its verified backup exists.**

## Documents

- [Requirements](requirements.md) — numbered functional/non-functional requirements and acceptance criteria.
- [Architecture](architecture.md) — modules, interfaces, backup transaction, trust boundaries and cross-platform approach.
- [Interoperability matrix](interoperability.md) — format support, conversions, object mappings, fidelity and evidence levels.
- [Delivery plan](delivery-plan.md) — work packages, milestones, test corpus and upstream contribution strategy.

## Current research inputs

These are **candidate dependencies**, not shipped components:

- [CubaseTools](https://github.com/schwifty00/CubaseTools) (MIT): heuristic CPR extraction; not a general lossless writer.
- [MyDAW](https://github.com/omeriko9/MyDAW): reverse-engineered CPR records/writer; old-Cubase validation is not proof of modern CPR write safety.
- [cpr2rpp](https://github.com/daniel-lynch/cpr2rpp): direct Cubase-to-REAPER research.
- [bravoh-daw](https://github.com/ozzaii/bravoh-daw) (MIT): read-only metadata for ALS, FLP, LOGICX and RPP.
- [DawVert](https://github.com/DawVert/DawVert) (GPL-3.0): broad converter, versions and capability vary by adapter.
- [ProjectConverter](https://github.com/git-moss/ProjectConverter): REAPER/DAWproject bridge.
- [DAWproject](https://github.com/bitwig/dawproject): useful interchange format, not a universal canonical representation.

Any new dependency requires a license, maintenance, platform, security and fidelity review before distribution. Distinguish confirmed supported behavior from proposals and untested assumptions.
