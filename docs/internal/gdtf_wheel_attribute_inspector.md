# GDTF Wheel and Attribute Inspector

Checkpoint 08E3 adds read-only core services for resolving wheel and attribute inspection state without moving GDTF semantics into presentation code.

## Model

The non-GUI catalog preserves Wheel, WheelSlot, Filter, graphic-wheel names, source order, stable IDs, raw Color text, Filter references, MediaFileName values, PrismFacet markers, AnimationSystem markers, and structured diagnostics. WheelSlot indexes are effective one-based indexes from source order.

## Resource lookup

Wheel, animation-wheel, graphic-wheel, and slot media resources are loaded lazily from the requested archive entry. The reader rejects unsafe paths, checks canonical wheel locations first, accepts supported image extensions, allows only unambiguous compatibility fallback, enforces a byte limit, and returns raw bytes without decoding images or extracting files.

## CIE previews

ColorCIE preserves raw xyY text and converts valid values to an approximate display sRGB preview. The conversion validates finite values, requires `y > 0`, performs xyY to XYZ to sRGB conversion, clips safely, and reports clipping. The preview is not a replacement for the GDTF source value.

## DMX resolver

The pure resolver accepts a typed channel model, normalized value, and catalog. It returns per-byte values, percentage, active LogicalChannel mappings, active ChannelFunction, active ChannelSet, Wheel, WheelSlot, Filter, physical interpolation when reliable, ModeMaster conditional state, DMXProfile limitation diagnostics, and invalid mapping diagnostics. The mapping is strictly Function.Wheel plus Set.WheelSlotIndex; slot order, labels, attributes, and physical values are not used as fallbacks.

## Read-only boundary

The inspector state is designed for later editing, but this checkpoint exposes no mutable XML nodes, no XML writer, no Save path, no undo commands, no project dirtying, and no live DMX output.
