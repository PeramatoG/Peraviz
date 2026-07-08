# DMX visual runtime

## Purpose

This document defines the C++ to Godot runtime transport contract for live visualization.

It covers:

- Structural schema installation.
- Stable IDs.
- Live typed deltas.
- Packed integer and float payloads.
- Section descriptors.
- Validation.
- Dirty-state behavior.
- Error handling.
- Threading and ownership.
- Migration constraints.
- Completion criteria.

This document does not define GDTF parsing semantics. Those belong in `docs/gdtf-runtime-architecture.md`.

This document does not describe temporary compatibility checkpoints as final architecture.

## Architectural objective

The runtime boundary is:

- Versioned.
- Schema-driven.
- Typed.
- Packed.
- Batched.
- Sparse.
- Dirty-state based.
- Free of per-fixture Dictionaries in the live path.
- Free of magic channel-type numbers in the final production path.
- Independent from raw GDTF and raw DMX semantics on the Godot side.

The boundary is divided into two distinct contracts:

1. Structural installation.
2. Live render deltas.

These contracts must not be merged into one universal fixture-state format.

## Ownership summary

### Native C++ owns

- DMX frame intake.
- Universe filtering.
- Relevant-address filtering.
- Compiled DMX program execution.
- ChannelFunction selection.
- ChannelSet selection.
- ModeMaster evaluation.
- Relation evaluation.
- Physical-state calculation.
- Interpolation and smoothing.
- Render-state cooking.
- Dirty-state generation.
- Section selection.
- Packed payload assembly.
- Protocol and schema generation.
- Runtime diagnostics.

### Godot owns

- Structural renderer registration.
- Cached component and render-target lookup.
- Node, RID, material, texture, shader, and renderer resource ownership.
- Validation of incoming protocol and schema metadata.
- Iteration of present sections.
- Domain-specific application of prepared values.
- Renderer-specific approximations after native semantic resolution.

### Godot does not own

- DMX byte decoding.
- Coarse, fine, or ultra-fine channel reconstruction.
- GDTF semantic interpretation.
- ChannelFunction or ChannelSet selection.
- ModeMaster or relation evaluation.
- Physical-range mapping.
- Attribute-name lookup.
- Wheel-slot selection from raw normalized DMX.
- Authoritative live fixture state.

## Contract separation

## Structural installation contract

Structural installation occurs after:

- MVR load.
- GDTF load.
- Fixture-type compilation.
- Selected DMX mode change.
- Patch change.
- Geometry topology change.
- Component topology change.
- Resource topology change.
- Render-target registration change.
- Protocol version change.
- Schema generation change.

The structural contract may contain:

- Protocol version.
- Schema generation.
- Fixture-type IDs.
- Fixture-instance IDs.
- Selected mode IDs.
- Geometry IDs.
- Component IDs.
- Emitter IDs.
- Wheel IDs.
- Wheel-slot IDs.
- Prism IDs.
- Shaper IDs.
- Resource IDs.
- Render-target IDs.
- Static transforms.
- Component-to-geometry mappings.
- Component-to-render-target mappings.
- Resource-to-target mappings.
- Static renderer capability metadata.
- Section schemas.
- Row strides.
- Section flags.
- Diagnostic references.

Godot installs this data and builds the renderer registry.

Structural data must not be resent every frame.

## Live delta contract

Live deltas contain only prepared changes since the previous accepted state.

A live delta may contain:

- Geometry transforms.
- Emitter intensity.
- Visibility.
- Light energy.
- Beam intensity.
- Material emission energy.
- Linear color.
- Beam angles.
- Edge softness.
- Zoom.
- Iris.
- Frost.
- Focus.
- Wheel selection.
- Wheel-slot selection.
- Resource selection.
- Wheel index angle.
- Wheel angular velocity.
- Wheel rotation direction.
- Shake frequency.
- Shake amplitude.
- Prism selection.
- Prism movement.
- Shaper values.
- Shutter state.
- Strobe mode.
- Strobe frequency.
- Duty cycle.
- Phase.
- Media parameters.
- Laser parameters.
- Environment output.
- Generic prepared visual values.

A live delta must not require Godot to:

- Decode DMX.
- Select ChannelFunctions.
- Select ChannelSets.
- Interpret GDTF attributes.
- Resolve physical ranges.
- Evaluate ModeMaster.
- Evaluate relations.
- Rebuild the structural registry.
- Search the scene tree.

## Protocol identity

Every structural snapshot and live delta must carry:

- Protocol major version.
- Protocol minor version.
- Schema generation.

The protocol major version changes when compatibility is intentionally broken.

