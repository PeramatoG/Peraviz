# Vector Gobo Prism light profile

Vector Gobo Prism remains the production/reference shaft renderer. GDTF/native
semantics and the Optical Projection State ownership from PR #102 are unchanged.
The shared state now retains a small radial profile value object, not another
scene-state owner. Its consumers are the shaft and the existing surface projector.

## Artifact audit at 71b6a4a

- `GoboPrismMeshBuilder._add_caps` triangulated both near and far silhouettes,
  including gobo holes. The far triangles were a literal illuminated aperture at
  the artificial atmospheric endpoint. Both caps are removed; only outer and hole
  side walls remain. The 36-sided open aperture drops from 140 to 72 triangles.
- The shader multiplied brightness by `1 + 2.2 * weight * abs(N·V)^1.8` and used
  `N·V` again for feather alpha. Triangulated prism normals therefore exposed
  topology as brightness differences, rather than a continuous output profile.
  Separate broad-core/shoulder/rim smoothsteps introduced more apparent bands.
- The distance fade had a 0.35 floor, feather alpha a 0.08 floor, haze a 0.2 floor
  (also forced on CPU), and final alpha a positive radial floor. Gobo opacity also
  had a 0.8 mask floor. The replacement has none of these visibility floors.
- CPU far fade ended at `max(400, range * 12)` metres, or 900 m for the standard
  75 m shaft, and the shader evaluated it in camera distance. Geometry ended
  while still illuminated. Normalized topology Y was also compared with a metric
  `cone_height`, so its axial progress was effectively near the middle everywhere.
- `beam_softness` was declared but did not shape the main profile;
  `beam_radial_falloff` changed normal-facing feather power. FieldAngle did not
  constrain a continuous shaft/surface distribution.
- Emitter setup mapped `beam_angle / field_angle` to `spot_attenuation`, Godot's
  **distance** attenuation property. The direct RenderingServer bridge also mapped
  that property to the angular `LIGHT_PARAM_SPOT_ATTENUATION` identifier; it now
  uses `LIGHT_PARAM_ATTENUATION`. The reference surface uses 2.0, the
  inverse-square-like baseline; angular transmission comes from the shared profile.
- `hint_depth_texture` was declared and sampled behind a uniform branch, while
  production set `depth_feather_enabled=false`. A runtime uniform is not a static
  shader variant and does not remove the declared renderer dependency. The
  reference shader now declares no screen/depth texture or samplers. The shader
  proxy's genuine depth clipping is retained. No GPU timing gain is claimed here.

## Standard data and presentation approximation

GDTF BeamType, BeamAngle, FieldAngle, BeamRadius and LuminousFlux remain canonical
inputs, alongside retained ThrowRatio and RectangleRatio. Wash/Fresnel/PC specify
soft conical projection, Spot hard-edged conical projection, Rectangle hard-edged
pyramidal projection, and None/Glow no projected output. None/Glow remain lens
emission only. No manufacturer/model exceptions or GDTF/MVR changes are introduced.

GDTF does not supply a complete measured angular intensity distribution. Peraviz
reconstructs one **presentation approximation** using the lighting convention that
BeamAngle is approximately the 50% contour and FieldAngle the 10% contour:

```
r = tan(theta) / tan(BeamAngle / 2)
I(r) = exp(-ln(2) * r^p)
p = log(ln(10) / ln(2)) / log(tan(FieldAngle / 2) / tan(BeamAngle / 2))
```

The tangent-space form satisfies both anchors at the source aperture without
per-fragment atan/log. Invalid, reversed, equal or unstable metadata uses p=2 for
Wash/Fresnel/PC and p=8 for Spot/Rectangle. Accepted p is bounded to [0.5,32]. The
profile is continuous, monotonic and centered; no concentric shells are generated.
A future measured/IES-style distribution can replace this value object.

The presentation boundary includes the shoulder down to 0.002 of peak, followed
by a small smooth rim window. This expands the shared geometric support beyond
the source BeamAngle; BeamAngle itself still names the 50% contour. Optical
Projection State resolves that support once for both shaft and projector, retaining
native Zoom in `source_full_angle_deg`. CPU culling bounds cover the shader-expanded
support without adding vertices. Zoom uniformly scales the distribution's
tangent, rather than inventing time-varying photometry or baking textures per DMX
frame. The original Beam/Field metadata is retained. The existing 89-degree half
aperture / 250 m resource guard can compress the distribution at extreme Zoom;
this remains a presentation limit, not a reinterpretation of fixture metadata.

Rectangle uses max(abs(x)/half_width, abs(y)/half_height) and the retained aspect
ratio; open Rectangle gets cached four-sided topology. Other projected types use
circular distance. Gobo vector boundaries shape transmission without replacing the
radial envelope. Both consumers inherit the same absolute roll, parity and aperture.

