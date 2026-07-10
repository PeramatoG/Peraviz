# GDTF gobo index, rotation, and shake mapping in Peraviz

This note summarizes the GDTF attributes used for gobo wheel control and
how they are mapped into Peraviz DMX runtime controls.

## GDTF reference used

Use the official GDTF specification as the reference for this implementation.
The relevant attributes are:

- `Gobo(n)` for wheel slot selection.
- `Gobo(n)Pos` for indexed gobo angle.
- `Gobo(n)PosRotate` for continuous gobo rotation speed/direction.
- `Gobo(n)SelectShake` or dedicated shake attributes for gobo shake behavior.

## Runtime mapping

Peraviz exposes gobo controls when present in the fixture mode:

- `gobo_*` for slot selection.
- `gobo_index_*` for indexed angle.
- `gobo_rotation_*` for continuous rotation.
- shake metadata (`supports_shake`, `shake_active`, `shake_amplitude_deg`,
  `shake_frequency_hz`) per wheel when shake-capable functions are detected.

For multi-wheel fixtures, each wheel in `gobo_wheels` also includes:

- `index_*` channels.
- `rotation_*` channels.
- shake ranges tied to parsed DMX windows.

When the GDTF channel functions define `PhysicalFrom`/`PhysicalTo`, those
limits are propagated for index/rotation and shake interpretation when
available. Runtime uses these physical ranges to interpret values with
fixture-accurate behavior instead of a generic normalization.

## Control interpretation in Godot

Peraviz runtime applies gobo controls with this behavior:

1. Base rotation from visual settings.
2. If `gobo_index`/`index` is present (`Gobo(n)Pos`), map DMX value to a
   **fixed angular position** relative to initial orientation.
3. If `gobo_rotation`/`rotation` is present (`Gobo(n)PosRotate`), map DMX value
   to **angular speed** (including direction) and integrate over time.
4. If shake is active, apply shake as an **additional tilt modulation layer**
   on top of the resulting rotation.

Shake is therefore **not mutually exclusive** with rotation:

- Rotation defines the wheel spin/index orientation over time.
- Shake adds oscillation amplitude/frequency on top of that state.

## Shake control priority

Per-wheel shake source priority is:

1. **Dedicated shake channel** (highest priority).
2. **Same-channel select-shake window** (`Gobo(n)SelectShake`).
3. **Fallback** from rotation speed (frequency inferred from
   `abs(rotation_speed_deg_per_sec) / 360.0` if no explicit shake frequency is
   available).

Debug override behavior:

- Debug override affects shake only when explicitly enabled in debug controls.
- If debug override is disabled (or running in non-debug builds), runtime uses
  fixture/runtime shake sources only.

## Real fixture example: `Robin MegaPointe.gdtf`

The fixture file `library/fixtures/Robin MegaPointe.gdtf` provides a concrete
same-channel select-shake example:

- `Gobo1SelectShake` appears on one DMX channel and defines select-shake windows
  (for static gobo shake selection).
- `Gobo2SelectShake` appears on one DMX channel with separate windows for
  shake-index and shake-rotation behavior.

Observed DMX windows (8-bit values) in the provided fixture modes:

- `Gobo1SelectShake` starts at `88` with slot windows stepping by `8`
  (`88..95`, `96..103`, ...).
- `Gobo2SelectShake` shake-index region starts at `60` with slot windows stepping
  by `8` (`60..67`, `68..75`, ...).
- `Gobo2SelectShake` shake-rotation region starts at `130` with slot windows
  stepping by `8` (`130..137`, `138..145`, ...).

In this specific fixture, select-shake windows are the active runtime source;
if a dedicated shake channel existed for the same wheel, it would take
precedence by design.

## Approved operational limits

Peraviz enforces the following shake safety limits at runtime:

- `max amplitude = 1.0º`
- `max frequency = 7.0 Hz`

Any resolved or debug-provided shake values are clamped to these limits before
being applied.

## Live visual-frame path

