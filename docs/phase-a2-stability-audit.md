# Phase A2: sustained live DMX stability baseline

Audited from `main` revision `1917f42448dc5897853f5f557bfc8c61c44cd49d`.
This revision already reports `color_rows`, `color_dirty`, and
`[peraviz-color-dirty]`. The older supplied trace predates that contract.
No ControlGroup, RenderGroup, RenderEmitterGrouping, batching, protocol, or GDTF
capability is implemented by this investigation.

## Evidence and classification

The supplied observation has approximately constant nodes, resources, physical
outputs, rows, draws, and visible beams while process time rises from roughly
137 ms to 400 ms. Emitter commit time rises much less (roughly 58 to 65–73 ms).
Neither this discrepancy nor high mailbox coalescing proves a leak or a GPU
bottleneck. Process/apply/render timings overlap and must not be subtracted as
if they formed an exclusive profiler timeline.

Inspection found actual accumulation in repeated short-payload diagnostics and
several scene/presentation lifecycle paths. These have been corrected and tested.
They are **not established as the cause of the canonical sustained-playback
slowdown**: the short-payload case requires missing compiled source bytes, and
the lifecycle cases require replacement/cleanup, rather than fixed-scene color
and intensity playback. Deterministic native and headless presentation soaks
show stable state sizes after warmup. An RTX/Forward+ run with real Art-Net is
still required to classify the unexplained frame time.

## Ownership audit

| Structure/path | Bound and lifetime | Finding/action |
| --- | --- | --- |
| Realtime mailbox dirty tokens | Fixed 32,768-token ring; at most one pending token per currently subscribed universe | Coalesces changed held states. Subscription replacement retires old tokens; stop now also invalidates pending and held session input while retaining interests. |
| Mailbox held slots | One slot per universe ever subscribed, at most the Art-Net domain of 32,768 | Intentionally retained for receiver lifetime; not one allocation per packet. Current slots, bytes, subscription size, pending count and high-water are exposed. |
| Art-Net metadata, sequence tracking, monitor payload cache | One entry per observed universe, at most 32,768; monitor capture has fixed per-drain/time budgets | Universe-keyed, not sender- or DMX-value-keyed. Active ID lists append only on initial slot allocation. Network/monitor cache byte estimate excludes mailbox, which has its own estimate. |
| Receiver latency statistics | Three pairs of fixed 32-bucket histograms | No sample list. Lifetime resets at receiver start; trace interval resets only when consumed by the reporter. Status reads do not consume it. Main-thread owned; no new RX mutex. |
| Native universe/latest frames | Installed universe IDs; each payload at most 512 bytes | Submissions replace held bytes. Pending flags clear on consume. No retained visual-frame history. |
| Native dirty target sets and section buffers | Local to one consume operation, bounded by installed dependencies/targets | Released on return. Frame descriptors, integers and floats cross into Godot once, then are released. |
| Native transform/property/color/wheel/gobo maps | Compiled fixture/property/physical output/wheel/layer IDs | Reuse stable IDs and reset on native scene installation/clear. New trace snapshot reports sizes and payload capacity. |
| Native diagnostic vector | Setup diagnostics plus runtime warning categories | **Unbounded before fix:** missing bytes could append warnings on every evaluation. Each installed source program now records each byte-warning category once, retaining the diagnostic and existing zero-fill behavior. `clear()` also clears diagnostics. Ambiguous gobo warnings were already deduplicated by physical layer. |
| `_snapshot_output_commits` | One entry per touched stable output ID in the current snapshot | Cleared on begin and after commit. Intensity/color nominations coalesce. Trace-only peak sampled once before snapshot drain. |
| `_target_states`, `_committed_output_states` | Stable physical output/target IDs | Steady playback is bounded by scene size. **Stale before fix:** service survived binding/scene replacements without retirement. Cleared at native manifest install and scene clear; new native generation rehydrates held receiver state. |
| `_beam_optics_signatures`, `_light_desired_state`, `_material_state_by_rid` | Renderer object ID or material RID | Bounded for a fixed scene; previously retained obsolete IDs across replacement. Retired with the apply service's scene state. |
| `_visible_beam_ids`, `_visible_light_ids` | Current light identities | Visibility transitions insert/erase; scene/binding retirement now clears sets and current-count gauges. |
| Diagnostic warning/info dictionaries | Fixed category or stable target/layer plus category | Values are overwritten, not appended per DMX value. Retired with apply-service state. |
| Native renderer target/resource registry | Installed manifest identities; lens materials per geometry | Target maps already clear on manifest rebuild. Logical gobo state intentionally survives presentation-only target rebind and is rehydrated; true scene clear resets it. |
| Native gobo asset/composition caches | Scene media IDs and ordered static slot combinations | Finite for an installed scene; can warm as previously unseen combinations are selected. Moving/index-angle-dependent compositions are not cached. Scene reset clears assets, composition and mesh caches. |
| Gobo vectorization helper Objects | One native Object per helper owner | **Leaked before fix:** `PeravizGoboVectorizer` derives from Object, not RefCounted. Both owning GDScript helpers now free it at destruction. The load-scene owner likewise frees its native Object loader. |
| Beam renderer mesh caches | Normalized topology/media identity; legacy aperture shape/range | Live color/intensity uses existing resources; no DMX-color cache keys. **Stale before fix:** shape caches could survive scene reload and retain previous media/topology. Scene retirement now clears both renderers' scene caches. |
| Shader proxy allocation/visibility/tier sets | One entry per physical light using a proxy | **Stale before fix:** renderer cleanup only hid proxies. Cleanup now destroys the old proxy and retires IDs; scene reset clears registries. Shared fixed mesh/shader/material remain reusable. |
| Beam/fog/projector resources | Beam/light node metadata; shader proxy shares fixed topology; projector media cache scoped to scene | Steady intensity/color mutate parameters. Topology/media changes may legitimately allocate resources. Existing creation/write counters plus mesh/registry sizes distinguish warmup from repeated recreation. Scene children own nodes; scene import already clears projector textures. |
| Beam parameter templates | Explicit `BEAM_PARAMS_TEMPLATE_CACHE_LIMIT` | Already capped, including keys involving optical values. Defaults are a fixed dictionary. |
| Deferred/message queue work | No per-packet deferred scene application | RX does not call Godot nodes. `queue_free()` is used for lifecycle/topology changes, not a packet backlog. Godot exposes message-buffer high-water, not current pending-call depth through this monitor. |
| Trace interval, previous snapshots and print payloads | Fixed counter/domain names; one last snapshot per category | `_perf_interval` clears after every report; previous snapshots are replaced. Idle applies now preserve the previous valid counters instead of replacing them with empty dictionaries. JSON/print payloads are local, not saved in memory. Console/file log storage remains external to runtime collection ownership. |

