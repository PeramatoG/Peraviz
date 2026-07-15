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

## Seated selection vertical slice

The production vertical slice currently supports seated discrete `Color(n)` selection with standard DMXFrom-only ChannelSet ranges inferred from the next ChannelSet and parent ChannelFunction range. The parser records ordered one-based wheel slots and exact `ChannelFunction.Wheel` / `ChannelSet.WheelSlotIndex` metadata. The runtime scene compiler cooks immutable palette slots, binds the color-wheel source to exact Beam render-target IDs, serializes palettes and bindings through the packed scene bridge, and installs only valid bindings as universe interests. Runtime DMX changes emit `WheelSelection` rows with slot A and B equal to the selected seated slot. Upstream native `EmitterColor` changes for the same exact Beam target also invalidate dependent seated wheel bindings so the final wheel-filtered result is re-emitted after the upstream color row. Godot resolves the exact Beam output record and mutates SpotLight, Lightweight Prism beam shader parameters, and lens/emissive material state through the same target-local render path used by native color and dimmer updates.

Indexed split, local spin animation, deterministic native random scheduling, palette registry resources beyond the packed row data, and spatial split shader/lens masks remain future work. Audio remains unsupported and must not fall back to Random.

The seated path keeps native base color and final wheel-filtered output separate: base color is cooked in linear RGB with gain, wheel slots provide bounded linear transmission shape plus a separate scalar transmission gain, and final renderer sRGB/gain is encoded once after linear multiplication. Filter ColorCIE Y or Measurement.Transmission supplies scalar energy exactly once; measurement spectra are used only as relative chromatic shape unless calibrated absolute data is added later. Packed runtime-scene contract version 3 preserves Color input Emitter/Filter resource IDs across the Godot bridge.
