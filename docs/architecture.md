# Peraviz architecture

## Purpose

This is the short technical source of truth for the active Peraviz runtime. Peraviz is a real-time lighting visualizer: native C++ owns DMX/GDTF-derived runtime state resolution, dirty-state generation, and render-ready frame preparation, while Godot owns presentation, renderer resources, interaction, and applying prepared sections to cached scene objects.

## Current implementation

The active live output remains the native sectioned visual frame. `SectionedVisualFrame` carries section descriptors plus separate integer and float payload arrays. The Godot bridge exposes the latest completed frame as a `Dictionary` with `descriptors`, `integers`, `floats`, and schema data for the section applier.

The production setup authority for the visual runtime is now a native compiled scene contract produced by the loader-owned native GDTF/MVR compiler. It installs stable fixture, component, render-target, patch, DMX source-program, property-contributor, and renderer-manifest records before live frames are submitted. The current Dimmer/Pan/Tilt slice is native-first, with application verification still required before broader production claims.

Current native runtime responsibilities include:

- Latest-frame coalescing so Godot consumes only the newest visual frame.
- Universe filtering and relevant-slot hashing before fixture updates are emitted.
- Native compiled scene generation and installation for fixture instances, stable IDs, DMX byte sources, and property contributors.
- Multi-byte DMX value assembly from ordered source byte records, including non-adjacent coarse/fine addresses.
- Dirty-state detection for transform and intensity output in the verified Dimmer/Pan/Tilt slice.
- Render-value cooking for sectioned visual output.
- Section assembly using descriptors and typed payloads.
- Visual frame schema validation helpers and behavior tests.

Current Godot runtime responsibilities include:

- Orchestrating runtime setup and renderer registration.
- Consuming the native sectioned visual frame.
- Applying domain-specific sections for prepared runtime output.
- Maintaining renderer-facing nodes, materials, beams, and UI state.

## Current live data flow

```text
MVR fixture patch
  -> parser-owned selected GDTF DMX mode model
  -> scoped DMXChannel records under the selected mode, including standard DMXChannels wrappers and harmless vendor wrappers
  -> LogicalChannel / ChannelFunction records with inferred or explicit full-resolution DMX ranges
  -> CompiledGdtfFixtureType
  -> native compiled runtime scene
  -> native fixture instances, patch, source programs, and contributors
  -> submitted universe snapshots
  -> relevant-slot filtering and native DMX evaluation
  -> dirty SectionedVisualFrame descriptors + integer payloads + float payloads
  -> Godot sectioned frame applier
  -> exact cached native target IDs resolved from full imported-node canonical GDTF geometry-instance keys
  -> cached renderer nodes, materials, lights, and beams
```

The live frame format is intentionally sectioned rather than one universal fixed row. Integer identifiers, flags, masks, offsets, and raw DMX source metadata stay in integer-oriented structures and payloads. Physical/render scalars such as pan, tilt, and intensity values stay in float payloads after compiled native evaluation.

## Removed visual-runtime setup bridge

The native visual runtime no longer exposes the old `set_fixture_bindings(Array<Dictionary>)` or `set_fixture_render_params(Dictionary)` setup methods. The runtime core no longer uses `FixtureChannelBinding`, magic numeric `channel_type` mappings, or a legacy semantic translation table to install production visual programs.

Godot registers the native renderer manifest once during structural setup, resolves native component/render-target IDs to cached scene targets by canonical GDTF geometry keys, and applies live Transform and Intensity rows through those IDs. Compiled-scene used universes, not legacy flattened bindings, own Dimmer/Pan/Tilt frame submission to the native runtime. The remaining GDScript inspection and gobo compatibility code is not an authoritative Dimmer/Pan/Tilt runtime path. Domains outside the verified Dimmer/Pan/Tilt slice must be wired through the compiled native contract before being described as production-supported.

## Verified GDTF/runtime coverage

- Dimmer: real selected-mode ChannelFunction records provide DMX range, physical range, ordered source bytes, fixture patch, and render-target ownership for native evaluation.
- Pan: real selected-mode ChannelFunction records provide DMX range, physical range, ordered source bytes, fixture patch, and component ownership for native evaluation.
- Tilt: real selected-mode ChannelFunction records provide DMX range, physical range, ordered source bytes, fixture patch, and component ownership for native evaluation.
- The generic source reader accepts one to four ordered bytes, so 8-bit, 16-bit, 24-bit, and 32-bit source layouts are supported by the runtime model.
- One resolved component property can contain multiple ChannelFunction ranges; native evaluation selects the active range from the assembled raw DMX value.
- Transform section rows use integer payloads `[fixture_id, pan_component_id, tilt_component_id, changed_mask]` and float payloads `[pan_degrees, tilt_degrees]`.
- Transform section Pan/Tilt values are physical degrees, not normalized values.
- The technical DMX monitor is on-demand: hidden windows perform no grid refresh work, and visible windows copy the selected universe only when metadata changes.

## Known unsupported GDTF semantics

ModeMaster, Relations, virtual attributes, complex ChannelSet selection, CMY/RGB/color wheels/CTO, gobos, prisms, strobe curves, repeated emitters, and repeated wheel families are not claimed as production-supported by this slice unless a later test connects them through the compiled runtime path end to end. Unsupported or incomplete compiled inputs should produce diagnostics instead of silent semantic guessing.

## Runtime invariants