## Shaft evaluation and finite length

An extruded boundary has no interior radial vertices. Simply evaluating radius on
that surface would give r=1 around an open beam and cannot render a bright center.
The shader instead evaluates one analytic closest-axis point along the view ray,
limited to the finite optical interval, as a cheap column-density approximation.
It uses smooth optical coordinates, never triangle normals. Camera movement
changes that view-ray sample but cannot mutate optical/profile state or geometry.
This is neither ray marching nor a participating-medium simulation.

Axial distance is measured in metres from the shared lens origin, including the
normalized-topology conversion. Shaft attenuation is:

```
exp(-0.018 * strength * d) / (1 + 0.002 * strength * d*d)
    * (1 - smoothstep(0.72, 0.98, d / visual_length))
```

`beam_longitudinal_falloff` is strength, including zero. The independent smooth tail
is exactly zero from 98% of the visual budget onward, even with decay disabled.
The deterministic terminal threshold is 1e-6. The unshaded color output, alpha and emission all reach zero;
intensity and haze zero also produce zero. Additive alpha/emission split the density
by sqrt so their product preserves the underlying radial envelope. No smoke/noise,
extra shell/slice, per-pixel loop or texture sample is added to the ordinary shaft.

## Surface model, controls and resource budget

Surface output is DMX/native energy × footprint multiplier × the **same** radial
profile × gobo transmission, with Godot spot distance attenuation 2.0. Angular
attenuation is disabled (0.0) on profiled projectors so it does not apply a second
unrelated radial curve. Surface masks are cached compositions; original gobo
textures/vector metadata remain untouched. Rotation and Zoom reuse the composition. The compositor multiplies in linear
intensity and encodes sRGB for Godot's projector atlas, preserving the radial anchors.
Source gobo resolution is retained (with a minimum 128×128 profile sampling size).
The cache is renderer-owned, capped at 128 entries and cleared at scene reset;
there are no new playback Nodes, Dictionaries, meshes or curve/texture generation
for color, dimmer, Zoom or phase-only updates.

| Setting | Meaning |
| --- | --- |
| `beam_multiplier` | Beam / shaft intensity only; 0 hides the shaft |
| `footprint_multiplier` | Footprint / surface intensity only; 0 blacks out the surface |
| `spot_multiplier` | Advanced experimental/native realtime-light intensity |
| `beam_softness` | Bounded exponent bias around the resolved profile; 0.32 is neutral |
| `beam_radial_falloff` | Exponent bias; 1.0 is neutral |
| `beam_longitudinal_falloff` | Axial decay strength; 0 disables decay, not the tail |
| `haze_density_multiplier` | Overall shaft density; 0 means no atmospheric shaft |

Old project dictionaries missing `footprint_multiplier` inherit `spot_multiplier`;
explicit new values, including zero, win. Defaults and quick presets include both
controls. The packed native photometric contract remains unchanged: scalar user
presentation gains are applied at the existing adapter boundary, and settings
changes replay held state without requiring fresh DMX.

The generic surface profile supports open Spot, Wash and gobo, but production
**does not enable every open/Wash surface light**. Dense visibility currently turns
on each output's real light when it has a projector; the ownership is per output,
not a bounded grouped fixture-light budget. Enabling profiles for all 1,095 outputs
would therefore activate many additional real lights. The existing gobo activation
policy stays in place until a later batched/grouped surface-light backend. The small
visual fixture explicitly enables its two open lights to review the generic model.

## Validation and remaining acceptance

`test_radial_light_profile.gd` covers anchors, continuity/monotonicity, invalid angles,
BeamType fallbacks, rectangular distance, axial tail, cap-free triangles, gobo mask
multiplication, migration, zero haze and 600 Zoom/intensity updates retaining mesh,
profile identity and projector texture. PR #102's camera/roll/parity/blackout tests
remain, with resolved-support aperture assertions. Dense tests cover independent
shaft/surface blackout and held settings replay.

Reproduce the graphical gallery with Godot 4.7.1 and a real Forward+ renderer:

```
godot --audio-driver Dummy --rendering-method forward_plus --rendering-driver vulkan \
  --path . --script tests/manual/vector_light_profile_gallery.gd
```

The captured cases are open Spot, Wash, asymmetric gobo, near/far surface distances,
and overlapping white beams. Software Vulkan captures verify compilation and visual
behavior; they do not establish the canonical Windows RTX 3070 FPS acceptance.
The 82-fixture / 1,095-output reference scene and matching live DMX are not available
here. Its trace-OFF 24–25 FPS / trace-ON 22–23 FPS baseline must still be compared
on that machine; investigate a repeatable loss above roughly 5%, including added
pixel coverage from the softer support. No progressive-resource-growth assertion
or headless FPS is a substitute for that comparison.
