# GDTF support matrix

This is the single capability source of truth for GDTF semantics in the active production runtime. A parser recognizing a name does not imply a rendered feature.

Optional Fake Smoke is a Peraviz shaft-presentation effect; it does not add GDTF/DMX Fog or Haze channel semantics.

## Status definitions

- **Supported (verified scope):** compiled, evaluated, applied by the active native-to-Godot path, and covered by focused tests.
- **Partial:** a bounded production subset is implemented; the stated exclusions remain unsupported.
- **Parsed only:** data can be retained or classified, but no production renderer behavior is claimed.
- **Unsupported/deferred:** no production semantic/rendering contract exists.

## Runtime semantics

| Domain | Status | Current verified scope and limits |
| --- | --- | --- |
| Static model geometry | Partial | Selected-mode hierarchy and GeometryReference expansion; dotted/Unicode Model.File basenames; 3DS and GLB resources with selectable authored Low/Default/High tiers and deterministic fallback; default-on bounded native LOD is derived presentation for eligible opaque static 3DS/glTF casing, with exact original selectable; declared positive model dimensions fitted to transformed bounds; retained GLB hierarchy and shared raw resources. Named primitive approximations and tagged missing-part placeholders are presentation fallbacks, not exact standard-library meshes. No new animated/deforming-model support is claimed. |
| Selected DMX mode and patch | Partial | Native selected-mode `DMXChannel`/`LogicalChannel`/`ChannelFunction` compilation, ordered 1–4 byte sources, explicit or inferred ranges, and target IDs. Native routing resolves numbered breaks and supported GeometryReference instances; see the bounded addressing contract below. |
| Dimmer | Supported (verified scope) | Physical/normalized native evaluation and dirty target-oriented Intensity rows, including repeated targets. |
| Pan / Tilt | Supported (verified scope) | Physical-degree evaluation and component-oriented Transform rows. |
| Zoom | Supported (verified scope) | Native selected-mode physical full-angle evaluation, target-oriented BeamOptics rows, and cached Lightweight Prism aperture/spread mutation. |
| Additive color | Partial | Native target-local ColorAdd_R/G/B/W/RY/GY composition. Physical emitter resources are used where valid; documented renderer fallbacks cover incomplete data. Other additive families are not claimed. |
| Subtractive color | Partial | Native ColorSub_C/M/Y and linked filter evaluation for the documented physical/fallback scope. |
| CIE / CCT / Tint | Partial | Native CIE xyY, CTO/CTB/CTC, and Tint paths for supported physical records and documented approximations; calibrated spectral/CRI rendering and complete gamut handling remain deferred. |
| Color wheel selection/index | Partial | Seated selection and indexed adjacent-slot metadata, native target-local color composition, and `WheelSelection` rows. Indexed spatial split rendering, spin/random/audio motion, ColorEffects and animation wheels are unsupported. Spin/random/audio/unknown wheel modes currently display the first palette slot; compilation reports this fidelity limitation. ColorEffects is diagnosed, retains source bytes/ranges/activation, and uses first-slot Color when linked to a wheel, otherwise unchanged base Color. Compatible emitters may aggregate these explicitly approximate resolved colors; shaft resolution does not imply effect support. Missing-resource fallback applies to wheel-owning identities or explicit unresolved links, not unrelated ColorMixReset/ColorCalibrationMode controls. Intentionally unlinked ColorEffects remains approximate; an explicit unresolved FX Wheel link remains a blocker. |
| Static seated `Gobo(n)` | Partial | Exact `WheelSlotIndex`, seated ChannelSet windows, native `GoboSelection`, open-slot clearing, cached masks, and bounded static multi-wheel binary composition. See [Gobo control](GDTF_GOBO_CONTROL.md). |
| Gobo motion | Partial | Exact `Gobo(n)Pos` physical Angle and `Gobo(n)PosRotate` signed AngularSpeed (degree/s), including generic ModeMaster activation, are evaluated natively and applied parametrically to one visible selected-gobo layer per Beam/wheel instance without topology work or `PlacementOffset`. Independently moving multi-layer composition, WheelSpin, SelectSpin, shake, random, audio, and effects remain deferred. |
| Beam geometry profile | Partial | Setup-time BeamType, BeamAngle, FieldAngle, BeamRadius, ThrowRatio, RectangleRatio, LuminousFlux, and ColorTemperature are retained for current renderer use. BeamType None and Glow remain emission-only and never allocate a projected cone. The reference Vector Prism and existing gobo surface path use a [shared approximate radial profile](vector-light-profile.md) anchored by BeamAngle/FieldAngle, with BeamType fallbacks. This is Peraviz presentation, not measured photometry. Authored/default provenance is retained; open Spot/Wash/Fresnel/PC retain native unshadowed surface parameters without automatically owning realtime lights; see [bounded surface ownership](surface-light-ownership.md). Scalable visible open footprints, grouped presentation, measured photometry and Focus semantics remain incomplete. |
| Focus / Iris / Frost | Unsupported/deferred | No authoritative live renderer contract. |
| Prism selection/rotation | Parsed only | Names may be classified or retained; no production prism behavior is claimed. |
| Shutter / strobe | Parsed only | Names may be classified or represented in generic structures; no verified production shutter/strobe rendering contract is claimed. |
| ModeMaster | Partial/native | Exact selected-mode Node paths resolve to stable DMXChannel or ChannelFunction identities, use resolution-aware inclusive `DMXValue` ranges, reach the production setup contract, and evaluate cycle-safely for instantaneous native scalars. Malformed, ambiguous, unresolved, and cyclic graphs are diagnosed during compilation. |
| Relations | Unsupported/deferred | GDTF Relations are not parsed or evaluated by the compiled production runtime. |
| Virtual attributes / DMXProfiles | Unsupported/deferred | No production evaluation contract. |
| Unsupported attributes | Parsed only or unsupported | Preserve/report data when possible; never infer support from legacy Godot helpers or generic enum values. |

