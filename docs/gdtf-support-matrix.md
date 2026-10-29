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
| Shutter / strobe | Partial/native | Numbered Shutter(n), Strobe, triangular StrobePulse, PulseOpen/PulseClose and explicitly approximate Random variants; persistent native phase, frequency/constant subphysical parameters, range transitions and generic ModeMaster. Shared ancestor and independent reference/multibreak outputs retain identity. See the bounded temporal contract below. |
| ModeMaster | Partial/native | Exact selected-mode Node paths resolve to stable DMXChannel or ChannelFunction identities, use resolution-aware inclusive `DMXValue` ranges, reach the production setup contract, and evaluate cycle-safely for instantaneous native scalars. Malformed, ambiguous, unresolved, and cyclic graphs are diagnosed during compilation. |
| Relations | Unsupported/deferred | GDTF Relations are not parsed or evaluated by the compiled production runtime. |
| Virtual attributes / DMXProfiles | Unsupported/deferred | No production evaluation contract. |
| Unsupported attributes | Parsed only or unsupported | Preserve/report data when possible; never infer support from legacy Godot helpers or generic enum values. |

## Shutter/strobe temporal playback

Semantics follow [GDTF 1.2 Tables 60–62](https://gdtf-share.com/help/developers/gdtf_1_2/file-format-definition/index.html)
and [Annexes B/F](https://gdtf-share.com/help/developers/gdtf_1_2/annex/index.html).
ChannelFunction PhysicalFrom/PhysicalTo default independently to 0/1. ChannelSet
DMXFrom defaults to 0/1; its end is the next set minus one or the parent boundary.
Set physical endpoints inherit the parent's values unless explicitly overridden.
Ranges are intersected with their parent, inclusive, and interpolated locally in
ordered 8/16/24/32-bit source resolution; descending ranges remain descending.
Malformed/nonfinite supplied values and duplicate sets are diagnosed, not defaulted.
The existing bounded nonstandard DMXTo compatibility is retained inside the natural
function boundary. Unnamed function prefixes retain their parent physical mapping.

Square flashes use Duration (default 0.025 s for standard Shutter strobe).
Annex F triangle/ramp pulses use DutyCycle (default 100%) and TimeOffset at the
pulse's end (default 100%). Constant SubPhysicalUnits are supported; SubChannelSets
and variable parameter ranges remain guarded. Zero Hz produces no temporal modulation
(unmodulated/open presentation policy); negative/unrepresentable Hz never becomes an
arbitrary flashing rate. Explicit English polarity labels use a normalized, exact
whitelist (status 1), not a normative universal 0=closed/255=open rule or substring
matching. Unknown/misleading labels remain diagnosed.

Split StrobeFrequency/Duration use the existing ModeMaster graph. A ChannelFunction
master selects its typed mode; channel-wide masters select among the current typed
mode ranges without a generic selector overriding the waveform. StrobeRate means
time between flashes and remains explicitly unsupported; it is never treated as Hz.
A shutter may use a different break/universe from Color/Dimmer, but a shutter's own
parameter/activation chain must resolve within one universe. Channel-wide typed mode
candidates with additional ModeMaster conditions remain guarded; direct ChannelFunction
masters retain the existing native activation-chain evaluation.

**Peraviz random approximation (status 1):** all four numbered Random families and
StrobeModeRandom variants use the declared nominal Hz, with one deterministic event
per nominal cycle. Event positions are uniformly jittered in the middle half of each
cycle; intervals lie in [0.5,1.5]/Hz and the long-run rate converges to the declared Hz.
Counter hashing keys physical target, activation revision, function and event index.
Hold/identical DMX preserve the sequence; frequency changes retain its event position;
new function/waveform activations restart it. Square flashes retain Duration. Random
pulses reuse triangle/increasing/decreasing shapes, declared shape parameters or
Peraviz defaults of full-period duty/end offset; overlapping windows combine by maximum,
never additive brightness. GDTF does not prescribe this distribution or manufacturer-exact
random pulse timing. Only two candidate events are sampled, without RNG state or catch-up loops.

All envelopes multiply existing shafts, footprints, material/GPU lenses and owned
Native/reference light energy independently of canonical Color/Dimmer. Render/Control
Groups require identical complete temporal authority; any independently seeded random
path uses the existing individual fallback at setup, never regrouping per flash.
Unknown custom effects, ambiguous activation, SubChannelSets and cross-universe
shutter parameter chains remain open with bounded `PVZ-SHUTTER-*` diagnostics/status 2.

For real-scene diagnosis, set `PERAVIZ_SHUTTER_TRACE=<fixture UUID>` before import
(optional `PERAVIZ_SHUTTER_TRACE_TARGET=<physical target ID>`, otherwise first output),
use serial evaluation, then click **Copy shutter diagnostic** in Debug. The selected
fixture or configured UUID is inspected; manual fixture overrides need not be enabled.
The native `get_shutter_trace(uuid, target)` API returns at most 64 cached rows: identities,
reference path, MVR/native addressing, raw/resolution, function/set/mode ranges, physical
endpoints, effective Hz/waveform/parameters and status. No XML or sources are re-evaluated.
Worker ownership returns an explicit unavailable reason. Its frozen-parameter 20-event
sampling probe compares exact windows with 15/30/60/120 FPS; missed windows diagnose visual
aliasing, not incorrect Hz. No smoothing or brightness compensation changes the reference.

Production ZIP/native and Godot regressions cover defaults, range edges, split modes,
independent random outputs, hold, gobo concurrency, renderer parity/replacement, async
handoff and unchanged archives. Visible flashing remains limited by presentation sampling;
full GDTF compliance, Windows GUI/hardware timing and manufacturer-exact random effects
are not claimed by this synthetic coverage.

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