The protocol minor version changes when compatible fields or sections are added.

The schema generation changes whenever structural meaning changes.

Examples of schema-generation changes:

- Fixture added or removed.
- Fixture type changed.
- DMX mode changed.
- Patch changed.
- Geometry structure changed.
- Component structure changed.
- Render-target mapping changed.
- Resource topology changed.
- Section schema changed.

Godot must reject live deltas whose protocol major version or schema generation does not match the installed structural registry.

## Stable identifiers

The transport uses stable integer IDs for:

- Fixture instances.
- Fixture types.
- Selected DMX modes.
- Geometry instances.
- Components.
- Emitters.
- Wheels.
- Wheel slots.
- Prisms.
- Shapers.
- Resources.
- Render targets.
- Sections.
- Schemas.

IDs are assigned during parsing, compilation, scene construction, or structural registration.

Do not derive component IDs or render-target IDs from arbitrary fixture-ID multiplication.

IDs must remain stable for the lifetime of an installed schema generation.

## Packed transport

The live runtime uses packed integer and float storage.

### Integer payloads

Use packed integer storage for:

- Protocol versions.
- Schema generation.
- Section descriptors.
- Section type IDs.
- Fixture IDs.
- Component IDs.
- Geometry IDs.
- Emitter IDs.
- Wheel IDs.
- Wheel-slot IDs.
- Prism IDs.
- Resource IDs.
- Render-target IDs.
- Row counts.
- Row strides.
- Offsets.
- Masks.
- Flags.
- Modes.
- Indexes.
- Booleans represented as flags.

### Float payloads

Use packed float storage for:

- Angles.
- Positions.
- Scales.
- Energies.
- Intensities.
- Linear colors.
- Beam angles.
- Edge softness.
- Zoom.
- Iris.
- Frost.
- Focus.
- Rotation values.
- Angular velocity.
- Frequencies.
- Amplitudes.
- Duty cycle.
- Phase.
- Shader parameters.

Do not encode integer identities, indexes, masks, flags, or counts as floats.

## Structural schema

The installed schema defines:

- Protocol version.
- Schema generation.
- Supported section types.
- Integer row stride for each section.
- Float row stride for each section.
- Required IDs.
- Optional flags.
- Validation rules.
- Renderer application ownership.
- Whether a section represents structural, resource-selection, or parametric change.

The schema must be immutable during one generation.

A new generation must be installed before live deltas using that generation are accepted.

## Live frame envelope

A live frame should contain one coherent transport envelope.

Recommended fields:

```text
protocol_major
protocol_minor
schema_generation
frame_index
timestamp
descriptors
integer_payload
float_payload
```

Optional fields may include:

```text
diagnostic_flags
source_sequence
dropped_frame_count
coalesced_frame_count
```

The live frame must not contain one Dictionary per fixture.

The live frame must not contain one object call per fixture.

The live frame must not require section slicing that creates new arrays per row.

## Section descriptors

Each section descriptor identifies one contiguous range in the packed payloads.

A descriptor should contain at least:

```text
section_type
row_count
integer_offset
float_offset
flags
```

Additional descriptor fields may be added through a compatible protocol revision.

Validation must confirm:

- Known section type.
- Non-negative row count.
- Valid integer offset.
- Valid float offset.
- Integer range inside payload bounds.
- Float range inside payload bounds.
- Expected integer stride.
- Expected float stride.
- Compatible flags.

No section applier may read payload data before validation succeeds.

## Section domains

The live protocol may define these transport domains:

- `GeometryTransform`
- `EmitterIntensity`
- `EmitterColor`
- `BeamOptics`
- `WheelSelection`
- `WheelMotion`
- `Prism`
- `Shaper`
- `TemporalOutput`
- `MediaDisplay`
- `Laser`
- `EnvironmentOutput`
- `GenericVisualParameter`
- `DiagnosticNonVisual`

These are transport domains.

They are not replacements for GDTF FeatureGroups, Features, Attributes, or semantic component identities.

## Domain isolation

Each section must update only its own domain.

Examples:

- `GeometryTransform` must not reset intensity.
- `EmitterIntensity` must not reset color.
- `EmitterColor` must not reset beam energy.
- `BeamOptics` must not reset transform.
- `WheelSelection` must not reset wheel motion.
- `WheelMotion` must not select a different wheel slot.
- `TemporalOutput` must not reset intensity or color.
- `Prism` must not reset gobo state.

Missing fields must not be interpreted as zero values for unrelated domains.

Partial rows must not be expanded into universal fixture state.

## Suggested section layouts

The exact field order must be versioned in the schema.

The following layouts describe ownership, not mandatory binary order.

