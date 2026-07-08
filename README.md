# Peraviz – real-time DMX 3D viewer based on MVR/GDTF

<p align="center">
  <a href="https://github.com/PeramatoG/Peraviz/releases">
    <img alt="Release Status" src="https://img.shields.io/badge/release-unreleased-lightgrey?style=flat-square">
  </a>
  <img alt="Status" src="https://img.shields.io/badge/status-experimental-orange?style=flat-square">
  <img alt="Godot" src="https://img.shields.io/badge/Godot-4.2%2B-478CBF?style=flat-square">
  <img alt="GDExtension" src="https://img.shields.io/badge/GDExtension-C%2B%2B-00599C?style=flat-square">
  <img alt="Art-Net" src="https://img.shields.io/badge/DMX-Art--Net-purple?style=flat-square">
  <img alt="MVR/GDTF" src="https://img.shields.io/badge/MVR%20%2F%20GDTF-supported-blue?style=flat-square">
  <img alt="Platform" src="https://img.shields.io/badge/platform-Windows%20%7C%20macOS%20%7C%20Linux-blue?style=flat-square">
  <a href="https://github.com/PeramatoG/Peraviz/blob/main/LICENSE.txt">
    <img alt="License" src="https://img.shields.io/badge/license-GPL--3.0-blue?style=flat-square">
  </a>
</p>

<p align="center">
  <img width="1919" height="1079" alt="Peraviz 3D viewer" src="https://github.com/user-attachments/assets/19e536f2-e6df-4b70-9d41-14c48f55143b">
</p>

## Overview

**Peraviz** is an experimental open-source project developed in parallel with **Perastage**. Its goal is to become a **real-time 3D DMX visualizer** based on **MVR**, **GDTF**, **Godot 4**, and a native **C++ GDExtension** backend.

While Perastage focuses on project management, editing workflows, and MVR/GDTF authoring tasks, Peraviz is intentionally scoped as a **viewer-first** tool: load an **MVR** scene, interpret **GDTF** fixtures as reliably as possible, and render the result while reacting to **live DMX**.

Peraviz is designed to work independently. In the future, it may also become a partially integrated module inside Perastage, for example to reuse project assets and scene organization, while still remaining usable as a standalone viewer.

## Current status

Peraviz is currently in active development and should be considered experimental. It already includes the foundations for MVR loading, GDTF-based fixture interpretation, live DMX input, beam rendering, gobo parsing, and runtime validation, but it is not yet distributed as a packaged release.

### Key principles

* **MVR/GDTF as source of truth**
  Peraviz loads `.mvr` scenes and reads `.gdtf` fixture definitions to drive geometry placement, fixture metadata, DMX patching, and runtime behavior.

* **Visualization, not editing**
  The current focus is rendering, validation, and live DMX response. Editing features are expected to remain minimal, if added at all. Perastage remains the primary tool for authoring and editing workflows.

* **Correct transforms and predictable units**
  Import correctness is treated as a first-class concern. Peraviz includes debug modes and validation workflows to audit axis conventions, handedness, scale, and beam orientation.

* **Godot 4 + native C++ backend**
  Runtime setup and UI logic are implemented in Godot scripts, while MVR/GDTF parsing and heavier live data processing are handled by a native C++ GDExtension.

* **Performance-oriented architecture**
  The project aims to keep heavy calculations in C++ and pass only the data needed by Godot for rendering and interaction.

## Implemented features

### 1. MVR loading and scene reconstruction

* **Native loader: `PeravizLoader`**

  * Loads `.mvr` files and returns render nodes with id, parent id, name, type, class, local transform, asset references, and fixture metadata.
  * Loads 3DS mesh data for fixtures and scene assets when available.
  * Exposes fixture patch information.
  * Can build DMX control bindings when DMX support is enabled.

* **Standalone transform/runtime foundation**

  * Peraviz contains its own matrix and transform utilities under `native/src/`.
  * The native loader does not require Perastage at build time.
  * The viewer remains proxy-first in some geometry and material paths while runtime asset loading continues to evolve.

### 2. Runtime viewer and UI

* **Main viewer script: `scripts/load_scene.gd`**

  * Provides a file picker to load `.mvr` scenes.
  * Builds a Godot node tree from the parsed scene data.
  * Instantiates proxies and/or real assets depending on the available data.
  * Includes camera focus, selection tools, and debugging overlays.

* **Fixture selection and manual testing**

  * A manual test panel allows selecting a fixture and applying pan, tilt, and dimmer controls.
  * This is useful for validating fixture behavior even without live DMX input.

* **Visual settings**

  * A dedicated settings window exposes rendering multipliers and quality options.
  * These controls are intended to help balance visual quality and performance.

### 3. Live DMX support

* **Native Art-Net receiver**

  * Listens for Art-Net packets on the default Art-Net port.
  * Exposes per-universe DMX frames to Godot scripts.
  * Includes UI controls for enabling/disabling DMX, monitoring activity, and applying a universe offset.

