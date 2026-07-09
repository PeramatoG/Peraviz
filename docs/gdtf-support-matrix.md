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
| Dimmer | EmitterIntensity | partial | Native runtime-scene compiler installs eligible selected-mode ChannelFunction records with preserved DMX/physical ranges and target IDs, then emits normalized intensity for render cooking. |
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
- Transform-section unit: physical degrees prepared by native C++; Godot applies the values directly without a second semantic range conversion. Transform rows carry separate Pan and Tilt component IDs, Intensity rows carry a Dimmer render-target ID, and setup resolves those IDs by full imported-node canonical GDTF geometry-instance keys built during native setup; missing targets are categorized diagnostics, not successful fallback application.
- Unsupported or diagnostic-only: full ChannelSet selection, ModeMaster evaluation, Relations, DMXProfiles, ColorSpaces, Gamuts, emitters/filters beyond current visual needs, and complete wheel-slot resource selection. Multiple ChannelFunctions on one Dimmer/Pan/Tilt logical property are selected by raw DMX range.
