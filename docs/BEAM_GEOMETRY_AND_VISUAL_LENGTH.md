# Beam geometry and visual length

Peraviz follows the GDTF optical geometry fields as physical inputs and keeps its own visible-beam length as a separate visualization choice.

## Official GDTF values

For GDTF 1.2 Beam geometry, `BeamRadius` is the radius at the beam origin in meters. It is not a diameter and is not stored in millimeters. `BeamAngle` and `FieldAngle` are full physical angles in degrees. Peraviz keeps these full angles canonical and converts to a half-angle only for tangent equations or APIs that explicitly require an angular radius.

The GDTF Beam geometry origin is the rendered beam origin, normally the lens/output aperture. GDTF emits along local negative Z. Peraviz maps source coordinates `(x, y, z)` to Godot `(x, z, -y)`, so the canonical mapped beam direction is Godot local negative Y with aperture axes local X and local Z.

## Peraviz visual length

`beam_visual_length_m` is a Peraviz-specific renderer setting, not a GDTF property. It defaults to 75 m and is clamped to the supported 1-150 m range. `BeamRadius` controls only the near aperture. Zoom changes the full angle and far spread only; Dimmer changes intensity and visibility only.

Optional realtime `SpotLight3D.spot_range` may use the configured visual length for lighting reach, but it is not the hidden authority for custom visible beam mesh length.

## Circular beam equation

For circular projected beams:

```text
near_radius_m = selected render aperture radius
near_diameter_m = near_radius_m * 2
half_angle_rad = deg_to_rad(full_beam_angle_deg * 0.5)
far_radius_m = near_radius_m + tan(half_angle_rad) * beam_visual_length_m
```

A 25 degree full beam angle at 75 m with a 0.05 m near radius has a far radius of about 16.6771 m. At 100 m it has a far radius of about 22.2195 m. These are valid optical results and are not clipped to 10 m.

## Aperture source priority

Peraviz records official, measured, and selected render aperture data separately:

1. A finite, positive, plausible explicit `BeamRadius` is selected first.
2. A reliable measurement from the exact Beam-owned lens/model subtree is selected when no explicit radius exists, when only a generic fallback exists, or when an explicit value grossly contradicts exact model evidence.
3. A documented safe fallback of 0.03 m is used only when neither source is usable.

Malformed official values are preserved for diagnostics. For example, `BeamRadius=50` remains recorded as 50 m; if exact Beam-owned geometry measures 0.05 m, Peraviz renders the measured aperture and emits mismatch diagnostics rather than silently interpreting the value as millimeters.

## Shapes

`Spot` renders as a hard-edged conical projected beam. `Wash`, `PC`, and `Fresnel` render as soft-edged conical projected beams. `Rectangle` preserves rectangular aperture ratio and separate half-extents. `None` and `Glow` do not draw a projected visible beam, while lens/self-emission may still follow Dimmer.

## Safety limits

Renderer safety handling rejects non-finite values, clamps visual length to 1-150 m, and guards only mathematically invalid or extreme resource cases. The guard is not a visual tuning factor and valid 75 m or 100 m beams are not narrowed to hide their physical spread.

## Appearance is not geometry

The Beam Appearance Baseline consumes the corrected near and far geometry as normalized local coordinates. It does not change the selected aperture radius, full-angle far-radius equation, `beam_visual_length_m`, RectangleRatio geometry, Beam-local direction, or fixture/scene scale.