* **Fixture control runtime: `scripts/dmx_fixture_runtime.gd`**

  * Builds per-fixture DMX bindings from parsed MVR/GDTF data.
  * Registers the current fixture/channel setup with the native visual runtime.
  * Consumes native sectioned visual frames with descriptor, integer, and float payloads.
  * Applies prepared transform, intensity, color, optics, wheel, and temporal sections to cached scene objects.
  * Reports unbound fixtures when scene nodes or metadata are incomplete.

### 4. Beam rendering

Peraviz currently supports two beam rendering approaches:

* **Volumetric mode**
  Intended for a more realistic haze and light-shaft look, with adjustable quality presets.

* **Lightweight mode**
  A lower-cost cone/mesh approach intended for higher FPS on weaker hardware or very dense scenes.

### 5. Gobos

* Reads gobo wheel data from GDTF files.
* Maps DMX values to gobo wheel slots.
* Supports composition of multiple active gobo wheels into a single mask texture.
* Can generate simple fallback gobo textures when media is missing or malformed.
* Projection and emission paths are currently being refactored.

### 6. Debug and validation workflow

Peraviz includes explicit tooling to make import correctness reproducible:

* **Coordinate-system audit**

  * Prints deterministic metadata about scale, up/forward axes, handedness, and beam local reference.

* **Baseline render validation**

  * Provides a checklist-driven workflow to prevent unintended transform, scale, or orientation regressions across representative test scenes.

## Build and run

### Requirements

* **Godot:** 4.2+
* **godot-cpp:** compatible with the selected Godot 4.2.x line
* **CMake**
* **C++ compiler** compatible with the native extension build
* Native dependencies used by the loader:

  * `tinyxml2`
  * `libzip`

### Build the native extension

The native project lives under `native/`.

Example debug build from the repository root:

```bash
cmake -S native -B native/build -DCMAKE_BUILD_TYPE=Debug
cmake --build native/build --config Debug
```

For Windows exports, build with vcpkg manifest mode and the static triplet so `peraviz_native.dll` is self-contained instead of depending on copied third-party DLLs:

```bash
cd native
cmake --preset windows-release-static
cmake --build --preset windows-release-static
```

The resulting native library is copied into `bin/` so the Godot editor can load it.

For the full Windows export flow, including dependency verification and Godot resource include filters, see:

```text
docs/WINDOWS_EXPORT.md
```

### Run the viewer

1. Open the Godot project from the repository root.
2. Ensure the native extension is built and present in `bin/`.
3. Run the test scene or the main viewer scene.
4. Load an `.mvr` file from disk.
5. Optionally enable DMX, connect an Art-Net source, and verify incoming universes in the DMX monitor.

## Known limitations

* **No packaged release yet**
  Peraviz is currently intended to be built from source. Official release packages will be added later.

* **GDTF quality matters**
  Peraviz follows the information present in GDTF files. If a GDTF is incomplete or inconsistent, behavior may degrade.

* **Proxy-first geometry path**
  The current milestone prioritizes correct transforms and DMX-driven behavior. High-fidelity model reuse, materials, and full fixture geometry pipelines are ongoing areas of work.

* **Gobo rendering is being refactored**
  Gobo parsing and runtime texture loading exist, but projection and emission paths are still under active development.

* **Performance work is ongoing**
  The project is moving toward a more C++-driven runtime pipeline so Godot receives preprocessed data and focuses on rendering.

## Roadmap direction

The main development priorities are:

* Improve runtime performance with larger fixture counts.
* Move heavy DMX and fixture calculations into C++.
* Keep Godot focused on rendering, UI, and scene interaction.
* Improve beam quality, haze, attenuation, and soft rendering behavior.
* Complete the gobo rendering pipeline.
* Improve material and geometry reuse for repeated fixture models.
* Strengthen validation tools for transforms, scale, and coordinate-system correctness.
* Prepare the project for future packaged releases.

## Additional documentation

More detailed notes live under `docs/`:

* `docs/NATIVE_BUILD.md` – building the GDExtension
* `docs/COORDINATE_SYSTEM.md` – coordinate mapping and auditing strategy
* `docs/BASELINE_MVR_RENDER.md` – baseline comparison workflow
* `docs/BEAM_RENDERING_MODES.md` – beam modes and performance guidance
* `docs/LIGHT_INTENSITY_INTERPRETATION.md` – interpreting intensity/exposure in the viewer
* `docs/UI_ARCHITECTURE.md` – UI module map, visibility tiers, naming, and ownership rules
* `docs/UI_GROWTH_CHECKLIST.md` – pre-feature UI checklist, including clean-screen default gate
* `README_gobos.md` – gobo parsing and runtime projection notes

## Relationship with Perastage

Peraviz and Perastage are complementary projects:

* **Perastage** focuses on MVR/GDTF project inspection, editing, organization, and export workflows.
* **Peraviz** focuses on real-time visualization, DMX response, beam rendering, and visual validation.

Peraviz may later integrate with Perastage in a modular way, but it is intended to remain usable as an independent viewer.

## License

Peraviz is licensed under the **GNU General Public License v3.0**.

See [`LICENSE.txt`](LICENSE.txt) for details.
