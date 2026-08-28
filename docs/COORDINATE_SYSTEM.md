# Coordinate system and transform validation

Peraviz converts MVR/GDTF transforms in native C++ before Godot scene construction.

## Mapping contract

Source translation is millimetres. Runtime translation is metres:

```text
(x, y, z) mm -> (x / 1000, z / 1000, -y / 1000) m
```

Source vectors use the corresponding axis remap `(x, y, z) -> (x, z, -y)`. Local basis conversion applies the same change of basis so parent/child composition, scale, and mirroring remain intact. When native data supplies a basis, Godot applies it directly rather than multiplying embedded scale a second time.

Godot runtime space is right-handed, uses `+Y` as up and `-Z` as forward, and uses local `-Z` as the GDTF emitter reference direction. The imported-content presentation multiplier is `1.0`. The optional one-metre reference cube is outside the imported scene root and therefore provides a direct scale check.

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
