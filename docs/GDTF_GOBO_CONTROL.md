# GDTF gobo control

This document defines the authoritative production gobo contract: static seated selection and indexed selected-gobo position within the boundary below.

## Supported static contract

For selected-mode `Gobo(n)` ChannelFunctions, native C++ compiles indexed wheel identity, wheel instance order, exact one-based `WheelSlotIndex`, seated ChannelSet DMX windows, stable asset IDs, and exact Beam render-target IDs. The native runtime evaluates the active window and emits a dirty `GoboSelection` row containing fixture, Beam target, wheel, wheel instance, slot, asset, selection mode, change mask, and revision. The section's reserved float is structural and has no gobo meaning.

During structural setup, `NativeGoboResourceRegistry` loads and retains original PNG/mask resources and prepares reusable normalized vector-prism topology. Live rows select these registered resources by stable numeric ID; they do not carry paths, images, or semantic dictionaries. An open or missing-media slot clears deterministically.

## Static multi-wheel composition

When more than one seated gobo wheel targets the same Beam and all selected layers are static, Godot forms a canonical ordered key, multiplies the binary masks, caches the composed mask, and vectorizes that combination once. Topology excludes fixture UUID and live presentation values so repeated fixtures can reuse it. Original masks remain independently retained.

This is a bounded static compatibility contract. It does not support independently rotating, shaking, spinning, or indexed layers, and it must not be presented as general moving multi-wheel composition.

## Indexed selected-gobo position

Exact `Gobo(n)Pos` bindings cross the version 7 packed setup contract with their physical Angle range and generic ModeMaster activation chain. Native C++ evaluates changed source or activation-master bytes and emits dirty-only `GoboRotation` rows in physical degrees. Godot applies that renderer-ready angle parametrically to the reusable selected-gobo presentation layer; it does not add wheel `PlacementOffset`, rotate Pan/Tilt geometry, or rebuild gobo topology.

The indexed angle is retained per Beam target and one-based wheel instance across open-slot and selection changes. Exactly one visible seated layer can move. When multiple visible layers form a static composition, Peraviz retains each requested angle but leaves the cached composition unrotated and records the deferred moving-composition condition.

Volumetric shader-mask presentation combines the renderer alignment with Pos in its per-instance shader rotation. Reusable vector-prism presentation combines its cached base basis with Pos about renderer-child Beam space. Both paths reapply retained Pos after optics or shape refresh without rotating the `SpotLight3D`, Pan/Tilt geometry, or replacing the mesh resource.

## Unsupported motion

The production path does **not** support:

- continuous gobo rotation;
- wheel spin;
- selection or position shake variants;
- independently moving multi-wheel composition;
- a production surface-projector motion contract.

Legacy GDScript resolvers, metadata, projector logic, and attribute grouping may remain for compatibility, inspection, debugging, or transition. They are not the authoritative live GDTF semantic path and their presence does not make a feature supported.

The parser-owned native contract now preserves the exact, wheel-indexed identities `Gobo(n)`, `Gobo(n)SelectSpin`, `Gobo(n)SelectShake`, `Gobo(n)SelectEffects`, `Gobo(n)WheelIndex`, `Gobo(n)WheelSpin`, `Gobo(n)WheelShake`, `Gobo(n)WheelRandom`, `Gobo(n)WheelAudio`, `Gobo(n)Pos`, `Gobo(n)PosRotate`, and `Gobo(n)PosShake`. Setup compilation carries exact motion scope, Beam target, wheel, source, ChannelSet physical ranges, and generic ChannelFunction `ModeMaster`, `ModeFrom`, and `ModeTo` activation into `CompiledRuntimeScene`. Activation-only sources preserve dependencies on non-gobo channels, and native evaluation can select an instantaneous active semantic and physical scalar without XML or name lookup.

Static seated `Gobo(n)` selection and dirty parametric `Gobo(n)Pos` are rendered. `Gobo(n)PosRotate`, shake, wheel spin/random/audio, effects, and independently moving multi-wheel composition remain deferred and must consume the compiled contract rather than restore heuristic Dictionary-driven grouping.

## Related contracts

- [Runtime architecture](architecture.md)
- [GDTF support matrix](gdtf-support-matrix.md)
- [Runtime storage policy](runtime-storage-policy.md)
- [Beam rendering modes](BEAM_RENDERING_MODES.md)
