# Native color MVP consolidation

The supported color MVP remains limited to `ColorAdd_R`, `ColorAdd_G`, `ColorAdd_B`, `ColorAdd_W`, `ColorAdd_RY`, `ColorAdd_GY`, `ColorSub_C`, `ColorSub_M`, and `ColorSub_Y`. These are Peraviz fallback approximations, not physical emitter spectra, filter transmission data, ColorCIE conversion, CTO/CTB/CTC, Tint, color wheels, macros, or gobos.

## Root causes fixed

- The native compositor normalized against `max(rgb, 1.0)`, so CMY filtering could make gray chromaticity but could not lower scalar transmission below `1.0`.
- Godot cached renderer color by fixture UUID, allowing Dimmer or Optics updates for one Beam output to reuse another Beam output's last color in multi-beam fixtures.
- Color target registration reused Dimmer registration, which coupled Color setup to Dimmer counters, ownership filtering, and overlap diagnostics.

## Final contract

Native `EmitterColor` rows carry `fixture_id`, `beam_render_target_id`, `changed_mask`, renderer-ready sRGB chromaticity, and linear `color_gain`. Native color composition first computes complete linear RGB, derives `color_gain = max(linear_rgb.r, linear_rgb.g, linear_rgb.b)`, emits black with zero gain for closed output, and converts only normalized chromaticity to sRGB.

Godot stores color, gain, Dimmer, light energy, beam intensity, and material energy per canonical `beam_render_target_id`, with fixture UUID retained as metadata. Dimmer, Color, and Optics semantic records reference immutable cached Beam output records so a parent Dimmer target can update several exact Beam outputs without sharing mutable color state. Dimmer-only and Color-only rows both resolve cached resources by target ID and compute final rendered energy as:

```text
final_energy = native_dimmer_energy * color_gain
```

The multiplication point is the Godot resource application layer: SpotLight3D `light_energy` and Lightweight Prism beam shader intensity use `native_energy * projected_lumen_scale * color_gain`, while lens emission uses `native_material_energy * emission_lumen_scale * color_gain`. The cached target-local `color_gain` is applied exactly once and does not replace per-emitter photometric distribution.
