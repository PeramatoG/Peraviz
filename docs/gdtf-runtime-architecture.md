# GDTF runtime architecture

## Purpose

This document defines the GDTF-specific target architecture for Peraviz.

It explains:

- GDTF source-of-truth ownership.
- Parsing and validation.
- Serialization-neutral semantic models.
- Compiled fixture types.
- Scene and component registration.
- Compiled DMX programs.
- Physical and render-state resolution.
- Structural installation.
- Live typed deltas.
- Godot renderer application.
- Diagnostics.
- Testing.
- Migration completion criteria.

This document must not describe a planned target as if it were already active.

Current implementation status, temporary bridges, known legacy paths, and unsupported features must be identified explicitly.

## Relationship with other documents

The following documents have complementary responsibilities:

- `AGENTS.md`
  - Defines repository-wide architecture and refactoring precedence.
  - Defines architectural replacement mode.
  - Overrides normal incremental-refactor preferences when explicitly activated.

- `docs/architecture.md`
  - Defines the stable top-level Peraviz architecture.
  - Defines the separation between native C++ and Godot.

- `docs/dmx-visual-runtime.md`
  - Defines the structural and live C++ to Godot transport contracts.

- `docs/gdtf-support-matrix.md`
  - Defines exact, partial, diagnostic-only, and unsupported GDTF capabilities.

- `docs/peraviz-perastage-gdtf-contract.md`
  - Defines the serialization-neutral semantic contract shared with Perastage.

- `peraviz_tree.md`
  - Maps these responsibilities to real repository paths.

When these documents disagree, fix the inconsistency before extending the affected runtime path.

## Architectural objective

Peraviz uses GDTF as the semantic source of truth for fixture behavior.

The final production path is:

```text
MVR and GDTF input
    -> project-owned archive and XML access
    -> project-owned GDTF parser
    -> validation and diagnostics
    -> serialization-neutral semantic model
    -> immutable compiled fixture type
    -> selected DMX mode
    -> structural scene and component registry
    -> compiled DMX programs
    -> native physical-state resolution
    -> native render-state cooking
    -> native dirty-state generation
    -> versioned typed render deltas
    -> thin Godot domain appliers
    -> cached renderer targets
```

Godot must not reinterpret GDTF during live playback.

## GDTF source of truth

The runtime source of truth is the parsed and validated GDTF model.

Relevant source data includes:

- Fixture type metadata.
- Attribute definitions.
- Feature groups.
- Features.
- Activation groups.
- Main attributes.
- Subphysical units.
- Geometry trees.
- Geometry references.
- Models.
- DMX modes.
- DMX channels.
- Logical channels.
- Channel functions.
- Channel sets.
- Initial functions.
- DMX defaults.
- Physical ranges.
- ModeMaster gates.
- Relations.
- DMX profiles.
- Wheels.
- Wheel slots.
- Slot media resources.
- Animation systems.
- Prisms.
- Emitters.
- Filters.
- Color spaces.
- Gamuts.
- Shapers.
- Media servers and displays.
- Lasers.
- Connectors.
- Revisions.
- Unknown attributes.
- Unknown elements.
- Custom extensions.

The runtime must not replace GDTF semantics with:

- Magic channel-type numbers.
- A fixed list of visual controls.
- Name matching performed in Godot.
- One universal fixture row.
- One fixed member for every repeated family.
- A small manually maintained mapping that becomes more authoritative than the parsed file.

## Architecture status terminology

This document uses the following status labels:

- **Target**
  - Required final architecture.

- **Active**
  - Used by the current production path.

- **Partially active**
  - Used by production in a limited or transitional way.

- **Migration-sensitive**
  - Existing code that must not receive new ownership that belongs elsewhere.

- **Legacy**
  - Superseded code that must not be extended and should be removed from the active build during architectural replacement.

- **Unsupported**
  - Not implemented.

- **Diagnostic-only**
  - Parsed or preserved, but not yet applied visually.

