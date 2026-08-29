# Coordinate system and transform validation

Peraviz converts MVR/GDTF transforms in native C++ before Godot scene construction.

## Mapping contract

Source translation is millimetres. Runtime translation is metres:

```text
(x, y, z) mm -> (x / 1000, z / 1000, -y / 1000) m
```

Source vectors use the corresponding axis remap `(x, y, z) -> (x, z, -y)`. Local basis conversion applies the same change of basis so parent/child composition, scale, and mirroring remain intact. When native data supplies a basis, Godot applies it directly rather than multiplying embedded scale a second time.

Godot runtime space is right-handed, with `+Y` as world up and `-Z` as the conventional forward axis. Optical-axis descriptions use three distinct local spaces:

1. **GDTF/source-local:** a Beam emits along local `-Z`.
2. **Mapped scene/runtime:** the vector remap sends source-local `-Z` to mapped emitter-local `-Y`.
3. **Renderer-child-local:** Peraviz attaches a `SpotLight3D` below the mapped emitter and rotates it by `-90` degrees around X. Godot's light direction and the custom renderer children therefore use light-local `-Z`, which is the same physical direction as mapped emitter-local `-Y`.

Code working on future optical rotation or shake must state which of these spaces owns the value. GDTF semantics are defined around source-local `-Z`; renderer-local presentation is performed around the light child's `-Z` axis after attachment. The imported-content presentation multiplier is `1.0`. The optional one-metre reference cube is outside the imported scene root and therefore provides a direct scale check.

The current custom gobo-prism topology has a separate raw mesh space: its beam length is authored on mesh-local `Y`, with the gobo cross-section in the `XZ` plane. The renderer's `+90` degree X presentation rotation maps that longitudinal mesh-local Y axis onto the physical light-local optical axis. Code rotating the prism `MeshInstance3D` therefore spins around raw mesh-local Y; shader-mask presentation instead rotates transverse XZ coordinates and leaves the node transform unchanged.

## Debugging

- `peraviz_debug_baseline` enables `[PeravizBaseline]` source-to-runtime transform records.
- `peraviz_debug_coords` enables `[PeravizCoordDebug]` mapping metadata and can be toggled with `C`.
- `[PeravizNative]` load summaries provide node/category counts for comparison context.

The coordinate metadata reports the unit scale, handedness, axes, vector remap, and beam reference. Emitter events identify the fixture geometry being checked. Use the exact prefixes rather than depending on log ordering:

```bash
rg -n "PeravizCoordDebug|PeravizBaseline|PeravizNative|PeravizCoordDebugLegend" <runtime-log>
```

## Regression criteria

For transform changes, compare representative fixture-heavy, rigging, and nested-hierarchy MVR scenes. Positions, orientation, perceived scale, fixture aiming, and parent/child attachment must remain stable. Floating-point jitter, logging order, and debug-overlay appearance are not transform regressions. Record matched views and relevant audit logs when a deliberate mapping correction changes output; do not introduce silent transform adjustments.
