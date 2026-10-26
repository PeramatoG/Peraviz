# Peraviz runtime architecture

This document is the source of truth for the active runtime. The [GDTF support matrix](gdtf-support-matrix.md) defines semantic coverage; focused renderer documents define presentation details.

## Ownership

Native C++ owns MVR/GDTF parsing, selected-mode semantic compilation, fixture patch and DMX source programs, physical-value evaluation, target-oriented state, dirty detection, and render-ready frame assembly. The compiled setup model is `CompiledRuntimeScene`.

Godot owns scene construction, interaction, UI, setup-time renderer resources, and mutation of cached renderer targets. `NativeRendererTargetRegistry` maps stable native component and render-target IDs to Godot objects. Native workers never modify scene nodes; main-thread GDExtension presentation may mutate cached renderer nodes. C++ is the simulation and calculation
core; Godot is the presentation engine. Native dependency evaluation,
physical composition and Render Group reduction connect directly to compact
presentation snapshots. Godot must not shuttle physical-state buffers between
native calculation stages. Parallel evaluation and race resolution
belong in C++; no Godot worker threads are introduced.

Scene import uses one owned native preparation task for archive/XML work, immutable
geometry expansion, selected-mode compilation and Control/Render Group classification.
Generation-scoped geometry templates retain model leases and rebind UUIDs/keys per
instance; scene replacement retires them. Setup indexes follow actual fixture/resource
ownership. Godot transfers the completed data, builds nodes/targets in frame-budgeted
batches. Renderer target/material/group installation is a single main-thread
transaction, matching main’s publication order: no rendering turn consumes
individual resources before their final sharing/aggregate bindings. CPU preparation
is already complete. This transaction is not subject to the 8 ms construction
budget; its wall time is recorded separately. Initial light defaults yield, and
hidden fixture-inspection tables retain data without allocating row Controls;
visible tables build eight rows per frame with generation-safe replacement.
The completed scene activates at most 16 visual instances per rendered batch
behind an opaque modal shield before its removal. This avoids exposing the whole
hidden scene to the graphics backend in one frame and restores exact local
visibility, transforms and resource identity; cancellation hides the retired
generation before restoring its local flags. Final readiness waits for three
render-server `frame_post_draw` acknowledgments, with a process-frame fallback
only in headless mode. These signals are not GPU fences. Activation counts alone
do not establish readiness. While hidden/minimized, readiness explicitly defers;
a drawable window missing acknowledgments for 15 seconds fails and retires the
generation. The coordinator propagates failure and keeps DMX gated through resource
diagnostics/publication; failed imports remain gated until a later successful load.
This watchdog cannot interrupt a blocked engine/driver call. Phase text reports
native preparation through an atomic token and Godot setup on the main thread.
PVZ opening restores saved visual settings and the universe offset after retiring the
old scene and before constructing the new resources. Receiver startup and original
PVZ preference publication finish inside the same loading generation; no visual
restoration runs after its summary. Bulk visual scalar changes defer per-member
dense rebinding and commit one global group rebuild with held-state replay.
The loading indicator gates edits and DMX application against partial targets. Cancellation drains the task and clears
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

## Compiled evaluation and native scheduling

