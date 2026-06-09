# Windows export workflow

This document describes the recommended Windows export flow for Peraviz when using the native GDExtension.

## Required export layout

`peraviz.gdextension` expects the Windows native extension at this resource path:

```ini
windows.debug.x86_64 = "res://bin/peraviz_native.dll"
windows.release.x86_64 = "res://bin/peraviz_native.dll"
```

Keep the exported application layout consistent with that path:

```text
Peraviz/
    Peraviz.exe
    Peraviz.console.exe
    bin/
        peraviz_native.dll
```

Do not duplicate `peraviz_native.dll` in the export root. If Godot places the DLL next to the executable instead of under `bin/`, the export preset is missing an explicit resource include filter for `bin/*.dll`.

## Build the native extension for Windows export

Use vcpkg manifest mode with the static Windows triplet from a Visual Studio Developer Command Prompt or a shell where `VCPKG_ROOT` points to the vcpkg checkout:

```powershell
cd <repo>\native
cmake --preset windows-release-static
cmake --build --preset windows-release-static
```

For Debug editor validation, use the matching Debug preset:

```powershell
cd <repo>\native
cmake --preset windows-debug-static
cmake --build --preset windows-debug-static
```

The presets configure:

- `CMAKE_TOOLCHAIN_FILE=$env{VCPKG_ROOT}/scripts/buildsystems/vcpkg.cmake`
- `VCPKG_TARGET_TRIPLET=x64-windows-static`
- `BUILD_SHARED_LIBS=OFF`
- separate build directories for Debug and Release static builds

The `peraviz_native` target remains a DLL because Godot loads it as a GDExtension, but libzip, zlib, tinyxml2, and related third-party dependencies are linked statically.

If you previously configured the same build directory with `x64-windows` or another dynamic triplet, delete that build directory before reconfiguring. CMake and vcpkg cache the selected triplet, and reusing a dynamic-triplet cache can silently keep dynamic runtime dependencies.

## Verify native DLL dependencies

After building, verify that the native extension does not depend on unwanted third-party DLLs:

```powershell
dumpbin /DEPENDENTS bin\peraviz_native.dll
```

The output must not list:

- `zip.dll`
- `zlib1.dll`
- `zlibd1.dll`
- `tinyxml2.dll`
- `pcre2-16.dll`
- `pcre2-16d.dll`
- `wxbase*.dll`
- `wxmsw*.dll`
- `jvm.dll`

You can also run the CMake helper target from the static build tree:

```powershell
cmake --build --preset windows-release-static --target peraviz_native_check_dependencies
```

The helper uses `dumpbin` and fails if it sees the forbidden third-party DLLs above. Run it from a Visual Studio Developer Command Prompt so `dumpbin` is available.

## Configure Godot Windows export

`export_presets.cfg` is not committed because Godot export presets commonly contain local export paths. Configure the Windows Desktop preset in Godot with these resource settings:

1. Open **Project > Export**.
2. Select or create a **Windows Desktop** preset.
3. In **Resources**, use an export mode that includes project resources, such as **Export all resources in the project**.
4. Add these include filters so Godot preserves the GDExtension file and native DLL path:

   ```text
   *.gdextension, bin/*.dll
   ```

5. Export the project.
6. Confirm the exported folder contains `bin/peraviz_native.dll` and does not contain an extra root-level copy of `peraviz_native.dll`.

The repository keeps `bin/.gitkeep` so a clean clone has the expected `bin/` directory. The compiled DLL and local debug artifacts remain ignored and are produced by the native build.

## Final validation

Run the exported console executable with verbose logging:

```powershell
.\Peraviz.console.exe --verbose
```

The log should not contain:

- `Missing dependencies: jvm.dll`
- `GDExtension dynamic library not found`
- `Identifier "PeravizLoader" not declared`

If those messages appear, first confirm that `bin/peraviz_native.dll` exists inside the export and that `dumpbin /DEPENDENTS` does not list forbidden third-party DLLs.
