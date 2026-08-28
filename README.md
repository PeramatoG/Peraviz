# Peraviz

Peraviz is an experimental, source-built real-time lighting visualizer. It loads MVR scenes, interprets fixture data from GDTF, receives live Art-Net DMX, and presents the resulting scene in Godot through a native C++ GDExtension. Peraviz is viewer-focused; Perastage remains the companion project for authoring and project-management workflows.

Peraviz is under active development and has no packaged release. GDTF coverage is intentionally incremental: consult the support matrix before relying on an attribute or renderer effect.

## Current capabilities

- Native MVR/GDTF scene loading, fixture patching, and selected-mode runtime compilation.
- Live Art-Net input with native DMX evaluation and dirty, sectioned render updates.
- Native Dimmer, Pan, Tilt, Zoom, physical color, color-wheel, and bounded static seated-gobo paths for the verified scopes documented in the support matrix.
- Godot scene reconstruction, interaction, UI, and lightweight or volumetric beam presentation.
- Debug and regression tooling for transforms, runtime contracts, and renderer-facing updates.

## Platforms and build

The repository targets Windows, Linux, and macOS source builds. Continuous integration currently verifies Linux Debug; Windows build and export instructions are maintained separately.

- **Godot runtime/editor:** 4.7.1 stable
- **GDExtension API:** Godot 4.7, using the pinned `godot-cpp` revision in `native/cmake/GodotCompatibility.cmake`
- **Build tools:** CMake and a compatible C++ compiler
- **Native dependencies:** `tinyxml2` and `libzip`

From the repository root:

```bash
cmake -S native -B native/build -DCMAKE_BUILD_TYPE=Debug -DBUILD_TESTING=ON
cmake --build native/build
ctest --test-dir native/build --output-on-failure
```

The build copies the extension into `bin/`. Open `project.godot` in the compatible Godot editor and run the main scene. See [Native build](docs/NATIVE_BUILD.md) and [Windows export](docs/WINDOWS_EXPORT.md) for complete platform instructions.

## Documentation

These are the authoritative starting points:

- [Runtime architecture](docs/architecture.md): active native-to-Godot data flow and ownership boundaries.
- [GDTF support matrix](docs/gdtf-support-matrix.md): supported, partial, parsed-only, and unsupported semantics.
- [Gobo control](docs/GDTF_GOBO_CONTROL.md): the current static seated-gobo contract and motion limitations.
- [Uniform physical color pipeline](docs/uniform-physical-color-pipeline.md): color evaluation and renderer approximation contracts.
- [MVR-xchange](docs/MVR_XCHANGE.md): supported exchange behavior.
- [Project data ownership](docs/peraviz-project-architecture.md) and [PVZ format](docs/pvz-project-format.md): project-storage boundaries.
- [Coordinate system](docs/COORDINATE_SYSTEM.md), [beam rendering modes](docs/BEAM_RENDERING_MODES.md), and [performance guidelines](docs/godot_performance_guidelines.md): specialized renderer guidance.

Contributor rules are in [AGENTS.md](AGENTS.md) and [CONTRIBUTING.md](CONTRIBUTING.md).

## License

Peraviz is licensed under the [GNU General Public License v3.0](LICENSE.txt).
