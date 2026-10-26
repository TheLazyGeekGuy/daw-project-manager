# Inter-DAW interoperability and fidelity matrix

**Status:** research inventory and target design, NOT a certificate of working conversions. Distinguish **read**, **write**, **host-native export/import**, **indirect route** and **unverified**.

## Native formats and candidate engines

| DAW / standard | Extension | Structure / caveats | Candidate read | Candidate write |
|---|---|---|---|---|
| Cubase | .cpr | Proprietary RIFF-like serialized records | CubaseTools; cpr2rpp; MyDAW | MyDAW experimental old-version writer; modern write unverified |
| Nuendo | .npr | Proprietary Steinberg | Research | Research |
| Ableton Live | .als | GZIP XML | bravoh-daw; DawVert (11 documented) | DawVert (11 documented) |
| FL Studio | .flp | Binary events | bravoh-daw; DawVert (FL 20+ documented) | DawVert |
| REAPER | .rpp | Text chunks | bravoh-daw; DawVert; ProjectConverter | DawVert; ProjectConverter |
| Logic Pro | .logicx | macOS project package/binary | bravoh-daw metadata only | daw2logic research |
| Bitwig | .bwproject | Proprietary | Native DAWproject import/export | Native DAWproject import/export |
| Studio One | .song | Proprietary | Native DAWproject import/export | Native DAWproject import/export |
| Pro Tools | .ptx | Proprietary | Research / AAF exchange | Research / AAF exchange |
| Ardour | .ardour | XML + assets | Research | Research |
| LMMS | .mmp / .mmpz | XML/compressed | DawVert | DawVert |
| Tracktion Waveform | .tracktionedit | Structured session | Research | DawVert output |
| Renoise | .xrns | ZIP with XML/assets | Research | Research |
| DAWproject | .dawproject | Open ZIP/XML interchange | DawVert; native participating DAWs | DawVert; native participating DAWs |
| AAF | .aaf | Structured interchange | pyaaf2 / adapters | pyaaf2 / adapters |
| MIDI | .mid | SMF | DawVert / MIDI libraries | DawVert / MIDI libraries |

## Candidate route matrix (directed)

| Source → Target | Candidate route | Validation status | Main fidelity concern |
|---|---|---|---|
| Cubase CPR → REAPER RPP | cpr2rpp direct | Implementation exists; functional fidelity unverified here | Plug-in state, automation, mixer routing |
| Cubase 14+ → Bitwig / Studio One | Cubase export DAWproject → target import | Host-specific behavior not certified | Native effects, unsupported Cubase objects |
| REAPER ↔ DAWproject | ProjectConverter / DawVert | Supported path reported; confirm exact versions | Plug-in state, automation, routing |
| Ableton Live 11 ↔ FL Studio | DawVert | Bidirectional adapters documented; pair untested here | Devices, VST states, automation |
| Ableton Live 11 ↔ REAPER | DawVert | Adapters exist; pair untested here | Devices, clips, MIDI transforms |
| FL Studio ↔ LMMS | DawVert | Adapters exist; pair untested here | Native synth/FX translation |
| DAWproject → Logic | daw2logic | Adapter exists; constraints require testing | AU conversion, missing plugin states |
| Historical Cubase → Logic | Cubase Legacy Converter / AAF | Limited restoration | MIDI, plug-ins, automation |

**Do not claim:** a path is lossless merely because both adapters exist, that DAWproject is an exhaustive interchange format, or that an installed plug-in will load on any OS.

## Object-to-object mapping and fidelity risks

| Object | Typical mapping | Fidelity risk / required evidence |
|---|---|---|
| Audio track / clip | Track + regions | Media path, offset, fades, sample position, stretch |
| MIDI clip / notes | Pattern/region + MIDI events | PPQ, expression, articulation, note IDs, per-note data |
| Tempo/time signature | Tempo map | Continuous curves and timing offsets |
| Folder / group / VCA | Folder, bus, AUX, control automation | Different hierarchy/control semantics |
| Inserts, sends, side-chain | Processor graph and bus ports | Channel layouts, pre/post fader, latency |
| VST2 / VST3 / AU / CLAP | Instance + UID + saved state | Incompatible state schema, format or OS |
| EQ / dynamics natives | Native device or third-party substitute | DSP response may diverge at matching numeric values |
| Automation | Parameter envelopes | Parameter IDs, units, interpolation, scaling |
| Warp/time-stretch | Warp markers | Algorithmic differences |
| Markers, colors, windows | Closest UI counterpart | UI semantics or unrepresentable state |

## Route selection

Choose among all feasible paths:
1. Filter based on format versions, OS/tool availability and declared adapter capabilities.
2. Rank according to *verified* preservation of notes, tempo, media, states, automation, routing and bus topology; penalize approximations and unknowns.
3. Offer multiple routes with preview and explicit losses. Never silently replace a plug-in or throw away an opaque state.
4. Evaluate actual output; if a target DAW is unavailable, mark reopen/audio fidelity **untested**.

A quantitative confidence score may be added only after an evidence-backed corpus exists. Until then use **verified**, **converted**, **approximated**, **lost**, **unsupported**, **unknown**, **untested**.
