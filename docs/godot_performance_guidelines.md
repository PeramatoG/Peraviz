# Godot performance guidelines for Peraviz

## Purpose

This document captures the Godot-specific rules Peraviz should follow to stay suitable for real-time lighting visualization.

## Baseline assumptions

- Peraviz has many fixtures whose state can change at the same time.
- Camera movement may remain smooth even when fixture updates stutter, which suggests the bottleneck can be data processing, marshaling, synchronization, or scene-tree updates rather than raw GPU polygon load.
- Godot should be treated as the rendering/client layer. Native C++ should prepare the data that Godot applies visually.

## Measure first

Godot's own performance documentation emphasizes measuring bottlenecks with timing, Godot profiler, external CPU profilers, external GPU profilers, and frame-rate checks. Peraviz changes that claim to improve performance should include a small before/after note when practical.

Recommended profiling buckets:

```text
receive -> decode -> resolve -> snapshot -> transfer -> apply -> render
```

## Avoid scene-tree churn in live playback

During live data playback:

- Do not create/delete large numbers of nodes per frame.
- Do not repeatedly traverse the scene tree to find fixtures.
- Do not duplicate materials or meshes per fixture unless unavoidable.
- Do not parse strings, XML, fixture definitions, or protocol packets in `_process()`.
- Cache references and update only dirty visual elements.

## Prefer batched rendering data

Use a native-side frame snapshot or update buffer. The Godot side should apply compact render-ready state, not raw DMX packets.

Good live path:

```text
C++ resolves all changed fixtures -> Godot receives one snapshot/update buffer -> Godot applies dirty updates
```

Bad live path:

```text
Godot receives raw packet/channel updates -> Godot searches fixtures -> Godot resolves attributes -> Godot updates nodes one by one
```

## Use shared resources and instancing

For repeated fixture models and repeated submeshes:

- Share mesh resources.
- Share material resources where possible.
- Use per-instance transforms and shader parameters instead of duplicating geometry.
- Evaluate `MultiMeshInstance3D` for repeated identical geometry.
- Split MultiMeshes by fixture type, visibility region, or update behavior when needed.

Godot documents MultiMesh as a very efficient way to draw many instances with low API overhead, but it also has all-or-none visibility limitations per MultiMesh. Use several MultiMeshes when culling granularity matters.

## Consider RenderingServer carefully

Godot's `RenderingServer` can bypass the scene/node system and may improve performance when the scene system is the bottleneck. This should be considered for very large batches or hot update paths, but only after profiling confirms the scene system or node overhead is the issue.

## Threading rules

Godot supports multithreading, but not all engine APIs are safe from all threads.

Peraviz rules:

- Native worker threads may receive, decode, resolve, and prepare snapshots.
- Worker threads must not directly mutate active Godot scene nodes.
- Scene updates should be applied from the main thread or through Godot-safe deferred mechanisms.
- Keep mutex locks short.
- Create worker threads during startup/loading rather than just-in-time during playback.
- Avoid GPU-facing resource creation or texture/image modification from worker threads unless the specific API path is verified as safe and measured.

## GDExtension / native integration

GDExtension allows native shared libraries to interact with Godot at runtime without recompiling the engine. For Peraviz, the native extension should be used as the high-performance bridge between the C++ data pipeline and the Godot client layer.

Bridge expectations:

- Few batch calls, not thousands of tiny calls.
- Stable IDs and compact buffers.
- Minimal Variant/object churn.
- Explicit ownership and lifetime rules.
- No direct Godot scene mutation from native worker threads.

## Shader and GPU-friendly work

Where suitable:

- Move repeated simple visual calculations into shaders.
- Use instance custom data or texture buffers for large repeated visual sets.
- Avoid per-frame shader/material creation.
- Warm up or pre-load shader/material paths that would otherwise cause live stutter.

## References

- Godot performance index: https://docs.godotengine.org/en/stable/tutorials/performance/index.html
- General optimization tips: https://docs.godotengine.org/en/stable/tutorials/performance/general_optimization.html
- Thread-safe APIs: https://docs.godotengine.org/en/stable/tutorials/performance/thread_safe_apis.html
- Using multiple threads: https://docs.godotengine.org/en/stable/tutorials/performance/using_multiple_threads.html
- RenderingServer: https://docs.godotengine.org/en/stable/classes/class_renderingserver.html
- Optimization using MultiMeshes: https://docs.godotengine.org/en/stable/tutorials/performance/using_multimesh.html
- GDExtension system: https://docs.godotengine.org/en/stable/tutorials/scripting/gdextension/index.html

## Native realtime pump

Normal playback must configure the receiver from the native compiled visual runtime and call the native coordinator pump once per frame. It must not consume raw universe `PackedByteArray` values, hash them, or cache them in GDScript. Dirty work is handed off through a bounded generation-tagged ID ring rather than a patched-universe scan. Technical Monitor payload capture is a fresh, budgeted diagnostic session; when its four-captures-per-drain and one-per-millisecond allowance is exhausted, payload fidelity is skipped before scene reception is delayed.

## Live DMX latency tracing

Start Peraviz with `--peraviz-perf-trace` after Godot's `--` application-argument separator. The compact once-per-second line reports transport and CPU RX-to-apply histograms beside FPS, process time, objects, primitives, draw calls, node/resource counts, production pump cadence, row outcomes, and renderer mutation counters. The trace is disabled by default and its histogram values are bounded approximations, not GPU-presentation measurements.

On a Windows GPU, compare the normal run with Godot's `--disable-vsync`, a controlled `--max-fps`, `--print-fps`, and `--gpu-profile` options. Do not infer a GPU bottleneck from fan speed alone; compare CPU RX-to-apply age, FPS, draw calls, and the GPU profile.

Diagnostic render modes are runtime-only A/B controls. `transforms-only` isolates target motion from lighting apply cost, while `no-beams` preserves held lighting state and emissive geometry but suppresses projected-beam work. Neither mode changes saved visual preferences. Use the interval mutation counters rather than outputs-considered counts when evaluating CPU renderer cost.
