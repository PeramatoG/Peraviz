# Native build (GDExtension) for Peraviz

This document explains how to build the C++ native extension (`peraviz_native`) for the standalone Peraviz Godot project.

## Supported versions

- **Godot**: `4.2+`.
- **godot-cpp**: `godot-4.2.2-stable`.

## Native dependencies

In addition to `godot-cpp`, the native target links:

- `tinyxml2`: parsing `GeneralSceneDescription.xml`.
- `libzip`: reading and extracting ZIP-based MVR/GDTF archives through the internal native archive layer.

Peraviz now provides matrix/transform utilities locally under `native/src/` (`types.h`, `matrixutils.h`), so no external Perastage headers are required.

## Coordinate conversion (MVR/GDTF -> Godot)

The conversion is performed in C++ before exposing data to GDScript:

- MVR typically uses millimeters with a Z-up convention.
- Godot uses meters with a Y-up convention.
- Axis mapping and unit scaling are applied in `mvr_scene_loader.cpp`, and values are exported to GDScript as `Vector3` for position/rotation/scale.

## Standalone build

From the repository root:

```bash
cmake -S native -B native/build -DCMAKE_BUILD_TYPE=Debug
cmake --build native/build --config Debug
```

The resulting library is copied automatically to `bin/`.

### Windows (Visual Studio) note

When building with Visual Studio, the generated `peraviz_native.dll` may depend on additional
runtime DLLs (`libzip`, `zlib`, `tinyxml2`, etc.). The native CMake copies runtime DLL
dependencies to `bin/` after each build, so Godot can load the extension without
manual PATH tweaks.

If `PeravizLoader` is still reported as unknown in GDScript, verify that `bin/`
contains `peraviz_native.dll` and its dependent DLLs, then restart the Godot editor.

## Usage from Godot

The native class `PeravizLoader` exposes:

- `load_mvr(path: String) -> Array`

Each array element is a `Dictionary` with:

- `id: String`
- `type: String` (`fixture`, `truss`, `support`, `scene_object`)
- `is_fixture: bool`
- `pos: Vector3`
- `rot: Vector3` (degrees)
- `scale: Vector3`

The script `res://scripts/load_scene.gd` consumes this data to instantiate proxy meshes (`CylinderMesh` configured as a cone / `BoxMesh`) in the test scene.
