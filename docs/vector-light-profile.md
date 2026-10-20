# Vector Gobo Prism light profile

Vector Gobo Prism remains the production/reference renderer. Native GDTF/DMX
semantics and PR #102's shared Optical Projection State remain authoritative.
This document describes the corrected presentation contract on the existing branch.

## Canonical data and provenance

The compiled native Beam profile and setup renderer manifest retain three flags:
`beam_type_explicit`, `beam_angle_explicit`, `field_angle_explicit`. They originate
from the scene model's `has_beam_type`, `has_beam_angle`, `has_field_angle`; no
manufacturer/model heuristic or nonstandard "Beam" BeamType is introduced.

GDTF 1.2 defaults remain **Wash, 25°, 25°**, including when all flags are false.
Explicit Spot remains Spot; explicit Wash/Fresnel/PC remain their authored type.
Provenance is presentation/diagnostic metadata, not a change to those defaults.
BeamRadius, LuminousFlux, selected DMXMode and native Zoom semantics are unchanged.

The native runtime converts source flux once using its existing unitless-light
approximation: a 10,000 lm reference × DMX dimmer × 0.02. Dense output composition
applies the represented output's existing `effective_luminous_flux/10000` scale once,
yielding `max(source LuminousFlux,0) * dimmer * 0.02`; Godot applies the user
surface gain once. No physical-light-unit calibration is claimed. Gobo selection,
contour count and support width never mutate canonical source flux. Shaft dimmer,
mask transmission and presentation gains remain separate from the native source.

Enable `beam_debug_optics` to log one concise optical diagnostic at explicit optics
updates, including authored/default BeamType, current BeamAngle (source=zoom when
changed), base BeamAngle, source FieldAngle, resolved dynamic FieldAngle and
anchored/fallback status. Color/dimmer-only playback does not format these strings.

## Radial curve, dynamic FieldAngle and bounded support

An independently authored, useful pair `0 < base_beam < base_field < 178°` anchors
a tangent-space generalized Gaussian:

```
ratio = tan(base_field/2) / tan(base_beam/2)
p = log(ln(10)/ln(2)) / log(ratio)
r = tan(theta) / tan(current_beam/2)
I(r) = exp(-ln(2) * r^p)
dynamic_field = 2 * atan(tan(current_beam/2) * ratio)
```

Stable p is bounded to [0.5,32]; invalid/equal/reversed/unstable pairs or missing
independent authored angles use a BeamType fallback. A default FieldAngle=25° is
never treated as independent measured photometry around a narrow native Zoom.
The base ratio is cached, so narrow/wide cycling does not regenerate curves or
textures, accumulate drift, or leave a static wide FieldAngle around a narrow core.

The earlier branch already scaled a retained base curve when `profile_beam_angle`
was present. Its principal widening error was geometric support down to an
arbitrary **0.2% contour**, compounded by lost provenance and fallback/default
ambiguity. The corrected state explicitly resolves and reports dynamic FieldAngle;
it no longer expands geometry to that arbitrary low-energy contour.
Compatibility updates without a supplied base angle now retain the first authored
base (or canonical 25° default), including when callers pass fresh parameter maps.
They cannot repeatedly rebase the static FieldAngle profile on the current Zoom.

For anchored profiles, support tangent is **1.06 × the resolved field tangent**.
The smooth final feather begins at FieldAngle (10%) and reaches zero at that
support. Fallback Spot/Rectangle use a compact 1.18 × beam tangent; fallback
Wash/Fresnel/PC use 1.65 × with a longer shoulder. There is no marketing-name
classification or huge missing-metadata halo. Rectangle uses its retained aspect
metric with corner-normalized geometry fitting the shared projector support.
None/Glow remain nonprojecting.

Softness and radial falloff are bounded artistic exponent biases, neutral at 0.32
and 1.0 respectively. They never overwrite canonical angles. Optical Projection
State resolves the common support, base transform, lens offset, Zoom, absolute
roll/parity and resource guards. Shaft and footprint share that state and CPU cull
bounds. The existing 89° half-aperture / 250 m radius guards still limit extreme
presentation cones.

