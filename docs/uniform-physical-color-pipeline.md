# Uniform physical GDTF color pipeline

Peraviz keeps the uniform color pipeline native: GDTF/MVR data is parsed into immutable C++ resources, compiled into target-oriented Beam color programs, evaluated in the native visual runtime, and emitted to Godot only as the existing `EmitterColor` row with renderer-ready sRGB chromaticity and linear `color_gain`.

## Implemented standard physical paths

- GDTF `PhysicalDescriptions/Emitters/Emitter` resources are parsed with `Color`, `DominantWaveLength`, `Measurement`, `LuminousIntensity`, `InterpolationTo`, and `MeasurementPoint` spectra.
- GDTF `PhysicalDescriptions/Filters/Filter` resources are parsed with `Color`, `Measurement`, `Transmission`, `InterpolationTo`, and `MeasurementPoint` spectra.
- `ChannelFunction` `Emitter`, `Filter`, and `ColorSpace` links are resolved during fixture compilation to stable integer resource IDs. Invalid links produce compilation diagnostics and are not rebound by similar names.
- Linked emitter ColorCIE data replaces generic additive RGB approximations for the affected channel. Linked filter ColorCIE/transmission data replaces CMY arithmetic for the affected channel.
- Direct `CIE_X`, `CIE_Y`, and `CIE_Brightness` channels cook a target-level xyY result once all three components are present.
- `CTO`, `CTB`, and `CTC` physical values are treated as resulting Kelvin values and applied natively as a bounded CCT white transform.
- `Tint` uses linked physical filter data first. Without physical data it uses the isolated Peraviz green/magenta fallback described below.

## Fallback priority

Additive channels use this priority:

1. Linked Emitter measurement/spectrum when prevalidated and usable.
2. Linked Emitter ColorCIE.
3. Linked Emitter DominantWaveLength in the supported visible observer range.
4. Attribute/default color approximation.
5. Centralized Peraviz additive fallback for legacy MVP attributes.

Subtractive channels use this priority:

1. Linked Filter measurement/spectrum and transmission when prevalidated and usable.
2. Linked Filter ColorCIE and relative Y/transmission.
3. Attribute/default color approximation.
4. Centralized Peraviz CMY arithmetic fallback for legacy MVP attributes.

Tint fallback is explicitly non-standard. It maps the evaluated physical range to a conservative green/magenta axis, preserves energy unless linked filter data says otherwise, and remains isolated so it can be replaced by a more exact future model.

## Color science

- Physical `ColorCIE` values are parsed as CIE 1931 xyY. Emitter and Filter Y values use percentage-style normalization when authors provide values above `1.0`, preserving GDTF's relative-output/transmission meaning for Beam luminous flux context.
- xyY converts to XYZ with `X = x * Y / y` and `Z = (1 - x - y) * Y / y`; invalid, negative, or non-finite input is rejected.
- XYZ converts to renderer working RGB with the documented sRGB/D65 matrix.
- Spectral measurements are validated for finite, strictly ascending wavelengths and non-negative energy, then integrated to XYZ with a deterministic repository-owned CIE 1931 observer approximation. Converted measurement XYZ values are cached in the compiled scene instead of integrated per DMX tick.
- Dominant wavelength fallback uses the same observer path and rejects non-visible wavelengths instead of inventing visible UV colors.
- Final linear RGB is decomposed exactly once: `gain = max(linear_r, linear_g, linear_b, 0)`. The normalized linear chromaticity is converted to nonlinear sRGB, while `color_gain` remains a separate scalar.

## Composition order

For each exact Beam output, Peraviz composes color deterministically in this order:

1. Additive source composition.
2. Direct subtractive filters and CMY fallback filters.
3. CCT correction from CTO/CTB/CTC resulting Kelvin values.
4. Tint physical filter or fallback correction.
5. Final gain/chromaticity decomposition and dirty-only `EmitterColor` emission.

Godot does not receive CIE data, spectra, emitter/filter IDs, Kelvin values, Tint values, DMX ranges, or physical resource metadata.

## Deferred features

Wheels, WheelSlot selection, split colors, gobos, animation wheels, prisms, spatial projector textures, HSB controls, full gamut clipping, and CRI simulation remain unsupported for runtime rendering in this stage.
