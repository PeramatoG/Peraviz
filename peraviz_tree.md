# peraviz_tree.md

This file describes the intended module ownership for Peraviz. Keep it updated whenever files or responsibilities move.

## Root-level structure

```text
Peraviz/
├── AGENTS.md
├── CMakeLists.txt / SConstruct / native build files
├── godot/                         # Godot project, scenes, scripts, materials, shaders, UI.
├── native/                        # C++ real-time data pipeline and Godot integration.
├── third_party/                   # Vendored dependencies only when unavoidable.
├── docs/                          # Architecture, performance, protocol, and developer docs.
├── tests/                         # Small architecture/build/quality checks.
├── tools/                         # Developer scripts that are not runtime code.
└── README.md
```

If the repository currently uses different names, update this tree to match the real layout before relying on automated checks.

## Native C++ ownership

```text
native/
├── bridge/                        # Narrow Godot/C++ integration layer.
├── protocol/                      # Art-Net, sACN, DMX receiving and packet decoding.
├── patch/                         # Universe, address, fixture, and channel mapping.
├── fixture/                       # Fixture definitions, GDTF-derived data, attributes.
├── simulation/                    # Resolved fixture state, interpolation, dirty flags.
├── render_data/                   # Compact frame snapshots and GPU/client-ready buffers.
├── threading/                     # Queues, double buffers, worker lifecycle, synchronization.
├── diagnostics/                   # Timers, counters, profiling markers, debug snapshots.
└── platform/                      # OS-specific sockets, timing, filesystem, or library glue.
```

### Native rules

- Protocol-level input and high-frequency fixture-state calculations belong here.
- Keep data structures compact, predictable, and cache-friendly.
- Prefer batched frame snapshots and dirty ranges over per-fixture callback storms.
- Keep platform-specific code behind interfaces.

## Godot ownership

```text
godot/
├── project.godot
├── scenes/                        # Main scene, viewer scene, UI scenes.
├── scripts/                       # Thin rendering/client scripts only.
├── materials/                     # Shared materials and shader materials.
├── shaders/                       # Beam, atmosphere, color, gobo, and instancing shaders.
├── meshes/                        # Imported or generated mesh resources.
├── assets/                        # Icons, images, and static application assets.
└── addons/                        # Godot plugins/addons, if any.
```

### Godot rules

- Godot scripts should apply prepared data; they should not parse protocols or resolve raw DMX.
- Avoid per-frame scene-tree searches and per-frame node creation/deletion.
- Reuse nodes/resources and update transforms/material parameters in batches.
- Prefer shared meshes/materials and instancing for repeated fixture geometry.

## Documentation ownership

```text
docs/
├── architecture.md                # Overall architecture and data flow.
├── godot_performance_guidelines.md# Godot-specific performance rules.
├── protocol_pipeline.md           # Optional: Art-Net/sACN/DMX ingestion details.
├── fixture_state_pipeline.md      # Optional: DMX to resolved fixture state.
└── profiling.md                   # Optional: profiling counters and workflows.
```

## Test/check ownership

```text
tests/
├── check_peraviz_tree_modules.sh
├── check_no_large_files.sh
└── check_godot_boundary_lightweight.sh
```

## Boundary summary

The preferred runtime flow is:

```text
Network/input packets
    -> native protocol receiver
    -> universe filtering
    -> fixture patch lookup
    -> fixture state resolver
    -> interpolation / smoothing / dirty flags
    -> compact frame snapshot or update buffer
    -> Godot bridge
    -> Godot visual apply step
    -> renderer/GPU
```

Godot must not become the place where raw protocol data is repeatedly converted into fixture behavior during live playback.
