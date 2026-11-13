# MAC Quantum Wash Basic: strobe rate versus frame sampling

Investigation date: 2026-11-13. Runtime reference: `873d80e`. This investigation changes no production waveform, interpolation or source archive. The user's reported cadence was approximately 45 FPS; their exact source archive and DMX value have not been supplied.

## Main result

Two distinct mechanisms can produce a slow-looking strobe. Both were reproduced, but the inspected Quantum Wash profile supplies a particularly direct explanation: increasing DMX from **199 to 200 changes the resolved physical frequency from 20 Hz to 1 Hz**, independently of render cadence.

The inspected source is [Perastage's MAC Quantum Wash GDTF](https://github.com/PeramatoG/Perastage/blob/47b480220688ee057e5288aa0216d157bdb0cb24/library/fixtures/Martin_Professional%40MAC_Quantum_Wash%40Perastage.gdtf), mode `Basic`, pinned to commit `47b480220688ee057e5288aa0216d157bdb0cb24`. Git blob: `6816edf404a467d95fc421575e98479393d0080f`; SHA-256: `3b7bbf13bfc535de0aede095bcab82c2101392c5c7da46de51c7c888a6ae2e4e`. The original file still matches that blob after testing. This is a public sample, not proof that the user's archive is identical.

## Profile interpretation

The regular strobe function declares DMX 50–200 and physical frequency 1–20 Hz. Its ChannelSets start at 50, 51, 125, 126 and 200. None supplies physical endpoints. The function's inherited endpoints therefore apply separately to each set; singleton sets currently use PhysicalFrom. A label such as Medium or Fast does not replace physical metadata.

[GDTF 1.2 Table 61](https://gdtf-share.com/help/developers/gdtf_1_2/file-format-definition/index.html) defines parent endpoint inheritance. These declarations should be distinguished from [Martin's Basic-mode DMX chart](https://www.martin.com/en-US/site_elements/mac-quantum-wash-user-guide), which describes 50–200 as slow-to-fast strobe and 211–255 as slow-to-fast random strobe. The apparent resets are therefore an authoring/interpretation mismatch with that intended progression, not evidence of a reversed clock. A singleton with inherited unequal endpoints cannot describe two distinct physical endpoint values at the same DMX input; explicit authored endpoints avoid that ambiguity.

The production archive importer, selected-mode compiler, setup codec, native evaluator and cached trace produced:

| Raw channel 1 | Selected set | Physical frequency | Waveform |
| ---: | --- | ---: | --- |
| 124 | 51–124 | 20 Hz | Strobe |
| 125 | 125–125, Medium | 1 Hz | Strobe |
| 126 | 126–199 | 1 Hz | Strobe |
| 198 | 126–199 | 19.739726 Hz | Strobe |
| 199 | 126–199 | 20 Hz | Strobe |
| 200 | 200–200, Fast | 1 Hz | Strobe |
| 201–210 | Open | No periodic modulation | Open |
| 254 | 234–254 | 20 nominal Hz | Approximate Random |
| 255 | 255–255, Fast | 1 nominal Hz | Approximate Random |

No Duration subphysical value is supplied, so this runtime uses its existing standard 25 ms duration. No ModeMaster or DMXProfile explains these regular-strobe resets. Random event timing remains a documented approximation.

## Controlled FPS comparison

The same real native publication was fed into `presentation::ShutterPlayback`, with frozen DMX, phase and duration. Thirty seconds of deterministic timestamps were sampled. There were no source reevaluations during the holds. This checks the real CPU presentation envelope, not measured monitor refresh or GPU pixels.

| DMX | Native frequency | At 30 FPS: visible rising edges/s | At 45 FPS | At 120 FPS |
| ---: | ---: | ---: | ---: | ---: |
| 199 | 20 Hz | 10 | 20 | 20 |
| 200 | 1 Hz | 0 at this locked sample phase | 1 | 1 |

At 20 FPS, the same 20 Hz signal froze dark at the tested phase. At 15 FPS it produced five visible flashes/s. This reproduces temporal aliasing without any parsing change. At stable 45 FPS, both the 25 ms on window and the shortest regular off window are longer than a frame interval, so this particular regular 1–20 Hz profile does not require an apparent 20-to-1 Hz reversal. Average FPS alone does not establish actual frame spacing; intermittent long frames can still miss flashes. Shorter pulses and random timing have different sampling requirements.

`load_scene.gd::_process` advances temporal presentation once per process frame. `ShutterPlayback::tick` samples the exact instantaneous `shutter_envelope`; it does not integrate an exposure interval. The native clock continues during DMX hold, so increasing Art-Net packet rate does not remove this presentation limitation.

## Similar reports and confirmed fixes

- [Capture 2025.0.34 revision notes](https://www.capture.se/Products/2025-Revision-History), released 2025-05-13, explicitly record a fix for incorrect strobe appearance at certain combinations of strobe and frame rates, plus separate duration/stuck-state bugs. The [support thread](https://www.capture.se/Support/Forum/aft/10572/afpg/2) includes a user's confirmation that the update solved their issue. This is a verified product precedent; its proprietary implementation is not published and cannot be assumed to be a particular filtering algorithm.
- [WYSIWYG shutter/strobe report](https://forum.malighting.com/forum/thread/58264-wysiwyg-shutter-and-strobe-problem/?postID=70170): users reported irregular shutter visualization even with high displayed FPS. One reported improvement after changing rendering settings. This is corroborating user experience, not a verified universal fix or a diagnosis of Peraviz.
- [RED's technical explanation of temporal aliasing](https://www.reddigitalcinema.com/red-101/cinema-temporal-aliasing) describes apparent slowing/reversal and missed strobe beats. Increasing sample cadence or applying temporal filtering addresses sampling artifacts; no finite-rate display can reproduce arbitrary short or fast pulses exactly.

## Recommended resolution

1. Compare **199 versus 200** and **254 versus 255** in the user's exact archive. If the high endpoint becomes slow even in a small scene, inspect its set endpoints first. The production reproduction establishes this behavior for the pinned sample.
2. Resolve the intended physical progression in the source definition, with explicit ChannelSet physical endpoints or a function-only continuous interval where appropriate. A synthetic regression verifies that explicitly authored endpoints can produce a continuous 1–20 Hz mapping. That is a tested authoring mechanism, not hardware calibration or authorization to rewrite the original archive. Do not hardcode Quantum Wash ranges or globally ignore valid ChannelSets.
3. For unchanged resolved Hz that look different as scene cadence changes, stabilize/increase actual presentation and display cadence. Temporal exposure integration/antialiasing is an established mitigation, but it averages energy and can make rapid strobes look steadier; it cannot display every flash beyond the display's capacity. Any future Peraviz approximation must be explicit and preserve exact native timing. Do not alter frequency/duration silently or assume generic Godot TAA fixes parameter sampling.

## Existing diagnostic access

The **Copy shutter diagnostic** button exists in the Debug section (`FixtureDebugController::configure`). It copies a bounded report for the selected fixture. Currently the trace must be enabled before import with `PERAVIZ_SHUTTER_TRACE=<fixture UUID>` and the runtime must be in serial diagnostic mode. Merely pressing the button does not enable metadata collection retrospectively; without setup it copies an unavailable reason and the selected UUID. This is developer-oriented and is not required for the 199/200 comparison.

## Regression coverage and commands

`test_shutter_cadence_and_label_sets` extends the existing native suite with frozen 20 Hz playback at 15/20/30/45/120 FPS, source-hold invariance, inherited singleton resets, and an explicitly authored continuous physical interval. It uses synthetic public XML; no vendor assets are committed.

```sh
cmake --build native/build --target peraviz_native_visual_runtime_tests --parallel 5
native/build/peraviz_native_visual_runtime_tests --shutter
ctest --test-dir native/build -R '^peraviz_native_visual_runtime_tests$' --output-on-failure --timeout 120
bash tests/check_no_large_files.sh
bash tests/check_runtime_architecture.sh
git diff --check
```

The optional external-archive reproduction used a temporary MVR wrapper and a standalone probe linked to the existing native test objects. It imported the untouched Quantum Wash file, serialized/deserialized the production setup, evaluated 23 DMX values and sampled 30-second holds at six cadences. The probe passed and confirmed the original Git blob hash. No production rendering policy was changed; the user's exact archive and actual frame-time sequence remain the final checks for their scene.

Validation result: the focused shutter entry and the complete native visual-runtime CTest target passed (1/1 CTest target, 2.97 s). Architecture, file-size and whitespace checks passed; existing large-file advisories remain. No Godot script or production C++ implementation changed in this investigation.