The active live path uses the native sectioned visual frame described in `docs/architecture.md`. Gobo-related updates are transported as domain-specific section data instead of a universal fixed row. The Godot apply layer treats gobo slot or texture changes as topology-affecting updates and gobo rotation or shake changes as parametric updates. Slot or texture changes are applied before a beam topology rebuild so `peraviz_gobo_texture` is available when fog-beam materials are rebuilt. Rotation and shake updates are applied without forcing texture recomposition unless the active slot or composed texture changes.

This remains a transitional bridge: static wheel slot data, primary gobo slot data, wheel-only selector channels, and cached GDTF texture metadata are still cached per fixture by the DMX runtime. The live numeric state comes from native cooked runtime sections, while some slot/range metadata remains in Godot compatibility data. The intended next step is to move the remaining slot/range and motion-mode resolution, including independent multi-wheel gobo state, into native compiled runtime data so Godot receives render-ready gobo state instead of consulting cached capability dictionaries.

Diagnostics now distinguish gobo masks, cached controls, resolved slots, texture application, beam consumption, topology updates, parametric updates, texture compositions, and rotation/shake render-state updates. Continuous rotation or shake should update render state from persistent motion parameters and must not require full fixture capability re-application every frame. The current transitional projector still advances some motion only when called; this is documented as a remaining risk until render-state animation is moved into shader/material or compact renderer state.

## Attribute packing protocol direction

GDTF models multi-wheel gobos as indexed attributes such as `Gobo(n)`, `Gobo(n)Pos`, and `Gobo(n)PosRotate`, where `(n)` identifies the controlled wheel. Peraviz therefore treats gobo wheels as independent indexed attribute instances rather than additional bytes inside unrelated attributes such as zoom. The current sectioned visual frame keeps gobo selector, index, and motion data separate from unrelated optics such as zoom. At binding rebuild time, native code reserves all known gobo wheel selector/index/rotation DMX offsets away from zoom packing so these indexed attributes cannot overwrite each other.

The intended native protocol for additional wheels is indexed section data: each entry should carry stable `fixture_id`, `attribute_family`, `instance_index` (for example gobo wheel number), `component` (selector, index, rotation, shake), normalized value, raw value, topology dirty flag, and parametric dirty flag. Godot should consume those records by stable IDs and cached renderer resources, while C++ owns the mapping from GDTF/MVR DMX channels to indexed records. This keeps sender and receiver synchronized as new attributes are added without allowing one attribute's bytes to be interpreted as another attribute.
## Native BeamOptics foundation

Peraviz now starts the first native BeamOptics vertical. The selected-mode native compiler recognizes the canonical GDTF `Zoom` attribute alongside Dimmer, Pan, and Tilt and preserves ChannelFunction DMX ranges, ordered source bytes, and physical angle ranges in the compiled runtime. Live Zoom changes emit target-oriented `BeamOptics` rows with fixture ID, render target ID, changed mask, physical beam angle, half angle, and the current Zoom value so Godot can apply cached renderer resources by integer target ID.

Static Beam geometry fields remain setup-time optical profile inputs: `BeamType`, `BeamAngle`, `FieldAngle`, `BeamRadius`, `ThrowRatio`, `RectangleRatio`, `LuminousFlux`, `ColorTemperature`, and preserved emitter spectrum metadata. Official Beam geometry data has priority over Zoom, setup-time Peraviz aperture inference, documented fallback profiles, and the final safe circular fallback. Spot is treated as a hard-edged circular cone/frustum; Wash, PC, and Fresnel are circular cone/frustum baselines with softened field intent; Rectangle is reserved for rectangular pyramid/frustum output using `RectangleRatio`; None and Glow do not request a projected prism.

The live path is intentionally parametric: Dimmer rows mutate intensity/material state, while Zoom rows mutate the cached optics target and do not mark beam topology dirty. Setup-time target registration resolves optics targets and emitter anchors through canonical geometry keys; live application uses only numeric target IDs and cached records.
