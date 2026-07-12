# Beam Appearance Baseline

Peraviz separates corrected beam geometry from renderer appearance. Geometry still comes from the selected render aperture, the full GDTF `BeamAngle`, and `beam_visual_length_m`; appearance only changes alpha and emission distribution inside that existing volume.

## Official inputs and Peraviz defaults

GDTF `BeamType` remains the source for baseline renderer profiles. `Spot` and `Rectangle` use hard edges, while `Wash`, `PC`, and `Fresnel` use progressively softer Peraviz renderer defaults. `None` and `Glow` do not create a projected visible beam. These coefficients are not additional GDTF semantics; they are conservative Peraviz defaults for a first-pass, single-scattering-inspired appearance.

| BeamType | Projected beam | Shape | Edge default |
| --- | --- | --- | --- |
| Spot | Yes | Circular cone | hard or nearly hard |
| Rectangle | Yes | Rectangular pyramid | hard rectangular edge |
| PC | Yes | Circular cone | soft, more defined than Wash |
| Fresnel | Yes | Circular cone | broad soft transition |
| Wash | Yes | Circular cone | broadest soft field |
| None / Glow | No | none | lens/self-emission only |

## Radial energy

Circular beams use normalized local radius:

```text
normalized_radius = length(local_aperture_position) / local_radius
```

Rectangle beams use rectangular normalization so corners are not rounded:

```text
normalized_rect = max(abs(local_x) / local_half_width, abs(local_z) / local_half_height)
```

The local radius or half-extent is interpolated from the existing near and far geometry. The shader then applies a core-to-field envelope and exponent so energy is strongest near the axis and monotonically decreases toward the margin.

## BeamAngle and FieldAngle

`BeamAngle` remains the authoritative full-angle geometry input. `FieldAngle` never changes mesh radius, length, transform, scale, or AABB in this baseline. For soft BeamTypes only, valid `FieldAngle > BeamAngle` may broaden the visual envelope by comparing half-angle tangents. Missing, invalid, equal, or smaller `FieldAngle` values keep the BeamType baseline without warning spam.

## Longitudinal extinction

Visible in-air attenuation uses a stable physically motivated approximation:

```text
transmittance = exp(-extinction_coefficient * distance_m)
```

Distance is measured from the near beam plane along the beam axis. A small far-visibility floor keeps valid 75-100 m beams readable, but the floor is clamped so it does not make the whole beam uniformly bright or brighter at the far end than near/middle regions. Raw inverse-square attenuation is not applied directly to custom cone alpha.

## Surface light falloff

Custom visible beam attenuation is independent from `SpotLight3D` surface lighting. The Visual Settings surface falloff mode controls only Godot light attenuation:

- Balanced: the default practical Peraviz mode for existing non-photometrically-calibrated energy values.
- Physical inverse-square: sets Godot `spot_attenuation = 2.0`; distant surfaces may receive very little energy.

## Performance and limits

Profiles resolve during setup/static updates and are passed as shader instance parameters. Dimmer changes remain intensity-only, and appearance changes that are shader parameters do not rebuild fixture geometry. This is not a complete volumetric simulation: Frost, Focus, Iris, color systems, atmospheric spectra, multiple scattering, collision shortening, and shadowed participating-media integration are deferred.
