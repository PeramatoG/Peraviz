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

### Debug tests

Configure CTest, inspect both inventories, build every target, and run without filters:

```bash
cmake -S native -B native/build-tests -G Ninja -DCMAKE_BUILD_TYPE=Debug -DBUILD_TESTING=ON
ctest --test-dir native/build-tests -N -V
ctest --test-dir native/build-tests --show-only=json-v1 > native/build-tests/ctest-inventory.json
cmake --build native/build-tests --target all --verbose
ctest --test-dir native/build-tests --output-on-failure --verbose --timeout 120
```

The default also builds the GDExtension for Godot tests. For focused pure-native development, `-DPERAVIZ_BUILD_GDEXTENSION=OFF` avoids resolving `godot-cpp` and mdns; tinyxml2 and libzip remain required. This does not change default builds or output paths.

### Windows x64 presets

`native/` is the CMake project root. The checked-in presets use the vcpkg toolchain at `C:/vcpkg/scripts/buildsystems/vcpkg.cmake`; they do not read `VCPKG_ROOT`. They enforce `x64-windows-static-md`, `BUILD_SHARED_LIBS=OFF`, and the dynamic MSVC runtime (`/MD` or `/MDd`). Thus, `peraviz_native` remains a GDExtension DLL while libzip, zlib, tinyxml2, and other vcpkg dependencies are linked statically.

The recommended local Ninja workflows are:

```powershell
cd <repo>/native
cmake --preset win-x64-debug-ninja
cmake --build --preset win-x64-debug-ninja
ctest --preset win-x64-debug-ninja --output-on-failure

cmake --preset win-x64-release-ninja
cmake --build --preset win-x64-release-ninja
ctest --preset win-x64-release-ninja --output-on-failure
```

Ninja uses one configuration per build tree, and each preset writes to `native/build/<preset-name>`. The existing Visual Studio generator workflows remain available as `windows-debug-static` and `windows-release-static`.

#### Visual Studio CMake workflow

In Visual Studio, open or activate `<repo>/native` as the CMake source directory, select **Local Machine**, then select `win-x64-debug-ninja` or `win-x64-release-ninja` and its matching build preset. The presets declare x64 with the `external` architecture strategy so Visual Studio initializes an x64 MSVC environment without asking Ninja to process an unsupported `-A` option.

Opening only the repository root can trigger Visual Studio's default or partial CMake configuration because the repository root has no `CMakeLists.txt`. Always activate `native/` to expose the project and its checked-in presets reliably.

If you switch between vcpkg triplets, delete the affected build directory before reconfiguring. Reusing a CMake cache created with `x64-windows` can keep dynamic dependency choices even after changing the command line.

After building, verify the runtime dependencies:

```powershell
dumpbin /DEPENDENTS bin\peraviz_native.dll
cmake --build --preset win-x64-release-ninja --target peraviz_native_check_dependencies
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
