# DMX visual runtime

The long-term live boundary is a versioned, schema-driven, sectioned protocol. The former single universal fixture row is deprecated because it cannot represent arbitrary GDTF attributes, repeated numbered families, or sparse dirty updates efficiently.

## Schema installation

A schema is installed after MVR load, selected DMX mode changes, fixture patch changes, geometry/component binding changes, or another structural rebuild. The schema contains protocol version, schema generation, stable section type IDs, row strides, and stable render/component IDs.

Godot must reject frames whose protocol version or schema generation does not match the active registry. Section offsets and strides are checked before buffer access.

## Packed buffers

- `PackedInt32Array`: protocol metadata, schema generation, section descriptors, IDs, counts, strides, masks, indexes.
- `PackedFloat32Array`: physical and render-ready numeric values.

The live loop must avoid per-fixture Dictionaries, strings, one call per fixture, section slicing, per-frame schema rebuilds, and duplicate protocols.


## Sectioned live frame protocol
Live DMX visualization no longer exposes one float-only fixture row to GDScript. `PeravizVisualRuntime.consume_latest_visual_frame()` returns one coherent snapshot dictionary containing protocol version, schema generation, `PackedInt32Array` descriptors, `PackedInt32Array` integer payload, and `PackedFloat32Array` float payload. Godot installs schema metadata at runtime setup and applies rows through `scripts/runtime/visual_sections/sectioned_visual_frame_applier.gd`.

## Corrective sectioned runtime checkpoint

The active native runtime now builds its live schema from the capabilities present in registered fixture bindings and advances the schema generation whenever bindings are rebuilt or the runtime is cleared. The active C++ sectioned path no longer includes the deprecated universal visual-frame row header; legacy row definitions remain isolated for historical compatibility code only.

Godot's sectioned visual-frame applier now routes GeometryTransform, EmitterIntensity, EmitterColor, BeamOptics, WheelSelection, WheelMotion, and TemporalOutput rows directly into specialized apply calls. It keeps per-fixture render state only as cached section state and no longer reconstructs a 25-float universal fixture row or calls the fixed-row apply entry point from the sectioned path.

## Component-oriented runtime checkpoint

The native visual runtime now stores live values in component-oriented semantic state instead of a fixed compact-control array. Incoming setup bindings are compiled into semantic channel programs, dirty state is grouped by render domain, and section rows are emitted directly into typed integer and float buffers for GeometryTransform, EmitterIntensity, EmitterColor, BeamOptics, WheelSelection, WheelMotion, and TemporalOutput. Godot section consumption no longer rebuilds a universal fixture-state dictionary in the section applier.

This checkpoint keeps the existing Godot setup bridge while removing the fixed native state model from the active C++ runtime. The remaining migration work is to feed these compiled programs directly from parser-owned `CompiledGdtfFixtureType` data instead of setup-time legacy binding dictionaries.

## Direct render-domain applier correction

The sectioned Godot applier no longer calls the universal lighting apply method for every non-transform row. EmitterIntensity owns visibility, light energy, beam intensity, and material emission energy; EmitterColor owns light/material/beam color; BeamOptics owns supported spot and beam angle updates; WheelSelection and WheelMotion update gobo topology or motion without changing intensity; TemporalOutput records shutter/strobe state without changing beam energy. This prevents an initial frame with multiple sections from turning the dimmer on and then immediately turning the beam off with partial zero-filled rows.