## MVR/GDTF import and native addressing

Expectations follow [MVR 1.6 Address, Tables 50–51](https://github.com/mvrdevelopment/spec/blob/main/mvr-spec.md#node-definition-address)
and [GDTF 1.2 Tables 48–49/DMXChannel](https://github.com/mvrdevelopment/spec/blob/main/gdtf-spec.md).
MVR entries retain their unique, zero-based break identity (default 0), original
order, explicit/default flag and parsed absolute or one-based `Universe.Address`.
GDTF numbered break **n** resolves only to MVR break **n−1**, independent of entry
order; no break identifier is added to a universe. GDTF's absent DMXBreak means 1.

| Case | Verified production coverage | Status |
| --- | --- | --- |
| Primary patch and independent targets | Absolute/dotted addresses, universe offset −1/0, nonzero starts, UUID/component/target identities, reflected hierarchy/pivots, independent RGB/Dimmer, gobo media | Existing behavior preserved |
| Multiple and sparse breaks | One fixture reads distinct universes; native sparse MVR break 7 → GDTF break 8, without requiring primary 0 | Supported |
| Ordered source bytes | Native noncontiguous 16/32-bit sources; actual renderer 16-bit Pan and 24-bit Tilt on explicit break 2 | Supported up to four bytes; never truncate an invalid fine byte |
| Repeated GeometryReference | Distinct qualified source paths, numbered-break offsets, final-child Overwrite mapping, independent RGB/Dimmer, same-instance ModeMaster and common-ancestor controls | Supported for one reference level |
| Shared assets and lifecycle | Immutable models/media shared; fixture state independent; archive SHA-256, held universes, per-instance blackout/restore, serial/forced native async playback, renderer replacement and reload | Verified scoped support |
| Co-patching | Six physical outputs retain independent identities with shared cross-fixture input | Allowed; no automatic identity merging |
| Duplicate/malformed/missing patches; ambiguous geometry | Bounded native diagnostics, no legacy-metadata bypass, source geometry retained | Invalid/unresolved; affected fixture bindings withheld |
| Nested reference routing, cross-instance ModeMaster, cross-universe reference offsets | Explicit native guard rather than guessed routing | Follow-up; no support claimed |

Reference children correspond in ascending order to the numbered breaks used by
referenced channels; their DMXBreak must identify that source break. The final
child supplies Overwrite's effective break/offset. Offsets are one-based and added
to every ordered byte; supported reference DMXAddress forms are 1–512 and `1.Address`.
Offsets or patch-adjusted bytes crossing a 512-slot break remain guarded. Mechanical
hierarchies and source geometries are not rewritten. Existing inherited control
ownership and ChannelFunction/ModeMaster evaluation remain unchanged; this adds
addressing, not new composition/Relation semantics.

`test_import_compatibility_baseline.gd` and `import_compatibility_test.h` extend the
existing production harnesses with deterministic public ZIPs, native compilation,
universe snapshots and actual renderer/lens checks. The forced-worker variant has
no gobo domains: existing gobo scenes deliberately retain their serial transaction.
This is behavioral coverage, not full specification compliance, schema certification,
a vendor corpus or external hardware validation. Unknown data stays in the untouched
source archive; no editor/export representation is added.

`PVZ-MVR-DMX-PATCH-UNSUPPORTED` validates standard entries; the GDTF equivalent
validates effective instance sources and dependencies. Each failure withholds the
affected fixture atomically, preserving independent valid fixtures and graphical
geometry. Warnings remain bounded; complete structured issues are available in
`compile_diagnostics`, without raw XML dumps. The legacy single-universe metadata API
withholds complex patches; only compiled native routing drives production playback.
Nonstandard scalar MVR addresses remain a compatibility fallback only when standard
Addresses is absent. Parser-only legacy definitions without geometry trees retain
existing identities; this does not establish geometry validity.

Perastage's [address reader](https://github.com/PeramatoG/Perastage/blob/78a70c2d467e4147ce3a5f25935638b73ccd237a/mvr/mvr_fixture_addresses.cpp)
and patch tests informed entry retention/duplicate rejection; no editor/rendering
code is transplanted. Existing compatibility-offset media leases retire at the next
native preparation; immediate SceneTree-only retirement remains a separate follow-up.

## Interpretation boundary

Native C++ owns the supported semantic paths and prepares renderer-ready values. Godot applies those values to registered targets and owns visual approximations. Peraviz-specific fallbacks—such as incomplete color-resource fallbacks, visual beam length, and indexed color-wheel aggregate display—are renderer compatibility behavior, not official GDTF semantics. Their focused documents label them explicitly.

## Realtime transport note

The native subscription, mailbox, and direct pump are the active transport path and do not expand GDTF attribute support. Pan/Tilt remains immediate physical-degree evaluation in this pass; `RealFade` and `RealAcceleration` physical response is not yet claimed.