No feature should be marked active unless an end-to-end test proves that the production path uses it.

## Ownership overview

### Native C++ owns

- GDTF archive access.
- GDTF XML parsing.
- Validation.
- Canonical attribute resolution.
- Semantic normalization.
- Geometry resolution.
- Compiled fixture types.
- Selected DMX modes.
- Component identity generation.
- Scene component registration data.
- DMX program compilation.
- DMX value decoding.
- ChannelFunction and ChannelSet evaluation.
- ModeMaster evaluation.
- Relation evaluation.
- Physical-value calculation.
- Interpolation and smoothing.
- Dirty-state generation.
- Render-ready value preparation.
- Typed section and delta assembly.
- Diagnostics.
- CPU-side resource preparation where practical.

### Godot owns

- Scene presentation.
- Renderer-specific resources.
- Nodes.
- RIDs.
- Materials.
- Meshes.
- Textures.
- Shaders.
- Beam renderers.
- Atmosphere.
- Post-processing.
- Installation of structural render targets.
- Application of prepared typed render deltas.
- Renderer-specific approximations after native semantic resolution.

### Godot does not own

- GDTF parsing.
- GDTF semantic interpretation.
- DMX channel decoding.
- ChannelFunction lookup.
- ChannelSet selection.
- ModeMaster rules.
- Relation rules.
- Physical-range mapping.
- Wheel-slot selection from raw DMX.
- Name-based attribute resolution in the live path.
- Authoritative fixture-state storage.

## Parsing architecture

The project-owned parser must produce a deterministic serialization-neutral semantic model.

### Parser responsibilities

The parser must:

- Read the GDTF archive and required XML content.
- Preserve source identities.
- Parse official sections.
- Parse supported custom extensions.
- Preserve unknown attributes and elements where practical.
- Resolve required references.
- Record invalid references.
- Record missing required sections.
- Preserve original names for diagnostics.
- Normalize canonical attribute identities.
- Preserve wildcard and numbered attribute information.
- Keep source provenance.
- Produce deterministic output.

### Parser restrictions

The parser must not:

- Depend on Godot Nodes or Resources.
- Create renderer state.
- Create live DMX fixture bindings for Godot.
- Discard unknown data silently.
- Guess unsupported semantics without diagnostics.
- Collapse repeated families into one fixed object.
- Mix Perastage editor commands into shared semantic types.

## Validation architecture

Validation runs after parsing and before compilation.

Validation must detect and report:

- Missing required sections.
- Missing fixture type identity.
- Invalid geometry references.
- Invalid model references.
- Invalid attribute references.
- Invalid wheel references.
- Invalid emitter or filter references.
- Invalid DMX ranges.
- Overlapping or contradictory channel ranges.
- Invalid ChannelSet ranges.
- Invalid ModeMaster references.
- Invalid relation references.
- Invalid resource paths.
- Invalid physical ranges.
- Unknown official attributes.
- Custom attributes.
- Unsupported feature families.
- Approximation requirements.

Validation results must be deterministic and must not add live-frame overhead.

## Serialization-neutral semantic model

The semantic model is the shared meaning layer between parsing and runtime compilation.

It must be independent from:

- Godot renderer types.
- Godot Nodes.
- Godot RIDs.
- Peraviz renderer caches.
- Perastage UI.
- Perastage editor commands.
- Undo and redo.
- Archive-writing state.
- Platform-specific rendering behavior.

The semantic model may be shared conceptually or through deterministic contract fixtures with Perastage.

Shared compatibility means:

- Same canonical attribute meaning.
- Same geometry interpretation.
- Same selected DMX mode meaning.
- Same channel-function ranges.
- Same ChannelSet ranges.
- Same physical ranges.
- Same wheel and slot identities.
- Same diagnostics for the same source data.

It does not require both projects to share the same editor, renderer, cache, or UI implementation.

## Compiled fixture type

The immutable compiled fixture type is the native runtime-ready representation of one fixture type and one selected DMX mode.