Scene installation derives compact source/activation/consumer adjacency from the
existing selected-mode programs. Changed DMX offsets nominate only reachable domain
programs and optical layers. Instance-local workspaces cache decoded scalar values
until their own bytes change and share a complete ModeMaster activation result
within each relevant update. Declaration order, weighted/range interpretation and
temporal gobo state retain their existing owners. Selected-mode/content keys intern
immutable scalar mappings; patch addresses, source IDs, canonical targets and caches
remain independent. Setup serialization is unchanged.
See the [current performance roadmap](performance-foundation.md#compiled-evaluation-graph-phase-1)
for ownership limits, counters and a bounded reference comparison.

Large independent, non-gobo scenes use `AsyncPresentationPipeline`: the main thread
submits stable latest-state input banks and polls completed immutable snapshots.
One native coordinator owns the same moved physical state and compiled workspace.
`ParallelEvaluationPrefetch` runs disjoint source decoding and Color input/cooking
ranges through a bounded persistent C++ pool. Worker slots contain numeric scratch,
not authoritative state. The coordinator commits source warnings, properties,
activation, ordered Color/wheel maps and physical/reduction deltas in canonical
order. Cross-universe target writes remain ordered. Workers never call Godot.

Three input banks coalesce complete latest universe values; two output banks retain
ordered completed deltas, including one result waiting natively if Godot has not
consumed the preceding result. No unread delta is overwritten. Main-thread acquire
and release use atomic handoff without a worker wait. Input submission and polling
are separate, including frames with no new packets or a stopped stream. Godot packs
only accepted final render rows and independent domains and applies cached lens
RIDs. Its displayed physical-value cache is derived presentation data, not a second
simulation owner. Scene/schema/binding identities gate publication. Explicit setup,
renderer/diagnostic transitions and shutdown invalidate publication before joining
and retiring borrowed definitions; ordinary presentation never joins.

Small/shared-control scenes and gobo/temporal scenes retain the original serial
transaction. This subset deliberately avoids skipping temporal transitions or
changing the existing continuous gobo phase/velocity owner. See the
[adaptive evaluation comparison](performance-foundation.md#adaptive-native-parallel-evaluation)
for policy, measurements and remaining domains.

## Native dense presentation state

The [performance foundation](performance-foundation.md) remains the baseline;
renderer scalability is still open. Owner observations on Windows 4.7.1 Forward+
after PR #109 are approximately 75 FPS with active DMX; V-Sync may limit this observation.
Those observations do not attribute the remaining cost or predict this change's FPS.

Production calls `PeravizPresentationState.consume_runtime()` once per logical
update. `DirectPresentationPipeline` connects native selected-mode evaluation,
`DensePresentationState` composition and `RenderGroupProjection` reduction using
borrowed, reusable C++ section buffers. Intensity, Color and BeamOptics scalars
never cross into Godot for further calculation. The sole authoritative physical
presentation state remains in `DensePresentationState`; worker jobs own only
scratch. Godot receives final renderer deltas and independent sectioned Pan/Tilt,
wheel, gobo and temporal updates. Schema and binding generations are checked
before consuming pending DMX. Independent domains finish before script fallback shafts; native dynamic shaft writes are transform-independent and consume the same accepted generation.
The explicit packed `compose()` API remains for reference tests and cold held-state
replay; live playback uses the direct transaction.

Godot keeps physical lenses and fallback objects. Compatible controls retain
shared shaft/lens material ownership in Control Groups. Canonical outputs, selected-mode
ownership, physical native state and normal Pan/Tilt transforms remain exact;
compact-source native Render Emitter Groups now accumulate physical members into
AGGREGATED or INDIVIDUAL shaft rows. Exactly one renderer-sized integer/float
payload pair crosses to Godot. Main-thread native Godot glue updates cached lens
RIDs from exact physical values, separately from optical shaft mixing. Compatible
independent opaque lenses now use the bounded MultiMesh path described below;
volumetric shafts retain their reference rendering. Large independent Vector Prism scenes now use the exact native main-thread batch described below. See [dense presentation state](native-dense-presentation-state.md)
for ownership, remaining allocations, stage telemetry and the exact Windows A/B.

## Independent emitter presentation, phase 1

`NativeBeamBindings` applies final native render rows directly to weak, indexed
MeshInstance3D handles on Godot's main thread. It uses the same Vector Prism mesh,
material, instance uniforms, Node visibility and ancestor transforms. Native
serial and completed-async publication share this consumer. The cache holds only
last-applied renderer signatures, never physical lighting authority. Packed final
rows remain available for inspection; a reusable fallback-row index prefix means
GDScript iterates only unsupported rows, without per-row objects or dictionaries
for handled outputs. No physical values are sent back into C++ by scripts.

Cold admission requires at least 128 compatible individual rows, open Vector Prism
resources, no shared Control Group material, gobo/projector, debug or realtime
surface-light policy. The 115-row reference scene retains its existing renderer
loop. Zoom/topology always use the exact reference fallback and invalidate mutation
signatures before reuse. Scene/renderer/resource changes revoke weak bindings;
freed object IDs fail safely to fallback. Publication still requires current
schema/binding generations and never waits on workers during ordinary frames.
See the [bounded comparison](performance-foundation.md#independent-emitter-render-application-phase-1)
for the GPU-instancing decision, resource limits and measurement boundaries.

## GPU-instanced independent apertures, phase 1

`InstancedLensBatches` admits only Forward+ opaque, double-sided, single-surface
triangle lenses whose stored StandardMaterial options match the default PBR
reference (white albedo, metallic 0, roughness 1, specular 0.5, additive emission).
Textures, custom shaders/passes, transparency, skinned/morphed geometry, nondefault
render policy, physical light units, Control Groups and projector/gobo resources
retain individual lenses. A small shader implements that material slice; it does
not implement optical simulation or any Vector Prism shaft formula.

Setup partitions shared mesh/material-compatible outputs by nearest mechanical
Axis and 4 m local cells, with 8–64 instances per batch. Reflected, non-conformal or oversized geometry
falls back. Canonical nodes, collision/picking children, source meshes/materials
and target IDs remain intact. Only their draw layers are suppressed; a shared
batch material renders exact independent Color/emission through INSTANCE_CUSTOM.
Batch transforms inherit the same mechanical ancestor. Static geometry/resource
configuration changes use the existing cold rebind/refresh transaction.

`NativeLensBatches` borrows generation-checked MultiMesh RIDs and indexed physical
routes. Both serial and completed async publication update reusable 16-float
transform/custom buffers directly from native physical values, then submit each
changed batch once through `multimesh_set_buffer()` on the main thread. No
GDScript physical-value round trip, worker Godot calls or ordinary presentation
wait is introduced. Source visibility signals coalesce a native buffer flush,
including held/no-packet frames. Cold renderer/policy changes revoke routes before
freeing batch nodes, restore original draw layers and replay authoritative held
state. Diagnostic modes and unsupported backends use individual lenses. Original
lens resources are retained for exact fallback; this stage reduces submissions,
not their allocation. MultiMesh culling is per bounded batch, not per instance.
See the [measured comparison](performance-foundation.md#gpu-instanced-independent-apertures-phase-1).

## Aggregate member shaft lifetime

Native classification nominates provisional members before registry shaft creation.
The standard Vector Prism renderer exposes an immutable generation/resource
identity description without constructing member meshes or materials. Unknown
materials, gobo/projector resources and unsupported policies retain eager resources
and exact fallback. Final render layout acceptance checks physical membership,
anchors, optical/resource compatibility and selected-mode Zoom authority before
`AggregateShaftResources` confirms deferral. Canonical outputs, SpotLight anchors,
mechanical geometry, optical metadata and physical lenses remain installed.

The cold binding transaction now resolves render layout, reconciles actual shaft
allocation, installs Control Groups/lens sharing, and finally binds lens RIDs.
Deferred Control Groups retain their native control and lens ownership without a
phantom shared shaft material. Accepted aggregates own normal renderer shafts;
member shafts are absent. Resource lists are rebound in one indexed transaction.
Policy or resource changes rehydrate missing individuals hidden on the main thread,
then force native held-state replay before presentation. No new DMX packet is
needed. Re-acceptance retires unnecessary nodes immediately after revoking native
beam handles. Renderer replacement refreshes resource descriptions, never borrowed
old-generation handles. Dimmer/Color playback never changes resource ownership.
See the [allocation comparison](performance-foundation.md#lazy-aggregate-member-shafts).

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

Production playback is scheduled by `load_scene.gd::_process`, which calls `DmxController.process_dmx`, the native receiver/coordinator pump, completed-snapshot polling through `PeravizPresentationState.consume_runtime`, and `SectionedVisualFrameApplier.apply_snapshot` in the same render-process opportunity. The serial fallback completes its native transaction there; asynchronous native work can complete between opportunities. The 125 ms status refresh only updates monitor UI and does not gate playback. Apply completion is recorded after cached Godot renderer targets have been mutated. This is a CPU-side boundary; render submission, GPU execution, display queueing, and presentation are intentionally not represented as CPU RX-to-apply latency.

Renderer diagnostic modes are presentation-only policy over the section applier. They do not change native semantic evaluation, the sectioned protocol, saved visual settings, or renderer resource ownership. Emission-only GDTF Beam outputs remain physical geometry but are excluded from projected beam allocation and work.
