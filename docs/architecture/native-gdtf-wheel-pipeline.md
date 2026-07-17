# Native GDTF color-wheel pipeline

Peraviz now reserves the wheel runtime contract for native-authoritative GDTF wheel state instead of the earlier generic gobo placeholder routing. The intended data flow is GDTF/MVR parsing, immutable native wheel resources, compiled target bindings, native DMX interpretation, compact setup palettes, and renderer deltas consumed by Godot without GDTF parsing.

## Protocol v2.1 wheel rows

`WheelSelection` is renderer metadata for native wheel optical state. Its integer fields are `fixture_id`, exact `beam_render_target_id`, `wheel_renderer_id`, `mode`, `slot_a`, `slot_b`, `changed_mask`, and `revision_flags`. Its float fields are `normalized_phase`, `split_fraction`, `boundary_angle_degrees`, aggregate nonlinear sRGB RGB, `aggregate_gain`, and `edge_softness`. The authoritative uniform renderer color is the final composed `EmitterColor` row for the Beam; `WheelSelection` must not overwrite that color in Godot.

`WheelMotion` is a sparse synchronization row. Its integer fields are `fixture_id`, exact `beam_render_target_id`, `wheel_renderer_id`, `motion_mode`, `changed_mask`, and `revision`. Its float fields are authoritative phase, angular velocity in degrees per second, monotonic reference seconds, and random frequency in hertz.

Snapshots with stale protocol or schema generations are rejected by the sectioned visual-frame validator.

## Angle convention and PlacementOffset

Peraviz uses a clockwise normalized wheel phase where `phase = normalize_degrees(physical_degrees + PlacementOffset) / 360`. Slot sectors are equal nominal sectors in declared one-based slot order. For `N` slots, `sector_degrees = 360 / N`; `floor(phase * N)` selects slot A and the next cyclic slot is slot B. The fractional part is the spatial split fraction. This keeps negative, descending, and multi-turn physical ranges representable before the runtime evaluates the final physical angle.

The default `PlacementOffset` remains 270 degrees only when the standard attribute definition supplies that default; fixture-authored sub-physical units can override it. Zero degrees is not treated as Open or slot 1 by name.

## Renderer ownership and approximation

Godot receives cooked palette references and row deltas only. It does not resolve ChannelSets, parse GDTF, convert CIE values, interpret filters, or calculate physical ranges. Spatial split rendering is documented as `PeravizWheelCoverageApproximation`: a circular-aperture-safe chord mask with the same orientation on the lens and volumetric beam. `SpotLight3D` uses the provided aggregate cooked linear result because it cannot represent a spatial split.

Spin rows are emitted only on activation, speed changes, stop, resync, and scene reinstall. Godot may advance local phase from the native phase, angular velocity, and monotonic elapsed time. Random selection is native-authoritative, deterministic, seeded from fixture identity, wheel ID, and activation revision, and emits only when the selected slot changes. `Color(n)WheelAudio` is recognized as unsupported metadata and must not start audio capture or implicitly fall back to Random.

## Seated selection vertical slice

The production vertical slice currently supports seated discrete `Color(n)` selection with standard DMXFrom-only ChannelSet ranges inferred from the next ChannelSet and parent ChannelFunction range. The parser records ordered one-based wheel slots and exact `ChannelFunction.Wheel` / `ChannelSet.WheelSlotIndex` metadata. The runtime scene compiler cooks immutable palette slots, binds the color-wheel source to exact Beam render-target IDs, serializes palettes and bindings through the packed scene bridge, and installs only valid bindings as universe interests. Runtime DMX changes update one persistent layer in the Beam target's ordered wheel stack, emit sparse `WheelSelection` metadata for changed wheels, and recompose the exact Beam once into one final `EmitterColor` row when the uniform output changes. Godot resolves the exact Beam output record for `EmitterColor` and stores wheel metadata for future spatial split rendering without applying it as a second color authority.

Indexed `Color(n)WheelIndex` now preserves native adjacent slots, phase and split fraction and uses `PeravizIndexedWheelAggregateFallback`, a temporary non-spatial linear aggregate for renderer domains that cannot yet display a spatial split. Final spatial split shaders/lens masks, local spin animation, deterministic native random scheduling, and palette registry resources beyond the packed row data remain future work. Audio remains unsupported and must not fall back to Random.

The seated and aggregate-indexed paths keep native base color, per-wheel optical layers, and final wheel-filtered output separate: base color is cooked in linear RGB with gain, wheel slots provide bounded linear transmission shape plus a separate scalar transmission gain, and final renderer sRGB/gain is encoded once after ordered linear multiplication. Multiple wheels on the same Beam accumulate instead of overwriting. Filter ColorCIE Y or Measurement.Transmission supplies scalar energy exactly once; measurement spectra are used only as relative chromatic shape unless calibrated absolute data is added later. Packed runtime-scene contract version 3 preserves Color input Emitter/Filter resource IDs across the Godot bridge.


## Peraviz visual response

Physical wheel gain remains the native optical output. Godot applies a separate `PeravizBeamVisualResponse` only to volumetric beam presentation so small positive filter output stays legible in haze while SpotLight and lens energy continue to use physical gain. The response is monotonic, maps 0 to 0 and 1 to 1, and is not physical photometry. Final dual-sided spatial rendering is still deferred.