- Structural setup and live DMX submission remain separate contracts.
- The sectioned frame path remains active.
- Descriptor, integer payload, and float payload storage remain separate.
- The obsolete native fixed visual-frame buffer path stays deleted.
- Section appliers do not reconstruct the removed universal fixed row.
- Native receiving or processing threads do not mutate Godot scene nodes directly.

## Next architectural step

The next recommended vertical slice is color intensity/color-mixing through parser-owned compiled GDTF programs, with behavior tests proving selected ChannelFunction ranges and renderer-facing color sections without restoring Godot-built semantic dictionaries.

## Supporting documents

- `docs/adr-gdtf-parser-ownership.md` records the parser ownership decision shared with Perastage.
- `docs/gdtf-support-matrix.md` summarizes currently verified GDTF semantic coverage.
- `docs/pvz-project-format.md` documents the `.pvz` archive format.
- `docs/godot_performance_guidelines.md` contains renderer and scene-tree performance guidance.
- `docs/NATIVE_BUILD.md` documents native build steps.
- `docs/MVR_XCHANGE.md` documents MVR-xchange behavior.

### Native Dimmer/Pan/Tilt runtime contract

The active Dimmer/Pan/Tilt path is parser-owned: MVR fixture patches select GDTF DMX modes, selected-mode `ChannelFunction` records compile into native source programs and component properties, and live Art-Net frames are evaluated by the native sectioned runtime. The evaluator preserves raw DMX, local normalized range position, and GDTF physical value separately. Pan and Tilt consume physical degrees; Dimmer consumes normalized 0–1 intensity even when the GDTF physical range is 0–100.

Dimmer is target-oriented rather than fixture-oriented. Each compiled Dimmer property keeps its own property ID, component ID, render target ID, geometry key, contributors, cached state, dirty comparison, and emitted `EmitterIntensity` row. Fixtures with repeated emitters can therefore produce multiple changed intensity rows in one frame without last-target-wins overwrite.

Godot resolves renderer targets during structural setup only through the focused `NativeRendererTargetRegistry` service. `load_scene.gd` remains the scene lifecycle coordinator, but the registry owns canonical geometry-key indexing, Pan/Tilt component targets, Dimmer render-target records, duplicate/overlap diagnostics, and cached renderer resource summaries. Dimmer target records cache exact owner geometry, emitter anchors, Lightweight Prism beam instances, lens material targets, optional spotlight anchors, and photometric data. Live Dimmer rows update those cached resources directly; they do not parse GDTF, search by fixture UUID, traverse descendants, rebuild prism topology for intensity-only updates, or use legacy fixture bindings. Realtime spotlights may remain disabled because the Lightweight Prism backend provides the acceptance beam output independently.

This checkpoint has been visually verified in the Windows/Godot application for native Pan, Tilt, and Dimmer response through native target IDs. Lightweight Prism now has a native BeamOptics profile and parametric near/far deformation path for Beam geometry and Zoom; footprint alignment, gobo-shaped prism geometry, and advanced volumetric quality remain future work.

## Native BeamOptics foundation

Peraviz now installs a setup-time native Beam optical profile for each resolved Beam geometry/render target. The profile preserves official Beam geometry fields used by the renderer: BeamType, BeamAngle, FieldAngle, BeamRadius, ThrowRatio, RectangleRatio, LuminousFlux, ColorTemperature, and provenance for angle/radius fallbacks. Zoom remains a native selected-mode ChannelFunction property and emits target-oriented BeamOptics rows with the physical full angle and normalized range position.

The renderer keeps official optical radius separate from measured model aperture and selected visual near radius. Explicit BeamRadius is preserved as official data; the Lightweight Prism path also records measured aperture radius, selected render near radius, selection source, and mismatch ratio so oversized-start issues are diagnosable instead of silently hidden.

Lightweight Prism now exposes a real BeamOptics renderer API. Setup applies static Beam profiles even for fixtures without Zoom, and live Zoom updates mutate per-instance near/far beam parameters on the existing custom prism resource. Spot, Wash, PC, and Fresnel use circular aperture topology; Rectangle uses a rectangular topology with RectangleRatio; None and Glow hide the projected custom beam. Gobo vectorization remains separate from physical aperture topology and is not activated by this work.

Remaining limitations: advanced photometry, Focus, Iris, Frost, prisms, shutters, active gobo selection/rotation, and high-quality volumetric rectangular rendering remain unsupported.


See [Beam geometry and visual length](BEAM_GEOMETRY_AND_VISUAL_LENGTH.md) for the renderer aperture, full-angle, and Peraviz-specific visual-length contract.

## Beam appearance ownership

Beam appearance is resolved in Godot from the native transported Beam profile and cached as renderer parameters. Native/parser-owned BeamType, BeamAngle, FieldAngle, BeamRadius, RectangleRatio, and target identity remain authoritative; the renderer does not parse GDTF XML or infer fixture names during live playback.

Native BeamOptics profiles now carry BeamType provenance (`raw`, effective value, source, validity) into renderer target records. Godot finalizes one Beam render parameter dictionary after BeamType, FieldAngle, RectangleRatio, visual length, aperture, intensity, and visual settings are known.


### Projected Beam photometric weighting

Peraviz computes projected Beam target luminous-flux totals and target fractions during native scene compilation. Runtime Dimmer updates keep the existing owner-level EmitterIntensity row and the cached Dimmer target record applies the immutable per-emitter fractions to its already prepared Beam and light resources, so multi-emitter fixtures distribute declared Beam energy across projected targets instead of applying full fixture energy to every Beam geometry. BeamType `None` and `Glow` are excluded from projected-beam totals, and missing Beam photometry falls back to deterministic equal weighting.
