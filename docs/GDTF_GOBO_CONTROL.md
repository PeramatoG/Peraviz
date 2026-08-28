# GDTF gobo control

This document defines the authoritative production gobo contract. The implementation is intentionally limited to static seated selection; code present elsewhere does not expand this support boundary.

## Supported static contract

For selected-mode `Gobo(n)` ChannelFunctions, native C++ compiles indexed wheel identity, wheel instance order, exact one-based `WheelSlotIndex`, seated ChannelSet DMX windows, stable asset IDs, and exact Beam render-target IDs. The native runtime evaluates the active window and emits a dirty `GoboSelection` row containing fixture, Beam target, wheel, wheel instance, slot, asset, selection mode, change mask, and revision. The section's reserved float is structural and has no gobo meaning.

During structural setup, `NativeGoboResourceRegistry` loads and retains original PNG/mask resources and prepares reusable normalized vector-prism topology. Live rows select these registered resources by stable numeric ID; they do not carry paths, images, or semantic dictionaries. An open or missing-media slot clears deterministically.

## Static multi-wheel composition

When more than one seated gobo wheel targets the same Beam and all selected layers are static, Godot forms a canonical ordered key, multiplies the binary masks, caches the composed mask, and vectorizes that combination once. Topology excludes fixture UUID and live presentation values so repeated fixtures can reuse it. Original masks remain independently retained.

This is a bounded static compatibility contract. It does not support independently rotating, shaking, spinning, or indexed layers, and it must not be presented as general moving multi-wheel composition.

## Unsupported motion

The production path does **not** support:

- gobo position or index rotation;
- continuous gobo rotation;
- wheel spin;
- selection or position shake variants;
- independently moving multi-wheel composition;
- a production surface-projector motion contract.

Legacy GDScript resolvers, metadata, projector logic, and attribute grouping may remain for compatibility, inspection, debugging, or transition. They are not the authoritative live GDTF semantic path and their presence does not make a feature supported.

The parser-owned native contract now preserves the exact, wheel-indexed identities `Gobo(n)`, `Gobo(n)SelectSpin`, `Gobo(n)SelectShake`, `Gobo(n)SelectEffects`, `Gobo(n)WheelIndex`, `Gobo(n)WheelSpin`, `Gobo(n)WheelShake`, `Gobo(n)WheelRandom`, `Gobo(n)WheelAudio`, `Gobo(n)Pos`, `Gobo(n)PosRotate`, and `Gobo(n)PosShake`. It also compiles generic ChannelFunction `ModeMaster`, `ModeFrom`, and `ModeTo` conditions and evaluates resolved DMXChannel or ChannelFunction dependency cascades natively.

This semantic foundation does not animate or render gobo motion. Static seated `Gobo(n)` selection remains the only rendered gobo behavior; future renderer work must consume the compiled contract rather than restore heuristic Dictionary-driven grouping.

## Related contracts

- [Runtime architecture](architecture.md)
- [GDTF support matrix](gdtf-support-matrix.md)
- [Runtime storage policy](runtime-storage-policy.md)
- [Beam rendering modes](BEAM_RENDERING_MODES.md)
