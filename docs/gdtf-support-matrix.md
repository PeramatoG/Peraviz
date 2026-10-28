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
| Selected DMX mode and patch | Partial | Native selected-mode `DMXChannel`/`LogicalChannel`/`ChannelFunction` compilation, ordered 1–4 byte sources, explicit or inferred ranges, and target IDs. Current playback supports one primary MVR break (0), default/explicit GDTF break 1; unsupported multi-break/reference remapping is diagnosed and withheld. See the baseline below. |
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

## MVR/GDTF import compatibility baseline — phase 1

Expectations follow [MVR 1.6 Address, Tables 50–51](https://github.com/mvrdevelopment/spec/blob/main/mvr-spec.md#node-definition-address)
(unique break IDs, default 0, absolute integer or one-based `Universe.Address`)
and [GDTF 1.2 Tables 48–49/DMXChannel](https://github.com/mvrdevelopment/spec/blob/main/gdtf-spec.md)
(top-level GeometryReference, one-based DMX offsets, default break 1, reference
Break remapping and `Overwrite`). A break ID is not a universe offset.

| Case | Existing coverage → additional baseline coverage | Current result |
| --- | --- | --- |
| Independent physical targets | Render-emitter-group and DMX binding suites → real import of three fixtures/two selected modes, six Beams, exact UUID/component/target ownership, 16-bit Pan, pivots, independent RGB/Dimmer and hold across universes | Verified scoped support |
| Repeated GeometryReference | Geometry/template tests → actual repeated Beam nodes, distinct placements, common ancestor DMX control, original GLB sharing and correct native renderer records | Geometry and ancestor control verified; per-instance source remapping deferred |
| Standard primary patch | Lifetime/Unicode and byte-source tests → dotted/absolute MVR addresses, nonzero start offsets, universe offset -1/0 and exact received output values | Verified for MVR break 0 and GDTF default/1 |
| Multiple/non-primary MVR breaks; duplicate IDs | No comparable production regression → native loader/compiler and Godot preparation reject affected bindings while retaining all geometry | Unsupported/invalid, explicitly guarded; no silent first-entry projection into playback |
| GDTF break 2/Overwrite, reference DMXOffset, ambiguous repeated source name | No comparable production regression → selected-mode guards and legacy-metadata non-bypass checks | Unsupported, explicitly guarded; full break/context evaluation remains failing/deferred |
| Shared source/media and reload | Asset lifetime/Unicode tests → deterministic ZIPs, two modes of one GDTF, shared raw meshes/media with independent state, stable IDs after reload, retired nodes and next-preparation cache cleanup | Verified within existing lease policy |
| Cross-fixture address overlap | Existing shared-control tests → intentional co-patch retains six unique physical targets | Allowed shared input, not duplicate fixture identity; no new collision-warning feature |

`test_import_compatibility_baseline.gd` uses the real application import, native
compilation/frames and cached lens setters. Its public generator fixes ZIP metadata
and includes unknown XML/archive entries; SHA-256 remains identical through import,
playback and reload. `import_compatibility_test.h` extends the existing native scene
asset suite. This is behavioral coverage, not schema certification or vendor-corpus
coverage. FixtureTypeID/unknown content remain in the untouched source archive;
no editable or round-trip representation is claimed.

**Confirmed defects and bounded correction:** main selected the first MVR Address
and ignored later breaks; GDTF compilation ignored DMXBreak and reference offsets,
and the geometry-name map selected the last repeated source path. This PR adds
`PVZ-MVR-DMX-PATCH-UNSUPPORTED` / `PVZ-GDTF-DMX-PATCH-UNSUPPORTED`, withholds only
the affected fixture's compiled/compatibility bindings, forwards a bounded setup
warning and full `compile_diagnostics` in the existing native setup summary, and decodes absolute
addresses independently of break ID. The baseline also reproduced a fallback
cleanup error: optional LOD inventory held strong primitive-mesh references beyond
node retirement. It now uses weak provenance; active source/derived owners remain
unchanged. No material, culling or drawing policy changes. This PR does not add
multi-break support. Only
the selected mode/tree is checked; unused modes cannot reject a valid mode.

Follow-up must carry all patch entries/break identities and expand instance-aware
GDTF channel/reference contexts before compiling byte sources, then validate them
through independent universes and renderer targets. Replace these guards only
when that end-to-end contract exists. The existing parsed compatibility-offset
cache can retain media after SceneTree owner removal; the next native preparation
clears that owner (tested). Immediate SceneTree-only extraction retirement would
require a separate ownership change; no new cache subsystem is added here.

Perastage reference: [address reader](https://github.com/PeramatoG/Perastage/blob/78a70c2d467e4147ce3a5f25935638b73ccd237a/mvr/mvr_fixture_addresses.cpp),
[patch service](https://github.com/PeramatoG/Perastage/blob/78a70c2d467e4147ce3a5f25935638b73ccd237a/core/fixture_patch_service.h)
and its `mvr_fixture_addresses_test.cpp` informed raw-entry retention, normalized
break identity and duplicate rejection. No editor/rendering code was transplanted.

## Interpretation boundary

Native C++ owns the supported semantic paths and prepares renderer-ready values. Godot applies those values to registered targets and owns visual approximations. Peraviz-specific fallbacks—such as incomplete color-resource fallbacks, visual beam length, and indexed color-wheel aggregate display—are renderer compatibility behavior, not official GDTF semantics. Their focused documents label them explicitly.

## Realtime transport note

The native subscription, mailbox, and direct pump are the active transport path and do not expand GDTF attribute support. Pan/Tilt remains immediate physical-degree evaluation in this pass; `RealFade` and `RealAcceleration` physical response is not yet claimed.
