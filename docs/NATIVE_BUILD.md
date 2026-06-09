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

### Windows static vcpkg build for exports

For Windows exports, build from a Visual Studio Developer Command Prompt with vcpkg manifest mode and the static triplet:

```powershell
cd <repo>/native
cmake --preset windows-release-static
cmake --build --preset windows-release-static
```

The Windows static presets use `x64-windows-static`, `BUILD_SHARED_LIBS=OFF`, and `$env{VCPKG_ROOT}/scripts/buildsystems/vcpkg.cmake`. They keep `peraviz_native` as a GDExtension DLL while linking third-party dependencies such as libzip, zlib, and tinyxml2 statically.

If you switch between vcpkg triplets, delete the affected build directory before reconfiguring. Reusing a CMake cache created with `x64-windows` can keep dynamic dependency choices even after changing the command line.

After building, verify the runtime dependencies:

```powershell
dumpbin /DEPENDENTS bin\peraviz_native.dll
cmake --build --preset windows-release-static --target peraviz_native_check_dependencies
```

The dependency list must not include `zip.dll`, `zlib1.dll`, `tinyxml2.dll`, wxWidgets DLLs, pcre2 DLLs, or `jvm.dll`.

For the full Windows export checklist, including Godot resource filters for preserving `bin/peraviz_native.dll`, see `docs/WINDOWS_EXPORT.md`.

### Windows dynamic development note

The native CMake still keeps the post-build copy step for `$<TARGET_RUNTIME_DLLS:peraviz_native>`. This remains useful for dynamic local development builds, but a static vcpkg export build should not need copied third-party DLLs.

If `PeravizLoader` is reported as unknown in GDScript, verify that `bin/peraviz_native.dll` exists at the path referenced by `peraviz.gdextension`, then restart the Godot editor.

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