### GeometryTransform

Integer identity fields may include:

- Fixture ID.
- Component ID.
- Render-target ID.
- Changed-property mask.

Float fields may include:

- Position.
- Rotation.
- Scale.
- Axis angle.
- Quaternion or transform representation.

### EmitterIntensity

Integer identity fields may include:

- Fixture ID.
- Component ID.
- Emitter ID.
- Render-target ID.
- Visibility flags.

Float fields may include:

- Light energy.
- Beam intensity.
- Material emission energy.
- Dimmer output.

### EmitterColor

Integer identity fields may include:

- Fixture ID.
- Component ID.
- Emitter ID.
- Render-target ID.

Float fields may include:

- Linear red.
- Linear green.
- Linear blue.
- Optional white or auxiliary channels after semantic resolution.
- Optional temperature or tint renderer values.

### BeamOptics

Integer identity fields may include:

- Fixture ID.
- Component ID.
- Render-target ID.
- Optics flags.

Float fields may include:

- Inner angle.
- Outer angle.
- Edge softness.
- Zoom.
- Iris.
- Frost.
- Focus.

### WheelSelection

Integer identity fields may include:

- Fixture ID.
- Component ID.
- Wheel ID.
- Wheel-slot ID.
- Resource ID.
- Render-target ID.
- Selection mode.

Float fields may include:

- Slot blend.
- Transition value.
- Optional prepared resource parameters.

### WheelMotion

Integer identity fields may include:

- Fixture ID.
- Component ID.
- Wheel ID.
- Render-target ID.
- Motion mode.
- Direction.

Float fields may include:

- Index angle.
- Angular velocity.
- Shake frequency.
- Shake amplitude.
- Shake phase.
- Offset.

### Prism

Integer identity fields may include:

- Fixture ID.
- Component ID.
- Prism ID.
- Render-target ID.
- Selection state.
- Motion mode.

Float fields may include:

- Index angle.
- Angular velocity.
- Blend or activation amount.

### Shaper

Integer identity fields may include:

- Fixture ID.
- Component ID.
- Shaper ID.
- Render-target ID.
- Blade or element index.

Float fields may include:

- Position.
- Angle.
- Rotation.
- Softness.

### TemporalOutput

Integer identity fields may include:

- Fixture ID.
- Component ID.
- Render-target ID.
- Shutter mode.
- Strobe mode.

Float fields may include:

- Frequency.
- Duty cycle.
- Phase.
- Pulse width.
- Randomization parameters.

## Resource topology and parametric updates

The protocol must distinguish resource changes from parametric changes.

Examples:

### Resource or topology change

- Selecting a different gobo slot.
- Selecting a different texture.
- Changing the number of active renderer targets.
- Changing geometry.
- Changing component mapping.
- Changing selected DMX mode.

### Parametric live change

- Rotating the selected gobo.
- Changing gobo shake.
- Changing intensity.
- Changing color.
- Changing beam angle.
- Moving pan or tilt.
- Changing strobe frequency.

Resource changes may require renderer-resource installation or lookup.

Parametric updates should reuse existing resources.

## Gobo transport

The live boundary should carry prepared gobo identities and parameters.

Recommended gobo data includes:

- Wheel ID.
- Wheel-slot ID.
- Resource ID.
- Render-target ID.
- Index angle.
- Angular velocity.
- Direction.
- Shake frequency.
- Shake amplitude.
- Shake phase.
- Blend or transition value.

Godot must not receive raw ChannelFunction or ChannelSet data for live gobo resolution.

Godot must not regenerate the gobo image for rotation, index, or shake.

## Schema validation

Before accepting a structural schema, Godot must verify:

- Supported protocol major version.
- Supported protocol minor version.
- Valid schema generation.
- Unique section type IDs.
- Valid row strides.
- Valid component IDs.
- Valid render-target IDs.
- Valid component-to-target mappings.
- Valid resource references where required.

Before accepting a live frame, Godot must verify:

- Matching protocol major version.
- Compatible protocol minor version.
- Matching schema generation.
- Valid descriptor count.
- Valid descriptor strides.
- Valid payload ranges.
- Valid row counts.
- Valid IDs for the installed registry.
- Valid flags.

Invalid data must be rejected before renderer application.

## Error handling

When a live frame is rejected:

- Do not read invalid payload memory.
- Do not partially apply the rejected section.
- Keep the previous valid renderer state.
- Increment diagnostic counters.
- Report the reason outside the hot path.
- Avoid repeated log spam for the same error.

When one section is invalid:

- Reject the complete frame if partial application could create inconsistent state.
- Partial-frame acceptance is allowed only if the protocol explicitly defines independent transactional sections.