A compiled fixture type must contain or reference:

- Fixture-type identity.
- Selected mode identity.
- Geometry instance table.
- Geometry hierarchy.
- Geometry-reference expansion.
- Component table.
- Attribute identity table.
- Compiled channel programs.
- Physical mapping data.
- ModeMaster data.
- Relation data.
- Wheel table.
- Wheel-slot table.
- Emitter table.
- Filter table.
- Color-space and gamut data where supported.
- Prism data.
- Shaper data.
- Media data.
- Laser data.
- Resource references.
- Static render capability metadata.
- Diagnostics.
- Contract version.

The compiled fixture type must be reusable by multiple fixture instances of the same type and mode.

Fixture-instance patch data must remain separate from fixture-type compilation.

## Fixture instance model

A fixture instance references:

- Compiled fixture type.
- Selected DMX mode.
- Patch and universe information.
- Fixture-instance ID.
- Root scene transform.
- Instance-specific inversion or orientation settings.
- Instance-specific render-target mapping.
- Runtime component state.

Multiple instances must share immutable fixture-type data.

The runtime must not duplicate the full parsed or compiled fixture type for every fixture instance unless profiling proves that duplication is required.

## Component model

The runtime component model is variable and ID-based.

A component may represent:

- Geometry transform.
- Axis movement.
- Emitter intensity.
- Emitter color.
- Beam optics.
- Gobo wheel.
- Animation wheel.
- Color wheel.
- Prism.
- Shaper.
- Shutter.
- Strobe.
- Media display.
- Laser output.
- Environment output.
- Generic visual parameter.
- Diagnostic-only non-visual state.

Repeated families must use IDs and collections.

The architecture must not assume one fixture contains exactly:

- One pan axis.
- One tilt axis.
- One emitter.
- One beam.
- One color system.
- One gobo wheel.
- One prism.
- One shaper.
- One media layer.

## Stable IDs

Stable IDs must exist for:

- Fixture types.
- Fixture instances.
- DMX modes.
- Geometry instances.
- Components.
- Attributes.
- Emitters.
- Filters.
- Wheels.
- Wheel slots.
- Prisms.
- Shapers.
- Media layers.
- Resources.
- Render targets.
- Schemas.

IDs are assigned during parsing, compilation, scene construction, or structural registration.

Do not derive component IDs, wheel IDs, or render-target IDs from arbitrary multiplication of fixture IDs.

IDs must remain stable for the lifetime of an installed schema.

## Compiled DMX program model

The live runtime must consume compiled programs generated from parser-owned data.

A compiled DMX program may contain:

- Universe-relative or patch-relative address information.
- Coarse, fine, and ultra-fine byte layout.
- Bit depth.
- DMX range.
- Physical range.
- ChannelFunction identity.
- ChannelSet table.
- Attribute identity.
- Target component identity.
- Target property identity.
- ModeMaster gate.
- Relation dependencies.
- DMX profile.
- Interpolation behavior.
- Default and initial value behavior.
- Diagnostic fallback policy.

The final production path must not compile programs from Godot-created Dictionaries.

The final production path must not depend on magic integers such as:

```text
1 = Pan
2 = Tilt
3 = Dimmer
```

Temporary compatibility mappings must be explicitly marked legacy and must have deletion criteria.

## DMX resolution

For each relevant universe frame, native C++ must:

1. Ignore unregistered universes.
2. Ignore irrelevant byte changes.
3. Resolve fixture-instance patch addresses.
4. Decode coarse, fine, and ultra-fine values.
5. Select ChannelFunctions.
6. Select ChannelSets.
7. Evaluate ModeMaster gates.
8. Evaluate relations.
9. Apply DMX profiles.
10. Map DMX values to physical values.
11. Apply inversion and normalization rules.
12. Apply interpolation or smoothing.
13. Update component state.
14. Mark changed render domains dirty.
15. Produce prepared render values.
16. Emit typed deltas.

Godot must not repeat any of these steps.

## Physical-state calculation

