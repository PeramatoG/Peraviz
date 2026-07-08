# GDTF support matrix

The support matrix is registry-driven. The official predefined attribute registry is `mvrdevelopment/spec/gdtf_attributes_with_description.json`; Peraviz must use it as a reference for known semantics while treating each GDTF file's `AttributeDefinitions` as authoritative.

Status values:

- `full`: parsed, validated, compiled, resolved natively, and rendered.
- `partial`: parsed and resolved for current renderer behavior, with documented limits.
- `parsed-only`: preserved in semantic data and diagnostics, not yet resolved live.
- `non-visual`: meaningful to fixture control or diagnostics but not rendered.
- `unsupported`: known official behavior cannot yet be reproduced.
- `planned`: schema/component slot exists but implementation is future work.

| Official family / examples | Section | Status | Notes |
| --- | --- | --- | --- |
| Dimmer | EmitterIntensity | partial | Current native runtime preserves dimmer visual behavior. |
| Pan, Tilt, XYZ, Rotation, Scale | GeometryTransform | partial | Pan/Tilt are current behavior; broader transforms are planned. |
| Cyan, Magenta, Yellow, RGB/ColorAdditive, filters | EmitterColor | partial | CMY is current behavior; spectral/filter/color-space mapping remains planned. |
| Zoom, Focus, Iris, Frost | BeamOptics | partial | Zoom is current behavior; other optics are planned. |
| Gobo(n), AnimationWheel(n), Color(n), Prism(n) | WheelSelection / WheelMotion | partial | Repeated wheel families are represented with component IDs; full slot-resource rendering is incremental. |
| Shaper/blade families | Shaper | planned | Parsed/diagnosed before renderer support. |
| Shutter, Strobe, Pulse, Ramp | TemporalOutput | partial | Current strobe behavior is preserved; waveform details are planned. |
| MediaServer*, VideoEffect(n)Parameter(m), Display | MediaDisplay | parsed-only | Proprietary visual output must not be invented. |
| Laser families | Laser | parsed-only | Requires explicit renderer support. |
| Fog, Haze, Fan, Blower | EnvironmentOutput | parsed-only | Environment-affecting output is future work. |
| Control, Reset, Lamp, Mode, Macro | DiagnosticNonVisual | non-visual | Exposed to diagnostics, not rendered live. |
| Manufacturer-specific or unknown attributes | GenericVisualParameter / diagnostics | parsed-only | Preserved and reported; no substring guessing. |

New GDTF capability work must update this matrix, the native registry source or fixture vectors, and regression tests.


## Attribute registry provenance
The pinned local registry used by the checkpoint tests lives at `native/src/gdtf_runtime/registry/official_attributes.json`. It records source provenance and an update procedure so Peraviz and Perastage can compare deterministic normalized attribute output without runtime internet access.

## Runtime architecture status

- Supported in active runtime: component-oriented dirty domains for dimmer, pan, tilt, zoom, CMY color, strobe, gobo selection/motion, and prism selection/motion.
- Partially integrated: parser-owned compiled fixture types and semantic contract fixtures exist, but scene setup still needs to source runtime programs directly from parsed GDTF XML for full GDTF-first operation.
- Unsupported or diagnostic-only: full ModeMaster evaluation, Relations, DMXProfiles, ColorSpaces, Gamuts, emitters/filters beyond current visual needs, and complete wheel-slot resource selection.
