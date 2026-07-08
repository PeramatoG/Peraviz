# DMX visual runtime

## Purpose

This document defines the C++ to Godot runtime transport contract for live visualization.

It covers:

- Structural schema installation.
- Stable IDs.
- Live typed deltas.
- Packed integer and float payloads.
- Section descriptors.
- Validation.
- Dirty-state behavior.
- Error handling.
- Threading and ownership.
- Migration constraints.
- Completion criteria.

This document does not define GDTF parsing semantics. Those belong in `docs/gdtf-runtime-architecture.md`.

This document does not describe temporary compatibility checkpoints as final architecture.

## Architectural objective

The runtime boundary is:

- Versioned.
- Schema-driven.
- Typed.
- Packed.
- Batched.
- Sparse.
- Dirty-state based.
- Free of per-fixture Dictionaries in the live path.
- Free of magic channel-type numbers in the final production path.
- Independent from raw GDTF and raw DMX semantics on the Godot side.

The boundary is divided into two distinct contracts:

1. Structural installation.
2. Live render deltas.

Godot's sectioned visual-frame applier now routes GeometryTransform, EmitterIntensity, EmitterColor, BeamOptics, WheelSelection, WheelMotion, and TemporalOutput rows directly into specialized apply calls. It keeps per-fixture render state only as cached section state and no longer reconstructs a 25-float universal fixture row or calls the fixed-row apply entry point from the sectioned path.

## Component-oriented runtime checkpoint

The native visual runtime now stores live values in component-oriented semantic state instead of a fixed compact-control array. Incoming setup bindings are compiled into semantic channel programs, dirty state is grouped by render domain, and section rows are emitted directly into typed integer and float buffers for GeometryTransform, EmitterIntensity, EmitterColor, BeamOptics, WheelSelection, WheelMotion, and TemporalOutput. Godot section consumption no longer rebuilds a universal fixture-state dictionary in the section applier.

This checkpoint keeps the existing Godot setup bridge while removing the fixed native state model from the active C++ runtime. The remaining migration work is to feed these compiled programs directly from parser-owned `CompiledGdtfFixtureType` data instead of setup-time legacy binding dictionaries.

## Direct render-domain applier correction

The sectioned Godot applier no longer calls the universal lighting apply method for every non-transform row. EmitterIntensity owns visibility, light energy, beam intensity, and material emission energy; EmitterColor owns light/material/beam color; BeamOptics owns supported spot and beam angle updates; WheelSelection and WheelMotion update gobo topology or motion without changing intensity; TemporalOutput records shutter/strobe state without changing beam energy. This prevents an initial frame with multiple sections from turning the dimmer on and then immediately turning the beam off with partial zero-filled rows.