The native runtime should resolve physical or semantically meaningful state before crossing the Godot boundary.

Examples:

- Pan and tilt angles.
- Dimmer and emitter output.
- Linear RGB color.
- Color temperature or tint where supported.
- Beam inner and outer angles.
- Edge softness.
- Zoom.
- Iris.
- Frost.
- Focus.
- Gobo wheel identity.
- Gobo slot identity.
- Gobo resource identity.
- Gobo index angle.
- Gobo angular velocity.
- Gobo direction.
- Gobo shake parameters.
- Prism identity.
- Prism movement.
- Shaper positions.
- Shutter mode.
- Strobe frequency.
- Strobe duty cycle.
- Strobe phase.
- Media parameters.
- Laser parameters.

Godot receives values suitable for direct renderer application.

## Render-state cooking

Physical values and renderer values are related but not always identical.

Native C++ may prepare renderer-facing values such as:

- Final light energy.
- Final beam intensity.
- Material emission energy.
- Visibility state.
- Linear renderer color.
- Inner cone angle.
- Outer cone angle.
- Beam edge softness.
- Renderer-safe focus range.
- Renderer-safe frost range.
- Resource ID.
- Shader rotation value.
- Shader shake frequency.
- Shader shake amplitude.

Renderer-specific approximations may occur in Godot after native semantic resolution, but Godot must not reconstruct GDTF meaning.

## Structural scene compilation

Structural compilation builds the immutable registry required by Godot.

It must define:

- Fixture-instance IDs.
- Geometry IDs.
- Component IDs.
- Emitter IDs.
- Wheel IDs.
- Wheel-slot IDs.
- Resource IDs.
- Render-target IDs.
- Static transforms.
- Geometry hierarchy.
- Component-to-geometry mapping.
- Component-to-render-target mapping.
- Resource-to-target mapping.
- Protocol version.
- Schema generation.

Structural data is installed after a scene or topology change.

It is not resent for every live frame.

## Structural installation in Godot

Godot receives the structural snapshot and:

- Creates or reuses scene Nodes.
- Creates or reuses renderer resources.
- Registers component and render-target mappings.
- Caches Node references.
- Caches RID references.
- Caches material references.
- Caches shader references.
- Caches texture references.
- Validates schema version and generation.
- Rejects stale or incompatible data.

After installation, live updates must use cached IDs and references.

## Live section protocol

Live data is transferred as versioned typed sections.

The exact transport contract belongs in `docs/dmx-visual-runtime.md`.

Possible section domains include:

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

These sections are transport domains.

They do not replace GDTF FeatureGroups or semantic identities.

## Section rules

Each section must define:

- Section type ID.
- Integer row stride.
- Float row stride.
- Required IDs.
- Optional flags.
- Validation rules.
- Dirty-state behavior.
- Schema-version behavior.

Sections must be independently applicable.

One section must not reset unrelated domains.

Examples:

- Color must not reset intensity.
- Wheel motion must not reset wheel selection.
- Beam optics must not reset transform.
- Temporal output must not reset beam energy.
- Transform must not rebuild the complete fixture state.

## Packed transport

Use integer packed storage for:

- Protocol versions.
- Schema generations.
- Section types.
- IDs.
- Indexes.
- Counts.
- Masks.
- Flags.
- Strides.
- Offsets.
- Modes.
- Resource references.

Use float packed storage for:

- Physical values.
- Angles.
- Energies.
- Intensities.
- Linear colors.
- Speeds.
- Frequencies.
- Amplitudes.
- Renderer parameters.

Do not encode IDs or indexes as floats.

## Dirty-state generation

Dirty-state generation belongs in native C++.

Dirty domains may include:

- Transform.
- Intensity.
- Color.
- Optics.
- Wheel selection.
- Wheel motion.
- Prism.
- Shaper.
- Temporal output.
- Material.
- Resource topology.
- Generic visual output.

The runtime must distinguish:

- Structural changes.
- Resource-selection changes.
- Parametric live changes.