The trace size high-waters are reporting-boundary samples, except the exact
snapshot-commit peak and mailbox token high-water. They do not prove there were
no transient allocations between samples. Godot allocator/driver retention can
raise memory without growing a tracked collection. A fixed scene is expected to
stabilize after its media/topology warmup, not necessarily on its first frame.

## Automated regressions

The existing native visual-runtime executable now also runs:

- 120,000 latest-state publications across three fixed universes with repeated
  drains and generation replacement, checking every universe's latest/held bytes,
  pending count, coalescing and slot high-water;
- fixed histogram reset, empty interval, slow-after-fast interval/lifetime
  separation and trace-OFF interval suppression;
- 2,000 native snapshots with 50 physical color outputs sharing a source,
  bounded frame/state sizes, no leftover dirty frame and repeated native rebuild;
- 9,000 short-payload evaluations over three generations, proving warning count
  and capacity stabilize while warnings remain present.

`test_realtime_presentation_stability.gd` runs 512 changing snapshots for each of
three binding generations, with 51 physical outputs sharing control authority,
including an emission-only output and per-output lens materials. It checks
snapshot clearing, stable state-map and resource identities, latest held color,
trace ON/OFF behavior, actual manifest-install retirement, native Object cleanup,
renderer mesh-cache retirement, proxy cleanup, and bounded diagnostic snapshots.
Headless CPU/GPU timing may be zero. The existing coalescing test shares the same
synthetic loader fixture. These are bounded regressions, not CI benchmarks.

See [Live render latency diagnostics](live-render-latency-diagnostics.md) for the
trace schema, exact Windows commands and the remaining hardware experiment.
