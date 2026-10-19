# Foundation closure: ownership and legacy audit

This audit accompanies [performance foundation closure](performance-foundation.md)
from main `64e67e4`. It classifies exit ownership separately from sustained-playback
performance. The fixed-scene playback result is stable; an exit leak does not by
itself explain frame time.

## Outcome A: Peraviz-owned exit leak found and fixed

Pinned Godot 4.7.1 verbose headless shutdown with a loaded synthetic MVR reproduced:

| Independent outputs | ObjectDB instances leaked before fix | After fix |
| --- | --- | --- |
| 2 | 7 | 0 |
| 8 | 19 | 0 |
| 1,095 | **2,193** | **0** |

The exact relationship is `2 * outputs + 3`. Verbose instance IDs matched each
`DensePresentationAdapter.LightHandle` and its bound cache (two RefCounted objects
per output). The remaining three were their two GDScript resources and one native
RefCounted class wrapper retained by those objects. No leaked scene Nodes,
Materials, Meshes, Shapes or Textures were listed in this reproduction.

Each handle stores a `Callable(...).bind(handle)` in its own visibility callback
field. That bound argument retains the RefCounted handle, forming a self-cycle.
The handle in turn owns its small bound cache. Explicit scene unload already
called adapter.clear(), disconnected signals and cleared the Callable, and the
8-output unload probe had zero ObjectDB leaks. Normal application exit stopped
the receiver but omitted that retirement path. Application `_exit_tree()` now
resets the light apply service while Nodes still exist, invoking the same proven
cleanup. It does not add blind Node frees or free engine-owned objects.

The same 8-output application shutdown with pre-dense GDScript revision
`bd354a5` did not report this ObjectDB leak, using the same pinned engine and
retained native extension for a controlled script-ownership comparison. Thus this
specific self-cycle belongs to the dense bridge, not an established older leak.
The exact Windows count is reproduced, but the canonical Windows exit should
still be checked after updating. No playback-performance attribution is made.

Verbose logs also show a small fixed set of orphan StringNames for extension
class names in both the pre-dense comparison and corrected runtime. These are
not the ObjectDB-instance warning and do not scale with outputs. No application
code attempts to free engine/native-binding class internals.

## Scene ownership audit

| Owner | Retained objects and retirement | Evidence/action |
| --- | --- | --- |
| Fixture/scene registry | Weak fixture refs plus scene paths; scene clear removes entries; one-shot exit connections belong to fixture Nodes | Load/unload/reload test retires old Nodes; no independent Node owner added |
| Dense adapter/service | Native generation, typed output/material/light handles, bound signatures and visibility Callables | Reset on binding replacement, scene unload and now application exit; weak service back-reference; required install failure rejects playback |
| Beam renderers | MeshInstance children belong to light Nodes; materials/meshes belong to Nodes and scene caches | Renderer cache reset at scene clear; tree destruction releases scene children; weak probes cover generated mesh/material resources |
| Lens material cache | Registry records bind per-geometry prepared materials | Manifest/scene retirement clears registry and service handles; test observes material release and empty lens cache |
| Gobo/projector resources | Scene asset/composition/motion refs and optional generated children | Scene reset clears logical/resource caches; Node children free with tree; native Object vectorizer has explicit owner destruction; selected textures retire in weak probes |
| Collision/picking | CollisionShape Nodes and their shape Resources belong to imported fixture trees | Generated GLB lens test captures weak Node/shape refs and verifies retirement |
| Runtime/import storage | Application owns native loader Object; native active-scene storage retains extracted assets while needed | Existing PREDELETE frees loader; reload replaces native scene; existing native asset-lifetime tests remain authoritative; test verifies loader destruction |
| Import asset cache | Mesh/PackedScene/material refs and failed-path entries are scene scoped | Explicit scene clear empties maps; resource Nodes release with tree |
| Signal/UI services | Node-bound Callables do not own Node lifetime; dense handle-bound callback was the actual RefCounted cycle | Fix only proven dense cycle; no blind freeing of UI/service/engine resources |

Fixed shared renderer shader/topology resources are bounded renderer-lifetime
resources, not one retained object per DMX snapshot. Tests exclude intentionally
shared shader objects from scene-only weak-release assertions.

## Legacy presentation classification

Searches cover production scripts, tests, reflective method strings and section
callers. Zero trace counts alone were not used as evidence of dead code.

| Candidate | Classification / action |
| --- | --- |
| Universal fixed-row `apply_visual_frame_to_fixture`, its row constants and private row-lighting/gobo helpers | No caller remains; the section applier forbids reconstructing that row. Removed together with now-unreferenced private leaves |
| Old fixture-wide `apply_wheel_selection` / `apply_wheel_motion` helpers and gobo state setters/getters | No caller remains; current production sections use identified wheel/gobo state APIs. Removed |
| `record_beam_update` / `record_gobo_update`, unused fixture-state setters/material getter | Definition-only references; removed |
| Adapter `synchronize_visibility` and post-delegation caller | Bound lights return through apply_light_state first; unbound lights have no adapter handle to synchronize. Removed the no-op bridge |
| Lens callback pointing to nonexistent loader `_is_emitter_lens_mesh` | Invalid callback never executed; registry's existing fallback remains. Removed registration |
| `_snapshot_output_commits`, `_target_states`, `_committed_output_states` and commit signatures | Still used by explicit unbound compatibility API regressions; retained. Normal native snapshots now return immediately after dense apply and cannot run legacy coalescing/accounting |
| `_beam_optics_signatures`, `_light_desired_state`, `_material_state_by_rid`, `_visible_*_ids` | Retained for manual/standalone unbound presentation and compatibility API calls. Dense bound lights delegate to the adapter; these sets do not provide production visibility gauges |
| Diagnostic warning/info maps | Retained for bounded wheel metadata, warnings and compatibility angle state; no universal fixed-row authority remains |
| Native generation/dirty masks versus renderer applied signatures | Both required: native state decides control/render deltas, while resource signatures guard actual retained renderer setters. Not duplicate authoritative state |

The remaining Dictionary lighting API may execute for explicit manual fixture
controls or callers/tests without dense bindings. It is **not an error fallback**
when production dense installation fails. Production Intensity/Color/BeamOptics
use native compose plus indexed handles; the section applier still bypasses the
legacy APIs. Retired cache reset is shared across both paths. The legacy-only soak
now explicitly retires its empty dense test installation before testing unbound
calls, making its ownership boundary honest.

Legacy collection sizes are reported under `legacy_compatibility`, not as normal
dense state sizes. Old broad-helper `beam_full*`/topology counters remain available
to direct compatibility callers but are omitted from the production compact
report. Genuine initialization, mesh replacement and setter counts come from the
dense block. Dense apply no longer resets visible counts from empty legacy sets;
controller sampling precedes its own report.