Examples:

- Selecting a different gobo resource is a resource-selection change.
- Rotating the same gobo is a parametric live change.
- Creating a new renderer target is structural.
- Changing beam intensity is parametric.
- Changing selected DMX mode is structural.
- Changing one DMX value is live.

## Gobo architecture

Gobo handling is divided into semantic resolution, CPU-side resource preparation, and renderer application.

### Native semantic ownership

Native C++ owns:

- Wheel identity.
- Wheel-slot identity.
- Slot range selection.
- ChannelFunction evaluation.
- ChannelSet evaluation.
- ModeMaster effects.
- Resource reference resolution.
- Index angle.
- Rotation speed.
- Rotation direction.
- Shake behavior.
- Diagnostics.

### Native CPU-side resource preparation

Native C++ should own, when practical:

- Archive extraction.
- PNG decoding.
- SVG parsing.
- Rasterization.
- Alpha-mask normalization.
- Hashing.
- Cache keys.
- SDF generation where justified.
- Atlas planning.
- Multi-wheel composition planning.
- Prepared image or mask buffers.

These operations must not run every frame.

### Godot renderer ownership

Godot owns:

- Final `Image` creation.
- Final `ImageTexture` creation.
- Texture updates.
- Material assignment.
- Shader assignment.
- RID creation.
- Shader parameter updates.
- Renderer-specific filtering.

Rotation, index, continuous movement, direction, and shake should normally use parameters rather than image regeneration.

A texture changes only when slot selection, resource identity, composition, or topology changes.

## Color architecture

Native C++ owns color semantics.

Depending on fixture data and support level, native color resolution may include:

- RGB.
- CMY.
- RGBW.
- RGBA.
- Color wheels.
- Emitters.
- Filters.
- Color temperature.
- Tint.
- Color spaces.
- Gamuts.
- DMX profiles.

Godot should receive final or near-final linear renderer color.

Godot may apply renderer-specific exposure, tone mapping, or approximation, but must not reinterpret GDTF channels.

## Beam and optics architecture

Native C++ owns semantic and physical optical state:

- Zoom.
- Beam angle.
- Field angle.
- Iris.
- Frost.
- Focus.
- Beam type.
- Edge softness.
- Lens or beam metadata where supported.
- Intensity relationships.

Godot receives prepared renderer values.

Godot owns the concrete visual implementation:

- SpotLight3D properties.
- Beam meshes.
- Volumetric materials.
- Shader parameters.
- Renderer-specific approximations.

## Temporal output architecture

Native C++ owns:

- Shutter state.
- Strobe mode.
- Strobe frequency.
- Duty cycle.
- Phase.
- Pulse behavior.
- Random behavior where supported.
- Time-dependent semantic state.

Godot receives prepared temporal output or phase parameters.

Godot must not infer strobe behavior from raw normalized DMX.

## Threading

Parsing, validation, compilation, DMX resolution, dirty-state generation, and CPU-side resource preparation may use native worker threads.

Native threads must not mutate:

- Godot Nodes.
- Godot Resources.
- Godot RIDs.
- Materials.
- Textures.
- RenderingServer objects.

Use:

- Immutable compiled models.
- Immutable structural snapshots.
- Double-buffered live deltas.
- Lock-free queues.
- Short mutex-protected swaps.
- Latest-wins frame coalescing where appropriate.

Do not hold locks while calling into Godot.

## Diagnostics

Diagnostics should be generated primarily during parsing, validation, and compilation.

Diagnostics may include:

- Missing required sections.
- Invalid references.
- Invalid ranges.
- Unknown attributes.
- Custom attributes.
- Unsupported official attributes.
- Unsupported feature families.
- Approximation decisions.
- Missing resources.
- Invalid resource formats.
- Invalid wheel-slot references.
- Invalid ModeMaster references.
- Invalid relation references.
- Schema mismatch.
- Stale schema generation.
- Missing render target.
- Unsupported renderer capability.

