# Peraviz runtime architecture

This document is the source of truth for the active runtime. The [GDTF support matrix](gdtf-support-matrix.md) defines semantic coverage; focused renderer documents define presentation details.

## Ownership

Native C++ owns MVR/GDTF parsing, selected-mode semantic compilation, fixture patch and DMX source programs, physical-value evaluation, target-oriented state, dirty detection, and render-ready frame assembly. The compiled setup model is `CompiledRuntimeScene`.

Godot owns scene construction, interaction, UI, setup-time renderer resources, and mutation of cached renderer targets. `NativeRendererTargetRegistry` maps stable native component and render-target IDs to Godot objects. Native threads do not modify scene nodes.

Scene import uses one owned native preparation task for archive/XML work, immutable
geometry expansion, selected-mode compilation and Control/Render Group classification.
Generation-scoped geometry templates retain model leases and rebind UUIDs/keys per
instance; scene replacement retires them. Setup indexes follow actual fixture/resource
ownership. Godot transfers the completed data, builds nodes/targets in frame-budgeted
batches, and publishes readiness after binding. A modal loading indicator gates edits
and DMX application against partial targets. Cancellation drains the task and clears
partial resources; native code never mutates the SceneTree from that task.

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

## Native dense presentation state

The [performance foundation is stable](performance-foundation.md); renderer
scalability remains open. The current canonical full result is about 24–25 FPS,
not the final target. User arguments after Godot's `--` select diagnostic policy;
actual mode/resource integration tests guard that boundary.

After sectioned semantic evaluation, `PeravizPresentationState` composes Intensity,
Color and BeamOptics through setup-only integer routes into a contiguous native
state per physical output. Scene binding assigns stable dense indices while
preserving canonical output IDs. Generation checks retire stale indices; native
pending masks deduplicate a bounded dirty-index vector. One packed delta crosses
to an indexed adapter with pre-bound light, beam and material handles. Normal
lighting playback bypasses the old per-output Dictionary commit/state pipeline.
Godot keeps physical lenses and fallback objects. Compatible controls retain
shared shaft/lens material ownership in Control Groups. Canonical outputs, selected-mode
ownership, physical native state and normal Pan/Tilt transforms remain exact;
compact-source native Render Emitter Groups now accumulate physical members into
AGGREGATED or INDIVIDUAL shaft rows. Exactly one renderer-sized integer/float
payload pair crosses to Godot. Main-thread native Godot glue updates cached lens
RIDs from exact physical values, separately from optical shaft mixing. MultiMesh,
independent-output batching and C++ threading remain future work. See [dense presentation state](native-dense-presentation-state.md)
for ownership, remaining allocations, stage telemetry and the exact Windows A/B.

## Renderer ownership

GDTF/native semantic state determines physical optical values. Peraviz resolves
shared presentation geometry into one [Optical Projection State](optical-projection-state.md)
per emitter. Every projected output may resolve surface-profile data without owning
a realtime renderer light. Vector Prism grants realtime ownership only to genuine
projectors and explicit realtime/experimental modes. Open-light A/B is an opt-in
developer argument; see [surface ownership](surface-light-ownership.md). The future
physical outputs → optical/surface state → Control/Render Groups → bounded/batched
surface backend remains deferred. Vector shaft and surface footprint consume its aperture,
base optical transform, native gobo roll, visual alignment and parity. They may not
maintain competing authoritative optical transforms. Color/intensity remain in the
native dense photometric state; camera movement cannot dirty projection geometry.

Dense playback assigns SpotLight RID visibility to the adapter, including gobo
callbacks. Its structural Node stays visible during full playback and changes
only at binding/diagnostic boundaries; suppressed modes hide it once to stop
hidden transform forwarding. Node visibility/tree notifications repair Godot's
own RID write. Beam/debug Nodes and aperture values have effective-value guards.
No-beams retains native lighting and gobo control state while suppressing beam,
light and local gobo renderer work after one cleanup; full resumes held state.
Typed bound prism signatures are renderer caches, not composition authorities.
The internal cache helper is explicitly preloaded and has no global class-cache
requirement; the base API accepts RefCounted. Required dense installation failures
reject playback instead of silently using legacy state. Stability trace reports
whether dense presentation is active. Existing-light discovery preserves its
live state. See [runtime recovery](native-dense-runtime-recovery.md) for cold-cache
startup validation and beam/footprint lifecycle coverage.

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
- [Rendering and performance architecture decisions](rendering-performance-architecture.md)
- [Runtime storage policy](runtime-storage-policy.md)
- [Godot performance guidelines](godot_performance_guidelines.md)

## Realtime DMX scene path

Art-Net reception records cheap metadata for all valid traffic, but only universes and offsets derived from the installed `CompiledRuntimeScene` enter the native latest-state mailbox. Clean-to-dirty transitions append one generation-tagged ID to a fixed ring; the native coordinator drains only those IDs, so idle cost does not scan patched universes. Godot invokes one native pump per render frame, and only the resulting sectioned renderer frame crosses into GDScript. Technical Monitor sessions use a fresh generation and a strict four-captures-per-drain and one-per-millisecond budget, so diagnostic fidelity degrades before scene processing. See [Realtime DMX runtime](realtime-dmx-runtime.md).

## Live latency measurement boundary

Production playback is scheduled by `load_scene.gd::_process`, which calls `DmxController.process_dmx`, the native receiver/coordinator pump, `PeravizVisualRuntime.consume_latest_visual_frame`, and `SectionedVisualFrameApplier.apply_snapshot` in the same render-process opportunity. The 125 ms status refresh only updates monitor UI and does not gate playback. Apply completion is recorded after cached Godot renderer targets have been mutated. This is a CPU-side boundary; render submission, GPU execution, display queueing, and presentation are intentionally not represented as CPU RX-to-apply latency.

Renderer diagnostic modes are presentation-only policy over the section applier. They do not change native semantic evaluation, the sectioned protocol, saved visual settings, or renderer resource ownership. Emission-only GDTF Beam outputs remain physical geometry but are excluded from projected beam allocation and work.
