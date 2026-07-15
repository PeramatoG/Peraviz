# Native GDTF color-wheel pipeline

Peraviz now reserves the wheel runtime contract for native-authoritative GDTF wheel state instead of the earlier generic gobo placeholder routing. The intended data flow is GDTF/MVR parsing, immutable native wheel resources, compiled target bindings, native DMX interpretation, compact setup palettes, and renderer deltas consumed by Godot without GDTF parsing.

## Protocol v2.1 wheel rows

`WheelSelection` is a renderer-ready optical state row. Its integer fields are `fixture_id`, exact `beam_render_target_id`, `wheel_renderer_id`, `mode`, `slot_a`, `slot_b`, `changed_mask`, and `revision_flags`. Its float fields are `normalized_phase`, `split_fraction`, `boundary_angle_degrees`, aggregate nonlinear sRGB RGB, `aggregate_gain`, and `edge_softness`.

`WheelMotion` is a sparse synchronization row. Its integer fields are `fixture_id`, exact `beam_render_target_id`, `wheel_renderer_id`, `motion_mode`, `changed_mask`, and `revision`. Its float fields are authoritative phase, angular velocity in degrees per second, monotonic reference seconds, and random frequency in hertz.

Snapshots with stale protocol or schema generations are rejected by the sectioned visual-frame validator.

## Angle convention and PlacementOffset

Peraviz uses a clockwise normalized wheel phase where `phase = normalize_degrees(physical_degrees + PlacementOffset) / 360`. Slot sectors are equal nominal sectors in declared one-based slot order. For `N` slots, `sector_degrees = 360 / N`; `floor(phase * N)` selects slot A and the next cyclic slot is slot B. The fractional part is the spatial split fraction. This keeps negative, descending, and multi-turn physical ranges representable before the runtime evaluates the final physical angle.

The default `PlacementOffset` remains 270 degrees only when the standard attribute definition supplies that default; fixture-authored sub-physical units can override it. Zero degrees is not treated as Open or slot 1 by name.

## Renderer ownership and approximation

Godot receives cooked palette references and row deltas only. It does not resolve ChannelSets, parse GDTF, convert CIE values, interpret filters, or calculate physical ranges. Spatial split rendering is documented as `PeravizWheelCoverageApproximation`: a circular-aperture-safe chord mask with the same orientation on the lens and volumetric beam. `SpotLight3D` uses the provided aggregate cooked linear result because it cannot represent a spatial split.

Spin rows are emitted only on activation, speed changes, stop, resync, and scene reinstall. Godot may advance local phase from the native phase, angular velocity, and monotonic elapsed time. Random selection is native-authoritative, deterministic, seeded from fixture identity, wheel ID, and activation revision, and emits only when the selected slot changes. `Color(n)WheelAudio` is recognized as unsupported metadata and must not start audio capture or implicitly fall back to Random.