Diagnostics must not become part of the authoritative live state.

Diagnostic Dictionaries and strings are acceptable outside the hot path.

## Support levels

The GDTF support matrix must classify features as:

- **Exact**
  - Parsed, compiled, resolved, and visually applied according to the intended semantics.

- **Partial**
  - Parsed and applied with documented limitations.

- **Diagnostic-only**
  - Parsed or preserved, but not visually applied.

- **Unsupported**
  - Not implemented.

- **Invalid**
  - Source data is malformed or inconsistent.

- **Approximated**
  - The renderer cannot reproduce the exact behavior and uses a documented approximation.

No feature should be listed as exact merely because its name is recognized.

## Current implementation status

This section must be maintained conservatively.

At the time this architecture is adopted:

### Target

The target production path is:

```text
Real GDTF
    -> project-owned parser
    -> serialization-neutral semantic model
    -> immutable compiled fixture type
    -> scene and component registry
    -> compiled DMX programs
    -> native physical and render-state resolution
    -> typed dirty deltas
    -> direct Godot domain appliers
```

### Partially active

The repository contains parts of the target architecture, including:

- Native GDTF runtime model foundations.
- Versioned section schema foundations.
- Typed integer and float payload concepts.
- Domain-specific Godot section appliers.
- Native dirty-state and section-assembly experiments.
- Semantic contract and registry artifacts.

These parts do not prove that the final production path is active.

### Migration-sensitive

The following patterns must be treated as migration-sensitive until removed:

- Godot-created fixture binding Dictionaries.
- `set_fixture_bindings(Array)` style setup.
- Magic channel-type numbers.
- Fixed compact-control models.
- Fixed single-instance component state.
- Duplicate C++ and Godot fixture caches.
- Godot-side DMX capability normalization used by production.
- Godot-side gobo range resolution used as semantic authority.
- Universal fixture-state or universal apply methods.
- Legacy runtime registration or fallback paths.
- Tests that construct legacy bindings manually.

### Not yet proven active

The following must not be described as fully active until an end-to-end production test proves them:

- Parser-owned `CompiledGdtfFixtureType` feeding the live runtime directly.
- Real GDTF ChannelFunctions feeding compiled DMX programs.
- Real ModeMaster evaluation in the live runtime.
- Real relation evaluation in the live runtime.
- Repeated component families through the complete path.
- Native-owned gobo slot and motion resolution through the complete path.
- Full structural installation separated from live deltas.

## Required vertical test

The first mandatory end-to-end proof is:

```text
Real GDTF test fixture
    -> project-owned parser
    -> compiled fixture type
    -> selected DMX mode
    -> structural component registry
    -> compiled Dimmer program
    -> compiled Pan program
    -> compiled Tilt program
    -> DMX frame
    -> native resolved values
    -> typed dirty deltas
    -> direct Godot render-domain application
```

The test must prove:

- The GDTF file is actually parsed.
- The selected DMX mode is actually used.
- ChannelFunctions are actually compiled.
- Dimmer, Pan, and Tilt are not mapped through magic channel integers.
- The runtime consumes compiled programs directly.
- Godot does not reconstruct semantic state.
- The legacy binding path is not used.
- Dirty domains remain isolated.
- Repeated identical frames emit no unnecessary changes.

Advanced gobo behavior must not be used as a substitute for this first vertical proof.

## Test requirements

Tests should cover:

- Parser determinism.
- Compiled-model determinism.
- Geometry-reference expansion.
- Canonical attribute identities.
- Wildcard and numbered attributes.
- ChannelFunction selection.
- ChannelSet selection.
- Physical-range mapping.
- ModeMaster gating.
- Relations.
- DMX profiles.
- Repeated wheels.
- Repeated emitters.
- Repeated geometry components.
- Unknown attributes.
- Unsupported attributes.
- Invalid references.
- Missing resources.
- Schema version rejection.
- Schema-generation rejection.
- Invalid section offsets.
- Invalid row strides.
- Unused universe rejection.
- Irrelevant-byte filtering.
- Latest-wins coalescing.
- Unchanged-frame suppression.
- Dirty-domain isolation.
- Structural and live separation.
- Legacy API absence after migration.
- Peraviz and Perastage semantic contract consistency.

