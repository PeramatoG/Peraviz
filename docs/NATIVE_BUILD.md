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

## Importer mesh and Unicode regression

After building the extension and importing the project with the pinned Godot version, run:

```bash
python3 tests/integration/run_importer_unicode_smoke.py --godot "$GODOT_BIN"
```

The runner creates only synthetic temporary assets. It checks equivalent ASCII, `ñ`, and accented/non-Latin source paths; Unicode model/texture/GDTF entries and temporary extraction parents; multi-object 3DS vertex/index data; real 3DS/GLB surfaces; shared meshes; explicit corrupt/empty/missing errors; repeated-failure summaries; runtime compilation; scene replacement; and final lease cleanup. It compares scene identities between source variants and rejects engine errors as well as nonzero exits. Native resolution/collision regressions run within `peraviz_native_scene_asset_lifetime_tests`.

CI currently runs on Linux. Windows Unicode filesystem behavior must additionally be verified on Windows, using the existing native build/test presets above and a matching Godot executable:

```powershell
# From the repository root, after building and placing the extension in bin/:
& $godot --headless --editor --path . --quit
python tests/integration/run_importer_unicode_smoke.py --godot $godot
```

Both commands must succeed without script/engine errors. Confirm that all three source variants report five real asset instances and zero fallbacks for the valid scene; the separate deliberate corrupt-model test must report two failures/fallbacks but one unique asset error. The direct Unicode model test exercises the Windows native-path stream, independently of ASCII cache naming. Run from a Unicode checkout or use a Unicode `TEMP` directory as an additional check of native XML and extraction parents. Windows execution cannot be replaced by Linux results.
