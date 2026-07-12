# GDTF support matrix

Status values:

- `full`: parsed, compiled, resolved natively, rendered, and covered by end-to-end tests.
- `partial`: parsed and resolved for the documented subset, with known limits.
- `parsed-only`: preserved in semantic data or diagnostics, not resolved live.
- `non-visual`: meaningful to fixture control or diagnostics but not rendered.
- `unsupported`: known official behavior cannot yet be reproduced.
- `planned`: schema/component slot exists but implementation is future work.

| Official family / examples | Section | Status | Notes |
| --- | --- | --- | --- |
| Dimmer | EmitterIntensity | native-complete for verified DPT slice | Selected-mode ChannelFunctions preserve raw/full-resolution DMX and physical ranges; native evaluation emits normalized 0–1 Dimmer rows per changed render target, and Godot applies them to cached Lightweight Prism/lens resources. Multi-emitter ownership is deterministic with overlap diagnostics for ambiguous targets. |
| Pan, Tilt | GeometryTransform | partial | Native runtime-scene compiler installs eligible selected-mode ChannelFunction records with preserved DMX/physical ranges and component IDs, then emits physical degrees in the transform section. |
| XYZ, Rotation, Scale | GeometryTransform | planned | Not part of the verified production slice. |
| Cyan, Magenta, Yellow, RGB/ColorAdditive, filters | EmitterColor | planned | Must be reconnected through native compiled runtime programs before production support is claimed. |
| Zoom, Focus, Iris, Frost | BeamOptics | planned | Must be reconnected through native compiled runtime programs before production support is claimed. |
| Gobo(n), AnimationWheel(n), Color(n), Prism(n) | WheelSelection / WheelMotion | planned | Renderer appliers remain, but runtime compiler support is not claimed for this slice. |
| Shaper/blade families | Shaper | planned | Parsed/diagnosed before renderer support. |
| Shutter, Strobe, Pulse, Ramp | TemporalOutput | planned | Must be reconnected through native compiled runtime programs before production support is claimed. |
| MediaServer*, VideoEffect(n)Parameter(m), Display | MediaDisplay | parsed-only | Proprietary visual output must not be invented. |
| Laser families | Laser | parsed-only | Requires explicit renderer support. |
| Fog, Haze, Fan, Blower | EnvironmentOutput | parsed-only | Environment-affecting output is future work. |
| Control, Reset, Lamp, Mode, Macro | DiagnosticNonVisual | non-visual | Exposed to diagnostics, not rendered live. |
| Manufacturer-specific or unknown attributes | GenericVisualParameter / diagnostics | parsed-only | Preserved and reported; no substring guessing. |

## Runtime architecture status

- Active native compiled runtime slice: Dimmer, Pan, Tilt, and Zoom from parser-owned fixture patches, selected GDTF DMXModes, scoped DMXChannel traversal, and real ChannelFunction records into `CompiledRuntimeScene` and sectioned visual output.
- Supported source widths for the slice: 8-bit, 16-bit, 24-bit, and 32-bit ordered source bytes, including non-adjacent byte addresses.
- Transform-section unit: physical degrees prepared by native C++; Godot applies the values directly without a second semantic range conversion. Transform rows carry separate Pan and Tilt component IDs, Intensity rows carry a Dimmer render-target ID, and setup resolves those IDs through `NativeRendererTargetRegistry` by full imported-node canonical GDTF geometry-instance keys; missing targets are categorized diagnostics, not successful fallback application.
- Lightweight Prism BeamOptics now applies setup-time Beam profiles and corrects the lens-side/far-end radius mapping so normal Spot beams use a small near aperture and expand toward the far end. Active gobo-shaped prism masking, footprint alignment, and advanced volumetric quality remain deferred.
- Unsupported or diagnostic-only: full ChannelSet selection, ModeMaster evaluation, Relations, DMXProfiles, ColorSpaces, Gamuts, emitters/filters beyond current visual needs, and complete wheel-slot resource selection. Multiple ChannelFunctions on one Dimmer/Pan/Tilt logical property are selected by raw DMX range.

## Native BeamOptics foundation

Peraviz now installs a setup-time native Beam optical profile for each resolved Beam geometry/render target. The profile preserves official Beam geometry fields used by the renderer: BeamType, BeamAngle, FieldAngle, BeamRadius, ThrowRatio, RectangleRatio, LuminousFlux, ColorTemperature, and provenance for angle/radius fallbacks. Zoom remains a native selected-mode ChannelFunction property and emits target-oriented BeamOptics rows with the physical full angle and normalized range position.

The renderer keeps official optical radius separate from measured model aperture and selected visual near radius. Explicit BeamRadius is the preferred GDTF source for the render near radius; the Lightweight Prism path also records measured aperture radius, selected render near radius, selection source, and mismatch ratio so unit/scale mismatches are diagnosable without changing imported 3D model sizes.

Lightweight Prism now exposes a real BeamOptics renderer API. Setup applies static Beam profiles even for fixtures without Zoom, and live Zoom updates mutate per-instance near/far beam parameters on the existing custom prism resource. Spot, Wash, PC, and Fresnel use circular aperture topology; Rectangle uses a rectangular topology with RectangleRatio; None and Glow hide the projected custom beam. Gobo vectorization remains separate from physical aperture topology and is not activated by this work.

Remaining limitations: advanced photometry, Focus, Iris, Frost, prisms, shutters, active gobo selection/rotation, and high-quality volumetric rectangular rendering remain unsupported.


See [Beam geometry and visual length](BEAM_GEOMETRY_AND_VISUAL_LENGTH.md) for the renderer aperture, full-angle, and Peraviz-specific visual-length contract.

## Beam appearance baseline

Peraviz uses official GDTF `BeamType` values to select conservative renderer defaults: Spot and Rectangle are hard-edged, Wash/PC/Fresnel are soft-edged, and None/Glow do not draw projected visible beams. FieldAngle may influence only the visual envelope for soft BeamTypes when it is valid and larger than BeamAngle; it does not change geometry.

BeamType provenance is preserved for native Beam profiles. Missing BeamType uses the official GDTF default `Wash`; explicit supported values are preserved; unknown non-empty values are diagnosed separately and use a conservative Peraviz fallback.


### Projected Beam photometric weighting

Peraviz computes projected Beam target luminous-flux totals and target fractions during native scene compilation. Runtime Dimmer updates keep the existing owner-level EmitterIntensity row and the cached Dimmer target record applies the immutable per-emitter fractions to its already prepared Beam and light resources, so multi-emitter fixtures distribute declared Beam energy across projected targets instead of applying full fixture energy to every Beam geometry. BeamType `None` and `Glow` are excluded from projected-beam totals, and missing Beam photometry falls back to deterministic equal weighting.