## Guardrail requirements

Architecture guardrails must verify active dependencies and APIs.

They must not rely only on banned filenames or variable names.

Guardrails should detect:

- `set_fixture_bindings(Array)` remaining in the final path.
- Magic channel-type mappings.
- Godot-side DMX decoding.
- Godot-side GDTF semantic interpretation.
- Universal per-fixture state Dictionaries.
- Fixed one-gobo or one-prism state as the only representation.
- Legacy runtime classes still registered.
- Old fallback paths still compiled.
- Production tests that use only manual legacy bindings.
- Checks that inspect nonexistent directories.
- Missing expected source paths.
- Target documentation that claims unproven active behavior.

A missing expected path must fail the guardrail.

## Migration rules

During an approved architectural replacement:

- Internal APIs may be broken.
- Legacy paths should be removed from the active build.
- Git history is the legacy reference.
- Temporary bridges require an owner, expiration condition, and deletion test.
- Temporary bridges must not receive new features.
- A new type without a new production call graph is not a completed migration.
- Passing string-based guardrails is not enough.
- The active call graph must be reviewed.
- End-to-end tests must prove the new path.
- Secondary features may remain temporarily unsupported when the new vertical path is real and no longer routes through legacy code.

## Migration completion criteria

The GDTF-first runtime migration is complete only when:

1. Real GDTF files feed the project-owned parser.
2. The parser produces the serialization-neutral semantic model.
3. The compiler produces immutable fixture types.
4. Fixture instances reference compiled types.
5. The scene compiler produces stable component and render-target IDs.
6. The live runtime consumes compiled DMX programs directly.
7. Godot does not create authoritative fixture channel bindings.
8. Magic channel-type numbers are absent from the final production path.
9. Repeated families use IDs and collections.
10. Native C++ owns physical-state resolution.
11. Native C++ owns dirty-state generation.
12. Structural installation and live deltas are separate.
13. Godot applies typed prepared data only.
14. Legacy runtime APIs are removed from registration and the build.
15. Legacy fallback paths are removed.
16. Tests exercise the real production path.
17. Guardrails inspect the real repository structure.
18. Documentation marks only proven behavior as active.
19. Dimmer, Pan, and Tilt pass the required vertical test.
20. Peraviz and Perastage semantic contract tests remain consistent.

## Documentation update rules

Update this document when changing:

- GDTF parser ownership.
- Semantic-model ownership.
- Compiled fixture type structure.
- Component identity rules.
- DMX program compilation.
- Physical-state calculation.
- Structural installation.
- Live section domains.
- Gobo resource ownership.
- Color architecture.
- Beam and optics architecture.
- Temporal output architecture.
- Support-level definitions.
- Required vertical tests.
- Migration completion criteria.

Do not add temporary implementation notes to target sections.

Use the `Current implementation status` section for temporary migration state.

## Final invariants

The following conditions must remain true:

1. GDTF is the semantic source of truth.
2. Native C++ owns GDTF parsing and compilation.
3. Native C++ owns live DMX resolution.
4. Native C++ owns physical and render-state preparation.
5. Godot owns rendering and presentation.
6. Godot does not reinterpret GDTF during live playback.
7. Structural installation and live updates are separate.
8. Stable IDs are used for repeated families and render targets.
9. Integer identities remain integer data.
10. Unknown and unsupported behavior is diagnosed rather than guessed.
11. Repeated GDTF families are never collapsed into one fixed field per fixture.
12. The active production path must be proven by end-to-end tests.
13. Legacy internal compatibility does not override an approved architectural replacement.
14. Shared Peraviz and Perastage semantics remain serialization-neutral.
15. Documentation never presents an unproven target as active behavior.
