# Shared optical projection geometry

GDTF/native semantic state determines physical optical values. Peraviz resolves
shared presentation geometry into one Optical Projection State per emitter.
Shaft and surface footprint remain independent renderers of that state and may
not maintain competing authoritative optical transforms.

## Boundary and ownership

The selected GDTF mode, exact Beam geometry, channel relationships, native Zoom
full aperture, wheel selection and native indexed/continuous phase are unchanged.
Nothing is written into GDTF or MVR. `optical_projection_state.gd` is exclusively
Peraviz presentation state, attached once to each existing emitter. Dense handles
retain that same object; the vector shaft retains its identity for diagnostics.
Photometry stays in native dense state; texture selection/cache stays in
`NativeGoboResourceRegistry`. The state owns no color, intensity or texture resource.

The state resolves the emitter-local base transform, aperture and half-aperture,
visual length, finite lens radius/far radius, lens offset, artwork scale, roll,
alignment and parity. Ancestor fixture transforms supply Pan/Tilt to both consumers
without duplicating world transforms. Explicit replacement of an emitter's local
transform rebases the optical transform. The lens offset shifts the common optical
origin once, rather than shifting only the shaft.

## Audit of prior competing calculations

| Value | Previous derivation/mutation | Current owner/conversion |
| --- | --- | --- |
| Origin and axis | Light's local transform; shape providers independently added lens shift/offset | Shared base transform and offset; fixture ancestors remain authoritative for Pan/Tilt |
| Optical basis | Projector cached a base basis and rolled the light; rotation helper incrementally compensated its child | State derives both absolute bases from the unrolled base |
| Zoom/full angle | Native dense full/half values; adapter separately wrote half angle while shape recomputed from full angle | Native full aperture enters shared state on `ZOOM | TOPOLOGY`; half angle is derived once |
| Radius, length and lens | Prism and cone providers each clamped params and called geometry calculator | Reference prism consumes resolved state; compatibility cone remains a separate renderer |
| Gobo roll | Native registry applied indexed phase to prism; projector rolled parent and compensated prism incrementally | One retained native phase in shared state; absolute child-coordinate conversion |
| Alignment and parity | Beam optics defaults, prism defaults and renderer-local Euler alignment | State owns explicit defaults; prism and projector perform named coordinate conversions |
| Artwork scale | Shaft radius multiplied independently; projector aperture did not track it | Shared cone tangent scales once for both consumers; finite near aperture scales correspondingly |
| Camera | Renderer retained camera for view-dependent presentation; no authoritative camera input found | State has no camera reference/input; camera motion cannot dirty it |

`BeamOpticsController` still builds the reused renderer parameter contract at setup
and explicit settings boundaries. `NativeRendererTargetRegistry` still maps stable
physical IDs and forwards native gobo motion. Neither becomes a semantic authority.
Compatibility/experimental cone and shader renderers retain their own rendering
conversions; this change targets Vector Gobo Prism, the reference renderer.

## Renderer conversions

Source artwork is X/right, Y/down along the emitted axis. Raw prism topology is
longitudinal on Y, so a fixed X quarter-turn maps it into the emitter frame. Explicit
X/Z mirrors and alignment are resolved with native gobo phase in that basis.
Godot spot-projector U follows light-local +X; its atlas flips V so image Y/down
follows light-local -Y. The prism applies an explicit raw-mesh X reflection after
the resolved roll/parity basis, recovering this artwork mapping without changing
the footprint. `projector_roll` and `projector_basis` still resolve shared roll
and visual mirrors. This fixed renderer conversion does not change centerline Z.
Applying the reflection before roll would invert the rotation convention.
The shaft basis is converted into the light's rolled child coordinates by an
absolute matrix inverse. It never subtracts a remembered compensation angle and
never incrementally rotates the already-modified child. Zoom reconstructs the same
resolved basis, so the previous compensation cannot be lost or applied twice.

The canonical presentation full aperture is limited once to Godot's supported
178-degree full cone and converted to its half-angle property. Visual artwork scale
multiplies the tangent of that half aperture once. The shaft keeps the existing
finite-lens near radius and resource-guarded far radius calculation. A Godot
SpotLight is a point projector: its cone has no finite near aperture. Thus finite
lens radius remains a shaft extrusion responsibility, not a second Zoom authority.
The existing 250 m resource guard limits the shared aperture for extreme cones,
so the projector and shaft cannot disagree when that guard is reached.
Spot range is still independent light coverage policy; visual length is shaft range.

## Dirty and lifecycle contract

Typed effective-value comparisons advance one projection revision when optical
inputs change. Geometry revision excludes motion-only roll. Both consumers record
the last revision they consumed. Color/dimmer changes never resolve optics. Repeated
optical values retain revision and cached topology identity. Zoom during blackout
updates hidden geometry so reactivation can use the lightweight intensity path.
No-beams keeps native held state and defers renderer mutation; returning full replays
the latest aperture and native gobo phase without needing fresh DMX. Consumer
revisions can intentionally lag held state while suppressed; both catch up in full.

Regression tests compare actual bases, common near origin, angle conversion,
revision identity, asymmetric source-artwork UV correspondence (both axes),
topology reuse, 600 motion/Zoom/camera updates, blackout and packed
dense held-state replay. The [custom surface regression](surface-light-ownership.md) now exercises real
Forward+ floor/wall/inclined projection. RTX 3070 GPU performance still requires
the reference machine; software/headless timings are not comparable.

The reference renderer also consumes a [shared radial light profile](vector-light-profile.md).
The presentation aperture includes its low-energy shoulder while `source_full_angle_deg`
retains native Zoom. Both consumers still use the same resolved aperture and bases.
The profile is a reusable presentation value, not an additional optical state owner.

The custom volume reads `pattern_texture` from this state and uses the resolved
anchor transform directly, including its parity and roll. It never derives artwork
from shaft polygons. Surface range is a separate bounded presentation setting;
Color/Dimmer arrive directly from native physical presentation, not this geometry
adapter or shaft intensity.

Surface-only falloff refinements leave native photometry and shaft profiles intact:
reliable Beam/Field anchors remain primary, while unanchored Wash/Spot use different
terminal feathers. Original gobo pixels are never blurred. Source selection advances
geometry revision (needed for held gobo-to-open replay); roll alone never does.
