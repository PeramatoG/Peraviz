# GDTF support matrix

This is the single capability source of truth for GDTF semantics in the active production runtime. A parser recognizing a name does not imply a rendered feature.

## Status definitions

- **Supported (verified scope):** compiled, evaluated, applied by the active native-to-Godot path, and covered by focused tests.
- **Partial:** a bounded production subset is implemented; the stated exclusions remain unsupported.
- **Parsed only:** data can be retained or classified, but no production renderer behavior is claimed.
- **Unsupported/deferred:** no production semantic/rendering contract exists.

## Runtime semantics

| Domain | Status | Current verified scope and limits |
| --- | --- | --- |
| Selected DMX mode and patch | Supported (verified scope) | Native selected-mode `DMXChannel`/`LogicalChannel`/`ChannelFunction` compilation, ordered 1–4 byte sources, explicit or inferred ranges, and target IDs. |
| Dimmer | Supported (verified scope) | Physical/normalized native evaluation and dirty target-oriented Intensity rows, including repeated targets. |
| Pan / Tilt | Supported (verified scope) | Physical-degree evaluation and component-oriented Transform rows. |
| Zoom | Supported (verified scope) | Native selected-mode physical full-angle evaluation, target-oriented BeamOptics rows, and cached Lightweight Prism aperture/spread mutation. |
| Additive color | Partial | Native target-local ColorAdd_R/G/B/W/RY/GY composition. Physical emitter resources are used where valid; documented renderer fallbacks cover incomplete data. Other additive families are not claimed. |
| Subtractive color | Partial | Native ColorSub_C/M/Y and linked filter evaluation for the documented physical/fallback scope. |
| CIE / CCT / Tint | Partial | Native CIE xyY, CTO/CTB/CTC, and Tint paths for supported physical records and documented approximations; calibrated spectral/CRI rendering and complete gamut handling remain deferred. |
| Color wheel selection/index | Partial | Seated selection and indexed adjacent-slot metadata, native target-local color composition, and `WheelSelection` rows. Indexed spatial split rendering, spin/random/audio motion, and animation wheels are unsupported. |
| Static seated `Gobo(n)` | Partial | Exact `WheelSlotIndex`, seated ChannelSet windows, native `GoboSelection`, open-slot clearing, cached masks, and bounded static multi-wheel binary composition. See [Gobo control](GDTF_GOBO_CONTROL.md). |
| Gobo motion | Native semantic contract only; rendering deferred | Exact official identities, wheel numbers, scopes, physical ranges, wheel/ChannelSet links, and relevant Attribute metadata are preserved for native evaluation. No indexed, spin, shake, random, or audio motion is rendered. |
| Beam geometry profile | Partial | Setup-time BeamType, BeamAngle, FieldAngle, BeamRadius, ThrowRatio, RectangleRatio, LuminousFlux, and ColorTemperature are retained for current renderer use. Advanced photometry is not complete. |
| Focus / Iris / Frost | Unsupported/deferred | No authoritative live renderer contract. |
| Prism selection/rotation | Parsed only | Names may be classified or retained; no production prism behavior is claimed. |
| Shutter / strobe | Parsed only | Names may be classified or represented in generic structures; no verified production shutter/strobe rendering contract is claimed. |
| ModeMaster | Partial/native | Exact selected-mode Node paths resolve to stable DMXChannel or ChannelFunction identities, use resolution-aware inclusive `DMXValue` ranges, reach the production setup contract, and evaluate cycle-safely for instantaneous native scalars. Malformed, ambiguous, unresolved, and cyclic graphs are diagnosed during compilation. |
| Relations | Unsupported/deferred | GDTF Relations are not parsed or evaluated by the compiled production runtime. |
| Virtual attributes / DMXProfiles | Unsupported/deferred | No production evaluation contract. |
| Unsupported attributes | Parsed only or unsupported | Preserve/report data when possible; never infer support from legacy Godot helpers or generic enum values. |

## Interpretation boundary

Native C++ owns the supported semantic paths and prepares renderer-ready values. Godot applies those values to registered targets and owns visual approximations. Peraviz-specific fallbacks—such as incomplete color-resource fallbacks, visual beam length, and indexed color-wheel aggregate display—are renderer compatibility behavior, not official GDTF semantics. Their focused documents label them explicitly.
