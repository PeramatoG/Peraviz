# Peraviz architecture

## Goal

Peraviz is a real-time lighting visualizer built around a native C++ data pipeline and a Godot rendering/client layer. The architecture should minimize latency between incoming lighting data and the rendered scene.

## Core principle

C++ prepares what Godot needs to draw. Godot should not perform heavy fixture, protocol, or patch calculations at frame rate.

## Runtime pipeline

```text
Art-Net / sACN / DMX input
    -> packet receiver
    -> universe filter
    -> patch lookup
    -> fixture attribute resolver
    -> state interpolation / smoothing
    -> dirty fixture/submodel ranges
    -> render-ready frame snapshot
    -> Godot bridge
    -> Godot scene/resource update
    -> renderer
```

## Native C++ layer

The native layer owns the high-frequency data path:

- Network/protocol receiving.
- Universe filtering and ignoring unused universes.
- Fixture patch mapping.
- GDTF/MVR-derived fixture model and attribute data.
- DMX channel decoding.
- Attribute resolution: dimmer, color, pan, tilt, zoom, focus, iris, gobo, prism, shutter, strobe, etc.
- Interpolation, smoothing, inversion, and normalization.
- Dirty flags and frame coalescing.
- Frame snapshots or compact update buffers.
- Profiling counters for receive/decode/resolve/transfer/apply phases.

### Native design rules

- Prefer data-oriented layouts for hot paths.
- Avoid per-channel/per-fixture heap allocation during live playback.
- Avoid string parsing and dictionary lookup in the live path once patch data is resolved.
- Use stable numeric IDs for fixtures, subfixtures, models, mesh parts, and attributes.
- Use double buffering or lock-free queues for cross-thread handoff where practical.
- Keep locks short and never hold locks while calling into Godot.

## Godot layer

The Godot layer owns the visual/client side:

- Scene setup and user interaction.
- Camera and viewport behavior.
- Mesh, material, shader, beam, atmosphere, and post-processing setup.
- Applying prepared transforms, colors, intensities, and visibility values.
- Reusing visual instances and shared resources.

### Godot design rules

- Do not parse Art-Net, sACN, DMX, GDTF, or MVR data in frame callbacks unless the task is explicitly UI/import related and not part of live playback.
- Avoid high-frequency `get_node()` searches, dynamic node creation, dynamic material duplication, or large tree traversals during live updates.
- Prefer cached node/resource references.
- Apply changes in batches and skip unchanged fixtures.
- Prefer `MultiMeshInstance3D`, `RenderingServer`, shared meshes, shared materials, and shader-side work when rendering many repeated elements.

## C++/Godot bridge

The bridge should be intentionally narrow. It should expose prepared data to Godot using a small set of batch-oriented calls.

Preferred API shape examples:

```text
initialize_scene(static_scene_description)
load_fixture_models(model_table)
apply_frame_snapshot(frame_snapshot)
apply_fixture_updates(update_buffer)
get_diagnostics_snapshot()
```

Avoid APIs shaped like this in the live path:

```text
set_fixture_channel(fixture_id, channel, value)
set_pan(fixture_id, value)
set_tilt(fixture_id, value)
set_color_r(fixture_id, value)
set_color_g(fixture_id, value)
set_color_b(fixture_id, value)
```

The second style creates too many calls, too much marshaling, and too much opportunity for scene-tree churn.

## Frame snapshot expectations

A frame snapshot should be compact and render-oriented. It may include:

- Frame index and timestamp.
- Dirty fixture ranges or dirty fixture IDs.
- Fixture root transforms.
- Head/yoke/beam transforms.
- Dimmer/intensity values.
- RGB/CMY/CTO/color-wheel resolved output.
- Beam cone/zoom/frost/iris parameters.
- Gobo/prism/strobe/shutter state.
- Material or shader parameter indices.

The snapshot should not require Godot to perform protocol-level decoding.

## Performance diagnostics

Maintain counters for at least:

- Packet receive time.
- Packet queue depth.
- Universe decode time.
- Fixture state resolve time.
- Dirty fixture count.
- Snapshot build time.
- C++/Godot transfer time.
- Godot apply time.
- Render frame time.

These counters make it possible to distinguish render cost from data-processing latency.

## Documentation update triggers

Update this document when changing:

- Native module ownership.
- Godot responsibilities.
- Bridge API or frame snapshot layout.
- Threading model.
- Supported protocol/import behavior.
- Any performance strategy that changes the live data path.
