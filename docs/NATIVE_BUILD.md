# Native build

`native/` builds the `peraviz_native` GDExtension and native test targets. Runtime architecture is documented separately in [architecture.md](architecture.md).

## Compatibility contract

`native/cmake/GodotCompatibility.cmake` is authoritative:

- Godot runtime: **4.7.1**
- GDExtension API: **4.7**
- minimum GDExtension compatibility: **4.7**
- `godot-cpp` revision: **`82c6c449b9432d1eae1fbaa087bd579c77e6e8d5`**

The revision is immutable. Repository validation rejects inconsistent version declarations.

## Dependencies

The normal GDExtension build uses:

- `godot-cpp`, fetched at the pinned revision unless `GODOT_CPP_DIR` supplies a checkout;
- `tinyxml2` for XML parsing;
- `libzip` for MVR/GDTF archive access;
- `mdns` when both the GDExtension and MVR-xchange discovery are enabled (the defaults).

`native/vcpkg.json` is the dependency manifest used by CI and supported Windows presets. A focused pure-native build can set `PERAVIZ_BUILD_GDEXTENSION=OFF`; this avoids `godot-cpp` and `mdns`, while `tinyxml2` and `libzip` remain required.

## Debug build and tests

The normal CI-equivalent configuration uses a vcpkg toolchain:

```bash
cmake -S native -B out/linux-debug -G Ninja \
  -DCMAKE_BUILD_TYPE=Debug \
  -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
  -DCMAKE_TOOLCHAIN_FILE="$VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake" \
  -DVCPKG_TARGET_TRIPLET=x64-linux \
  -DBUILD_TESTING=ON
cmake --build out/linux-debug --target all --verbose
ctest --test-dir out/linux-debug --output-on-failure --verbose --timeout 120
```

Before testing, CI validates the complete CTest inventory with `.github/scripts/validate_ctest_inventory.py`. The successful GDExtension build is copied to `bin/`; CI then imports the project with Godot, verifies native class registration, and runs every headless GDScript test.

## Windows

From `native/`, use `win-x64-debug-ninja` or `win-x64-release-ninja` and their matching build/test presets. They use the checked-in vcpkg toolchain configuration and static third-party libraries with the dynamic MSVC runtime.

```powershell
cd native
cmake --preset win-x64-debug-ninja
cmake --build --preset win-x64-debug-ninja
ctest --preset win-x64-debug-ninja --output-on-failure
```

Use the Visual Studio presets only with `native/` as the CMake source directory. See [Windows export](WINDOWS_EXPORT.md) for packaging and dependency verification.
