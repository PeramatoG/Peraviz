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

Do not duplicate `peraviz_native.dll` in the export root. The Windows packaging workflow checks Godot's export output and, when necessary, stages the verified Release DLL as a filesystem sidecar at `bin/peraviz_native.dll`. It verifies its SHA-256 hash against the compiled DLL; forcing the DLL into the PCK with an include filter is not an adequate substitute.

## Build the native extension for Windows export

Use vcpkg manifest mode with the static-dependency Ninja preset from an x64 Visual Studio Developer Command Prompt:

```powershell
cd <repo>\native
cmake --preset win-x64-release-ninja
cmake --build --preset win-x64-release-ninja
```

For Debug editor validation, use the matching Debug preset:

```powershell
cd <repo>\native
cmake --preset win-x64-debug-ninja
cmake --build --preset win-x64-debug-ninja
```

The presets configure:

- `CMAKE_TOOLCHAIN_FILE=C:/vcpkg/scripts/buildsystems/vcpkg.cmake`
- `VCPKG_TARGET_TRIPLET=x64-windows-static-md`
- `BUILD_SHARED_LIBS=OFF`
- dynamic MSVC CRT linkage (`/MD` for Release and `/MDd` for Debug)
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
cmake --build --preset win-x64-release-ninja --target peraviz_native_check_dependencies
```

The helper uses `dumpbin` and fails if it sees the forbidden third-party DLLs above. Run it from a Visual Studio Developer Command Prompt so `dumpbin` is available.

## Configure Godot Windows export

`export_presets.cfg` is now versioned with a reproducible Windows Desktop preset, with no local machine paths or signing credentials. Configure it in Godot with these resource settings:

1. Open **Project > Export**.
2. Select or create a **Windows Desktop** preset.
3. In **Resources**, use an export mode that includes project resources, such as **Export all resources in the project**.
4. Keep `VERSION` in the include filter so the standalone startup splash can display the same version used by the installer. Godot manages GDExtension resources based on their `.gdextension` declarations; do not force `bin/*.dll` into the PCK.
5. Export the project. When exporting manually, stage the verified compiled Release DLL in the exported `bin/` directory if it was not emitted by the exporter.
6. Confirm the exported folder contains `bin/peraviz_native.dll`, and neither a root-level duplicate nor a temporary `~peraviz_native.dll`.

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

## Experimental Windows GitHub Actions installer

The `.github/workflows/package-windows.yml` workflow compiles the x64 Release GDExtension on Windows, checks native DLL dependencies, downloads the pinned Godot 4.7.1 runtime and export templates, imports Godot assets, and exports the versioned `Windows Desktop` preset. It verifies that the export includes the application EXE, PCK, console executable, and `bin/peraviz_native.dll`, then performs a headless startup smoke check.

Successful runs upload two test artifacts, not GitHub Releases: `Peraviz-portable-<version>-windows-x64.zip` and `Peraviz-Setup-<version>-windows-x64.exe`. The installer uses Inno Setup, installs per-user without requesting elevation, and provides an optional desktop shortcut. The version is taken from `VERSION`.

After merge, trigger it with **Actions > Windows package (experimental) > Run workflow**. The workflow also runs on its own PR. Download the artifacts from the successful run.

The headless test is not proof that the renderer works: test launch, an ordinary MVR/GDTF import, DMX Art-Net, save/open, shortcuts, and uninstallation on a Windows PC. The installer is unsigned and may trigger SmartScreen warnings; do not suppress security protections. Public releases should add code signing and protect credentials using GitHub Actions secrets.

The preset now embeds Peraviz's golden Windows ICO. The project starts with `startup_splash.tscn`, a separate compact transparent, borderless window matching Perastage's startup proportions: a 180 x 180 px framed brand image, version at the top, and a static `Loading Peraviz...` label below. The version text uses `res://VERSION`, included in the Windows PCK, with a fallback for source-only builds. Godot's built-in full-window boot image is disabled. After the existing `test.tscn` Viewer is ready, the startup scene restores normal native window decorations, disables transparency and always-on-top, then maximizes the Viewer. Loading progress telemetry is intentionally deferred. Linux and macOS will each need platform native builds and export verification; macOS public releases need code-signing and notarization.

### Windows visual validation

On an actual Windows machine, run `Peraviz.exe` from the portable distribution and verify the initial card is small, centered, rounded and frameless, with `Peraviz <VERSION>` above the 180 px original artwork and `Loading Peraviz...` below. Check that the splash closes when the Viewer is available, the Viewer fills a normal maximized decorated window with the original control layout, focus and resizing work, and the taskbar icon stays correct. Repeat with a saved `.pvz` startup preference and at high-DPI scaling. A headless CI test cannot establish these visual properties.