## Coherent axial sample and intensity calibration

A single analytic closest-axis ray sample estimates the column envelope of the
boundary mesh; evaluating radius only on a shell would give its edge everywhere.
Radial and longitudinal attenuation now use the **same optical sample** in metres
from the lens. Reference axial decay is:

```
exp(-0.055 * strength * d) / (1 + 0.015 * strength * d*d)
```

At strength=1 this is approximately 0.23 at 10 m and 0.024 at 25 m relative to the
lens. Strength=0 removes physical decay, retaining the mandatory smooth tail from
72% to 98% of visual length. A second surface-position tail guard ensures every
terminal mesh vertex is exactly transparent even if its view-ray sample is nearer.
The terminal regression epsilon remains 1e-6. No positive visibility/haze floor,
end cap, depth dependency, ray marching, extra shell/slice or smoke/noise is added.

The full shaft path is:

```
(DMX/output shaft intensity / 20) * haze * 0.8
    * radial * axial * tail
    * static gobo transmission * per-ray topology coverage compensation
```

The previous fourfold overdrive response and double-sided additive contribution
made decay harder to see. The default beam gain 20 now represents a linear unity
reference response with headroom: haze=0.22 gives peak density 0.176 before masks
and attenuation. Unshaded ALBEDO/alpha split density by sqrt so their additive
product preserves the radial curve. Emission, color and alpha all reach zero.
The source flux conversion is not repeated in the shaft shader.

## Gobo topology energy and view stability

Godot uses clockwise front faces; the existing side-wall winding presents its
**exit walls** as front faces. The shader selects entry walls for outside cameras
and exit walls for inside cameras, accumulating only one orientation despite
`cull_disabled`. Entry walls avoid a dark terminal opening in the cap-free mesh.
The vertex stage classifies the camera in optical space; gobos also sample their
source mask there. No normal-facing intensity multiplier is used. The real GPU
inside-camera regression guards against disappearing when entering the shaft.

Concave contours and holes can still create several exit walls on one view ray.
A setup-only 256-offset × 128-direction RF lookup bounds their count in the
normalized artwork plane. A ray through the homothetic extrusion maps to a straight
line there. Its conservative reciprocal count divides additive wall contributions;
more contour walls therefore cannot create additional source energy. Convex rings
are bounded by two crossings independent of tessellation. General contours use
projected monotone chains, subdividing angular cells at edge-perpendicular events;
internal vertices cannot create spurious extra crossings or artificial fan bands.
One-cell minimum dilation permits smooth bilinear lookup without underestimating
coverage. A scan-converted chord integral then weights each line by its actual
transmitted length: tiny stripes/holes cannot receive the full brightness of a
solid thick lobe. The open shaft uses the corresponding analytic circular chord. There are no per-pixel loops or per-frame contour analyses.

Static analysis also integrates linear luma × alpha over the source aperture.
Binary open area is already represented by the chord integral, so only residual
grayscale/alpha transmission relative to vectorized open area is multiplied again.
Open transmission is 1 and the residual gobo scalar is clamped to [0,1]. This shaft-energy
approximation is deliberately conservative: complex concave masks or small holes
may be somewhat dimmer rather than receiving excess additive energy. It is not a
full participating-medium integral. The lookup is attached to cached topology;
mesh/lookup cache and footprint cache are each limited to 128 entries and reset
with the scene. Active resources remain owned by their existing output nodes.

## Open and gobo footprints

Every projected type is eligible for surface illumination in the existing dense
and compatibility visibility policies. Shaft gain zero also resolves surface optics
at cold setup, without allocating an unnecessary shaft mesh.

Open **Spot/Wash/Fresnel/PC** use the existing SpotLight3D with **no projector
texture and no shadow requirement**. Native angular attenuation is fitted to the
resolved support and 50% contour:

```
rim = (1-cos(beam_half)) / (1-cos(support_half))
spot_angle_attenuation = log(rim) / log(0.5)
```

