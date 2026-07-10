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

- Active native compiled runtime slice: Dimmer, Pan, and Tilt from parser-owned fixture patches, selected GDTF DMXModes, scoped DMXChannel traversal, and real ChannelFunction records into `CompiledRuntimeScene` and sectioned visual output.
- Supported source widths for the slice: 8-bit, 16-bit, 24-bit, and 32-bit ordered source bytes, including non-adjacent byte addresses.
- Transform-section unit: physical degrees prepared by native C++; Godot applies the values directly without a second semantic range conversion. Transform rows carry separate Pan and Tilt component IDs, Intensity rows carry a Dimmer render-target ID, and setup resolves those IDs through `NativeRendererTargetRegistry` by full imported-node canonical GDTF geometry-instance keys; missing targets are categorized diagnostics, not successful fallback application.
- Known renderer limitation: verified Dimmer output currently preserves the visible Lightweight Prism checkpoint, but the tested beam shape can appear cylindrical. Optically correct cone topology, GDTF beam-angle/range topology propagation, gobo-shaped prism geometry, footprint alignment, and advanced volumetric quality are deferred.
- Unsupported or diagnostic-only: full ChannelSet selection, ModeMaster evaluation, Relations, DMXProfiles, ColorSpaces, Gamuts, emitters/filters beyond current visual needs, and complete wheel-slot resource selection. Multiple ChannelFunctions on one Dimmer/Pan/Tilt logical property are selected by raw DMX range.
## Native BeamOptics foundation

Peraviz now starts the first native BeamOptics vertical. The selected-mode native compiler recognizes the canonical GDTF `Zoom` attribute alongside Dimmer, Pan, and Tilt and preserves ChannelFunction DMX ranges, ordered source bytes, and physical angle ranges in the compiled runtime. Live Zoom changes emit target-oriented `BeamOptics` rows with fixture ID, render target ID, changed mask, physical beam angle, half angle, and the current Zoom value so Godot can apply cached renderer resources by integer target ID.

Static Beam geometry fields remain setup-time optical profile inputs: `BeamType`, `BeamAngle`, `FieldAngle`, `BeamRadius`, `ThrowRatio`, `RectangleRatio`, `LuminousFlux`, `ColorTemperature`, and preserved emitter spectrum metadata. Official Beam geometry data has priority over Zoom, setup-time Peraviz aperture inference, documented fallback profiles, and the final safe circular fallback. Spot is treated as a hard-edged circular cone/frustum; Wash, PC, and Fresnel are circular cone/frustum baselines with softened field intent; Rectangle is reserved for rectangular pyramid/frustum output using `RectangleRatio`; None and Glow do not request a projected prism.

The live path is intentionally parametric: Dimmer rows mutate intensity/material state, while Zoom rows mutate the cached optics target and do not mark beam topology dirty. Setup-time target registration resolves optics targets and emitter anchors through canonical geometry keys; live application uses only numeric target IDs and cached records.
