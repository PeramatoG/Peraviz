# Peraviz DMX-to-visual runtime pipeline

Peraviz treats live DMX playback as a latest-state visual simulation instead of a queue of per-fixture script callbacks. The runtime goal is to keep Art-Net ingestion, universe filtering, fixture state resolution, and cooked visual diffing in native code, then let Godot apply the newest render-ready state once per frame.

## Pipeline

1. Art-Net packets update native universe snapshots.
2. Universes with no patched fixture bindings are ignored before fixture work.
3. Each patched universe tracks only the DMX offsets that affect registered fixture controls.
4. Repeated packets are coalesced with latest-state-wins semantics; if a newer universe frame arrives before the old one is consumed, only the newest frame is presented.
5. The native resolver converts fixture channel bindings into fixed-stride visual rows with normalized controls and render-ready light/material values.
6. Dirty fixture state is detected in native code before crossing into Godot.
7. Godot-side runtime code remains responsible for scene ownership and main-thread visual application, with the legacy dictionary path kept as the compatibility fallback while the native applier is completed.

## Current native frame schema

The visual runtime core emits a fixed stride of 25 floats per dirty fixture:

- fixture id
- dirty channel mask
- semantic visual change mask
- 13 normalized visual channel values
- 9 cooked render values: base energy, spot energy, inner angle, outer angle, RGB color, beam intensity, and material emission energy

Dimmer changes that cross the off/on visibility threshold are flagged as beam-topology changes. That keeps the native diff efficient for normal dimmer fades while ensuring Godot rebuilds or revalidates the reusable beam target when a prewarmed hidden beam becomes visible again.

This format is intentionally narrow and typed so it can later be applied directly by a native main-thread applier using cached ObjectIDs or RenderingServer RIDs.

## Metrics

The native core tracks cumulative counters for packets submitted, packets coalesced, universes ignored, universes considered, dirty fixtures, and skipped fixtures. These counters are designed for low-rate debug UI and benchmarks, not per-fixture frame-loop inspection.

## Threading rule

Worker threads may receive and resolve DMX snapshots, but they must not mutate active SceneTree nodes. SceneTree or resource changes must remain on the main thread unless a future RenderingServer-only path is explicitly implemented with documented thread-safe server APIs.