The default policy should favor coherent frame application.

## Dirty-state behavior

Native C++ determines which domains are dirty.

The runtime should suppress:

- Unchanged fixture state.
- Unchanged component state.
- Irrelevant universe changes.
- Irrelevant channel-byte changes.
- Duplicate identical frames.
- Redundant resource selections.
- Redundant material updates.
- Redundant texture assignments.

Dirty state may be tracked by:

- Fixture.
- Component.
- Render domain.
- Resource selection.
- Render target.
- Section row.

Dirty-state generation must not be delegated to Godot.

## Frame coalescing

Latest-wins coalescing may be used when intermediate states do not need to be rendered.

Coalescing is appropriate for:

- High-frequency DMX frames.
- Repeated universe snapshots.
- Renderer updates where only the newest complete state matters.

Coalescing must preserve:

- Correct final values.
- Correct schema generation.
- Required time-dependent state.
- Diagnostics for dropped or coalesced frames.

Temporal effects requiring phase continuity must use explicit time or phase data rather than depending on every network packet being rendered.

## Threading and handoff

Native receiving and processing threads may build structural snapshots and live delta frames.

They must not mutate:

- Godot Nodes.
- Godot Resources.
- Godot RIDs.
- Materials.
- Textures.
- RenderingServer objects.

Recommended handoff methods:

- Immutable snapshots.
- Double buffering.
- Lock-free queues.
- Short mutex-protected swaps.
- Preallocated packed buffers.
- Latest-wins frame exchange.

Do not hold a native lock while calling into Godot.

Godot applies accepted data from a thread context permitted by the renderer and scene API.

## Godot application model

Godot should:

1. Install the structural schema.
2. Build the render-target registry.
3. Cache target references.
4. Receive one coherent live frame.
5. Validate protocol and schema metadata.
6. Validate descriptors and payload bounds.
7. Iterate only present sections.
8. Dispatch each section to its domain applier.
9. Apply rows to cached targets.
10. Record diagnostics.
11. Release or recycle the frame buffer.

Godot should not:

- Build fixture bindings.
- Parse raw DMX.
- Resolve attribute names.
- Rebuild a universal fixture Dictionary.
- Search for targets every frame.
- Create duplicate materials or textures per update.
- Call one boundary function per fixture.

## Boundary API

Preferred final production API shapes include:

```text
install_runtime_schema(schema)
install_compiled_scene(structural_snapshot)
install_render_registry(render_registry)
submit_universe_frame(universe_id, packed_bytes)
consume_render_deltas()
get_runtime_diagnostics()
```

The exact class names may differ.

Avoid final production APIs shaped like:

```text
set_fixture_bindings(Array<Dictionary>)
set_fixture_render_params(fixture_id, Dictionary)
set_fixture_channel(fixture_id, channel_type, value)
set_pan(fixture_id, value)
set_tilt(fixture_id, value)
```

These APIs encourage legacy ownership and duplicate semantics.

## Diagnostics

Maintain counters for at least:

- Frames received.
- Frames coalesced.
- Frames dropped.
- Frames rejected.
- Universes received.
- Universes ignored.
- Relevant bytes evaluated.
- Fixtures evaluated.
- Components evaluated.
- Dirty rows emitted.
- Sections emitted.
- Structural installations.
- Schema mismatches.
- Invalid descriptors.
- Invalid IDs.
- Missing render targets.
- Delta assembly time.
- Transfer time.
- Godot validation time.
- Godot apply time.
- Resource update time.

Diagnostics may use Dictionaries or strings outside the hot path.

## Testing requirements

Tests must cover:

- Structural schema installation.
- Protocol major-version rejection.
- Compatible minor-version handling.
- Schema-generation rejection.
- Unknown section type rejection.
- Invalid descriptor count.
- Invalid integer offset.
- Invalid float offset.
- Invalid integer stride.
- Invalid float stride.
- Invalid row count.
- Invalid component ID.
- Invalid render-target ID.
- Empty frame behavior.
- Unchanged-frame suppression.
- Dirty-domain isolation.
- Latest-wins coalescing.
- Unused universe rejection.
- Irrelevant-byte filtering.
- Resource-selection changes.
- Parametric wheel motion.
- Color without intensity reset.
- Optics without transform reset.
- Temporal output without energy reset.
- Repeated component families.
- Structural and live contract separation.
- Legacy API absence after migration.

## Required vertical proof

The minimum end-to-end runtime proof is:

```text
Real GDTF test fixture
    -> project-owned parser
    -> compiled fixture type
    -> selected DMX mode
    -> structural component registry
    -> runtime schema installation
    -> compiled Dimmer, Pan, and Tilt programs
    -> DMX frame
    -> native resolved state
    -> typed live deltas
    -> Godot validation
    -> direct domain application
```

This proof must not use:

- Godot-created fixture binding Dictionaries.
- Magic channel-type numbers.
- Manual replacement of parser-owned programs.
- A universal fixture-state Dictionary.
- A legacy fallback runtime.

## Current implementation status

This section must remain conservative.

### Target

The target is the complete structural and live contract described in this document.

### Partially active

The repository contains parts of the target design, including:

- Versioned section-schema foundations.
- Packed integer and float payload concepts.
- Section descriptors.
- Domain-specific Godot section appliers.
- Native dirty-state and section assembly experiments.

These parts do not prove that the final production path is active.

### Migration-sensitive

The following patterns remain migration-sensitive until removed:

- `set_fixture_bindings(Array)`.
- `set_fixture_render_params(..., Dictionary)`.
- Godot-created fixture channel bindings.
- Magic channel-type integers.
- Universal fixture-state caches.
- Fixed compact-control arrays.
- Fixed render-ready arrays.
- Duplicate C++ and Godot fixture state.
- Legacy fallback appliers.
- Tests that only construct manual legacy bindings.
- Runtime schema derived from legacy bindings instead of compiled scene data.

### Not yet proven active

The following must not be described as fully active without end-to-end tests:

- Parser-owned compiled fixture types feeding the live runtime directly.
- Structural registry installation generated from compiled scene data.
- Real GDTF ChannelFunctions feeding compiled programs.
- Repeated wheel, emitter, or geometry families through the complete path.
- Complete separation of structural installation and live deltas.
- Full removal of legacy runtime APIs and registration.

## Migration rules

During an approved architectural replacement:

- Internal APIs may be broken.
- Legacy runtime paths should be removed from the active build.
- Git history is the legacy reference.
- Temporary bridges require an owner, expiration condition, and deletion guardrail.
- Temporary bridges must not receive new features.
- New types without a new production call graph do not complete the migration.
- Passing name-based guardrails is not enough.
- The active call graph must be reviewed.
- Tests must prove the intended production path.
- Secondary features may remain temporarily unsupported if the new vertical path is real and no longer routes through legacy code.

## Migration completion criteria

The DMX visual runtime migration is complete only when:

1. Structural installation and live deltas are separate.
2. The runtime schema is generated from compiled scene data.
3. Stable component and render-target IDs are installed in Godot.
4. The live runtime consumes compiled DMX programs directly.
5. Godot does not create authoritative fixture bindings.
6. Magic channel-type numbers are absent from the final path.
7. Live frames use typed packed integer and float payloads.
8. Godot validates protocol and schema metadata before application.
9. Domain appliers update only their own domains.
10. Repeated component families use IDs and collections.
11. Native C++ owns dirty-state generation.
12. Godot uses cached render targets.
13. Universal per-fixture live Dictionaries are removed.
14. Legacy runtime APIs are removed from registration and the build.
15. Legacy fallback paths are removed.
16. Tests exercise the real parser-to-renderer production path.
17. Guardrails inspect the real repository structure.
18. Dimmer, Pan, and Tilt pass the required vertical proof.
19. Documentation marks only proven behavior as active.
20. The runtime no longer depends on temporary legacy binding compatibility.

## Documentation update rules

Update this document when changing:

- Protocol versions.
- Schema-generation rules.
- Structural snapshot shape.
- Live frame envelope.
- Section descriptors.
- Section domains.
- Integer or float row layouts.
- Validation policy.
- Error-handling policy.
- Dirty-state rules.
- Coalescing behavior.
- Boundary API.
- Godot application ownership.
- Migration completion criteria.

Do not add temporary checkpoints to target sections.

Use `Current implementation status` for temporary migration notes.

## Final invariants

The following conditions must remain true:

1. Structural installation and live updates are separate contracts.
2. The boundary is versioned, schema-driven, typed, packed, batched, and sparse.
3. Integer identities remain integer data.
4. Godot does not decode DMX or reinterpret GDTF.
5. Native C++ owns dirty-state generation.
6. Godot applies prepared domain-specific values.
7. One section does not reset unrelated domains.
8. Renderer targets are cached during structural installation.
9. Live updates avoid per-fixture Dictionaries and per-fixture boundary calls.
10. Repeated families use stable IDs and collections.
11. Invalid frames are rejected before payload application.
12. Legacy internal compatibility does not override an approved architectural replacement.
13. Tests exercise the real production path.
14. Documentation distinguishes target architecture from current implementation status.