This single native exponent is a qualitative fit to the common profile, not exact
measured photometry. Wash is softer than Spot, center is brightest and Zoom shares
the shaft support. Distance uses `spot_attenuation=2.0` (inverse-square-like), with
the correct RenderingServer distance enum `LIGHT_PARAM_ATTENUATION`.

A real gobo retains its shadowed projector, multiplying original transmission by
the shared radial profile. Rectangle also needs a derived mask: a native circular
cone cannot reproduce its rectangular boundary. These texture paths use angular
attenuation zero to avoid an additional unrelated radial curve. Original source
textures/vector metadata are never blurred or resized in place.

Advanced `footprint_softness` defaults to 0.04, accepts [0,0.25], and allows zero for
sharp diagnostic comparison. At cached texture creation, premultiplied linear source
RGB is filtered with two running-sum separable box passes; radius is bounded to 16
pixels and source resolution is retained (minimum sampling 128×128). The radial
profile is applied afterward and encoded for Godot's sRGB projector atlas. Softness
is part of the cache key. Rotation/Zoom reuse textures; no Focus semantics are added.

## Controls and performance boundary

Basic controls remain **Beam / shaft intensity** and **Footprint / surface
intensity**. Either or both can be zero independently. Advanced controls retain
beam softness, radial falloff, axial decay (normal=1), shaft haze (zero allowed),
footprint softness and experimental realtime-light intensity. Old settings migrate
`spot_multiplier` to missing `footprint_multiplier`; missing softness gets 0.04.

No new light/beam Nodes are created per frame. Open footprints activate already
owned **unshadowed** light RIDs rather than generating shadowed gobo projectors.
This avoids texture/atlas/shadow costs but still activates more real lights than
the previous shaft-only policy. At 1,095 outputs, clustered-light count and GPU
surface lighting may remain a cost problem for the later grouped/batched backend.
No same-scene RTX 3070 before/after FPS can be measured here: the canonical MVR,
matching live DMX and Windows GPU are unavailable. The previous 24–25 FPS trace-OFF,
22–23 trace-ON, 30–32 no-beams and 50–59 transforms-only figures remain a reference,
not a claimed result. Investigate a repeatable loss beyond roughly 5% on that scene.
The published captures are reproducible software Forward+ fixtures, not substitutes
for the user's real-fixture acceptance or performance measurement.

## Regression and visual review

Native tests cover authored/default provenance and unchanged luminous-flux scaling.
GDScript tests cover all six metadata combinations, tangent-ratio Zoom cycling,
bounded support, monotonic radial/axial profiles, mandatory tail, native open
footprints with shaft gain zero, cached softness/source immutability, topology
coverage bounds and existing camera/roll/parity/blackout/held-state synchronization.

Run the real Forward+ review fixtures with Godot 4.7.1:

```
godot --rendering-method forward_plus --rendering-driver vulkan --audio-driver Dummy \
  --path . --script tests/manual/vector_light_profile_gallery.gd
godot --rendering-method forward_plus --rendering-driver vulkan --audio-driver Dummy \
  --path . --script tests/manual/gobo_energy_validation.gd
```

The energy fixture compares an open shaft, equal-open-pixel-count simple/complex
gobos and a camera inside the shaft. It fails if a gobo exceeds open image energy
or the inside-camera shaft disappears. The gallery reviews Spot/Wash surfaces,
gobo alignment/softness, near/far attenuation and white overlap. Measured/IES-style
photometry may supersede these presentation approximations when available; none
are written back into GDTF/MVR.

The software Forward+ energy fixture measured open=1016.50, simple=723.69 and
complex=635.39 background-subtracted linear image units (71.2% and 62.5% of open).
These are presentation regression measurements at one camera, not lumens or FPS.
Both gobos have the same open pixel count; extra holes do not add shaft energy.
The inside-camera capture also contains a visible shaft.

Review captures: [narrow Spot](images/vector-light-profile/narrow-spot.png),
[wide Spot](images/vector-light-profile/wide-spot.png),
[open Spot](images/vector-light-profile/open-spot.png),
[Wash](images/vector-light-profile/wash.png),
[gobo](images/vector-light-profile/gobo.png), and
[inside camera](images/vector-light-profile/energy-inside.png).
