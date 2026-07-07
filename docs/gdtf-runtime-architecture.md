# GDTF runtime architecture

Peraviz is moving to a GDTF-first native runtime. The source of truth is the official GDTF model: `AttributeDefinitions`, geometry trees and references, DMX modes, logical channels, channel functions, channel sets, wheels, emitters, filters, color spaces, gamuts, profiles, ModeMaster gates, Relations, defaults, and unknown/custom extension data.

## Reviewed sources

This architecture was checked against the public `mvrdevelopment/spec` repository, the current `gdtf-spec.md`, the official predefined attribute registry `gdtf_attributes_with_description.json`, Godot `PackedFloat32Array`, and Godot server-optimization guidance. Godot packed arrays remain appropriate for hot transport, but protocol metadata and IDs are integer data and must use integer packed storage rather than being encoded as floats.

## Flow

```text
GDTF/MVR input
  -> project-owned XML/archive parser
  -> serialization-neutral semantic GDTF model
  -> immutable CompiledGdtfFixtureType per fixture type + DMX mode
  -> native DMX/channel-function/physical resolver
  -> dirty semantic render sections
  -> versioned packed section protocol
  -> minimal Godot RenderingServer/node appliers
```

## Native compiled model

`native/src/gdtf_runtime/compiled_gdtf_fixture.h` introduces the first compiled-runtime tables: normalized attribute identities, geometry instances, component bindings, channel programs, and diagnostics. It is deliberately serialization-neutral so Perastage can share test vectors and semantics while keeping editor commands, undo/redo, and archive writing outside Peraviz.

The compiled model uses IDs and collections for repeated families. Gobo wheels, animation wheels, color wheels, prisms, emitters, shapers, media layers, and numbered attributes must never be collapsed into one fixed member per fixture.

## Sectioned live protocol

`native/src/runtime/visual_frame_schema.h` defines protocol version, schema generation, section descriptors, row strides, and validation. A frame with the wrong protocol version or schema generation is invalid. Section offsets and fixed strides are validated before an applier consumes packed rows.

Sections are transport domains, not replacements for GDTF FeatureGroups:

- `GeometryTransform`
- `EmitterIntensity`
- `EmitterColor`
- `BeamOptics`
- `WheelSelection`
- `WheelMotion`
- `Shaper`
- `TemporalOutput`
- `MediaDisplay`
- `Laser`
- `EnvironmentOutput`
- `GenericVisualParameter`
- `DiagnosticNonVisual`

## Threading and performance

Parsing, validation, fixture compilation, DMX resolution, physical-value mapping, relation handling, ModeMaster evaluation, dirty-state generation, and packed-frame assembly are native responsibilities. Godot installs schemas after structural rebuilds and during live playback only iterates present sections using cached component IDs and rendering targets.

## Diagnostics

Most diagnostics are generated during import and schema compilation. The native model records invalid references, missing required sections, bad ranges, unknown/custom attributes, unsupported official attributes, non-visual attributes, and approximated capabilities without adding frame-time overhead.


## Checkpoint 2 sectioned runtime activation
The active vertical slice now emits typed section descriptors plus integer and float payload buffers from the native runtime. Implemented layouts are named in `native/src/runtime/visual_frame_schema.h` for GeometryTransform, EmitterIntensity, EmitterColor, BeamOptics, WheelSelection, WheelMotion, and TemporalOutput. The current implementation remains a focused compatibility slice for the existing visual controls while real GDTF semantic coverage continues to expand.

## Component-engine migration checkpoint

Active native DMX evaluation now uses compiled semantic programs and per-fixture component state. The state cache has named semantic members for transform, emitter, optics, wheel, prism, and temporal domains, and dirty rows are written directly to the section protocol. This replaces the previous fixed control-array cache and fixed render-ready array. Fixture IDs are retained only as scene fixture identifiers; generated component and render-target IDs use distinct numeric spaces in emitted rows.

The parser-owned `CompiledGdtfFixtureType` remains the contract target for the next integration step: scene compilation should populate the runtime program table from parsed GDTF ChannelFunctions, ChannelSets, wheels, emitters, filters, relations, and mode-master records without any live XML or string lookups.
