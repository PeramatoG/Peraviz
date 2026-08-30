# Peraviz runtime architecture

This document is the source of truth for the active runtime. The [GDTF support matrix](gdtf-support-matrix.md) defines semantic coverage; focused renderer documents define presentation details.

## Ownership

Native C++ owns MVR/GDTF parsing, selected-mode semantic compilation, fixture patch and DMX source programs, physical-value evaluation, target-oriented state, dirty detection, and render-ready frame assembly. The compiled setup model is `CompiledRuntimeScene`.

Godot owns scene construction, interaction, UI, setup-time renderer resources, and mutation of cached renderer targets. `NativeRendererTargetRegistry` maps stable native component and render-target IDs to Godot objects. Native threads do not modify scene nodes.

Legacy fixture bindings and Godot-side semantic helpers remain in limited compatibility, inspection, or transitional areas. They are not authoritative for native-supported live attributes.

## Setup and playback contracts

Structural setup occurs before live playback. The loader and compiler install fixture instances, patch records, ordered DMX byte sources, property contributors, stable component/render-target IDs, renderer manifests, Beam profiles, wheel resources, and gobo resources. Godot builds and caches the corresponding target records and reusable materials, meshes, textures, and nodes.

The versioned compiled setup payload is encoded and decoded by the shared native `CompiledRuntimeScene` codec. The codec owns field order, version-specific strides, complete cursor validation, and deterministic rejection of truncated or trailing payloads; Godot wrappers only convert packed array containers.

Live playback submits relevant universe snapshots to the native runtime. It does not rebuild setup dictionaries or discover semantic ownership per frame. Native processing coalesces input, filters unchanged relevant slots, evaluates active `ChannelFunction` ranges, updates target-oriented state, and publishes only dirty renderer data.

## Active data flow

```text
MVR patch + selected GDTF DMX mode
  -> native parser-owned fixture model
  -> CompiledRuntimeScene with stable IDs and source programs
  -> submitted DMX universe snapshots
  -> native range/physical evaluation and target state
  -> dirty SectionedVisualFrame
  -> Godot section applier
  -> cached renderer targets and resources
```

`SectionedVisualFrame` contains descriptors plus separate integer and float payloads. IDs, masks, modes, revisions, and indices remain integers; physical and renderer scalars remain floats. Sections are enabled by installed capabilities rather than forced into a universal fixture row. Godot consumes the newest completed frame and dispatches each section to its domain applier.

Dimmer state is render-target-oriented, Pan/Tilt state is component-oriented, and color, BeamOptics, wheel, and gobo output is associated with exact Beam targets. Repeated targets therefore do not collapse into one fixture-wide value.

## Renderer ownership

Godot creates and retains renderer-facing resources during setup. Live section application mutates those cached resources without rebuilding the scene tree. Lightweight Prism owns parametric beam aperture/spread updates, including setup-time Beam profiles and native target-oriented Zoom rows. Optional realtime spotlights and volumetric/lightweight beam resources remain presentation choices; they do not interpret GDTF DMX semantics.

Static seated gobos use native `GoboSelection` rows and setup-time `NativeGoboResourceRegistry` resources. Indexed selected-gobo angles and continuous selected-gobo AngularSpeed use protocol 2.3 `GoboRotation` motion-state rows transported through compiled setup contract 7. C++ owns authoritative phase, signed velocity, ModeMaster arbitration, and dirty transitions; Godot advances active layers locally and mutates presentation parameters without topology regeneration. Gobo selection and rotation ownership is keyed by Beam render target plus one-based wheel instance; binding IDs remain diagnostic identities and never arbitrate Pos against PosRotate. Logical gobo control and temporal state outlive renderer target generations; target rebuilds explicitly rehydrate current resources and phase, while true runtime rebuilds seed the new native generation once from the latest held snapshots for used universes. Godot may compose and cache a bounded static multi-wheel mask, but independently moving compositions remain deferred. See [Gobo control](GDTF_GOBO_CONTROL.md).

## Invariants and limitations

- Structural setup and live updates remain separate.
- Stable IDs identify fixture instances, components, targets, wheels, slots, and resources.
- The sectioned descriptor/integer/float frame remains the only active visual-frame contract; the removed fixed-row path must not return.
- Native-supported domains do not fall back to legacy Godot semantic dictionaries.
- Unsupported or incomplete GDTF semantics produce diagnostics instead of guessed production behavior.
- ChannelFunction ModeMaster Node links are resolved and cycle-validated during setup, then carried as compact DMXChannel or ChannelFunction activation conditions in `CompiledRuntimeScene` for native scalar evaluation. Relations, virtual attributes, and DMXProfiles remain unsupported.
- Gobo motion, prisms, shutters/strobe rendering, Focus, Iris, Frost, and other entries marked unsupported in the matrix are not production-supported.

## Related documents

- [GDTF support matrix](gdtf-support-matrix.md)
- [Gobo control](GDTF_GOBO_CONTROL.md)
- [GDTF parser ownership ADR](adr-gdtf-parser-ownership.md)
- [Uniform physical color pipeline](uniform-physical-color-pipeline.md)
- [Beam rendering modes](BEAM_RENDERING_MODES.md)
- [Runtime storage policy](runtime-storage-policy.md)
- [Godot performance guidelines](godot_performance_guidelines.md)

## Realtime DMX scene path

Art-Net reception records cheap metadata for all valid traffic, but only universes and offsets derived from the installed `CompiledRuntimeScene` enter the native latest-state mailbox. Clean-to-dirty transitions append one generation-tagged ID to a fixed ring; the native coordinator drains only those IDs, so idle cost does not scan patched universes. Godot invokes one native pump per render frame, and only the resulting sectioned renderer frame crosses into GDScript. Technical Monitor sessions use a fresh generation and a strict four-captures-per-drain and one-per-millisecond budget, so diagnostic fidelity degrades before scene processing. See [Realtime DMX runtime](realtime-dmx-runtime.md).
