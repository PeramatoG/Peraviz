# MAC Quantum Wash Basic: inherited shutter mapping and frame sampling

Investigation updated: 2026-11-14. The user reported approximately 45 FPS and supplied grandMA3 readouts of Slow=50, Medium=125, Fast=200 and an encoder adjustment to 198. They confirmed the same MVR and reported that Fast works on the real fixture and in grandMA3's visualizer. Console/network traffic was reproduced locally, not captured from their show.

## Correction and compatibility decision

Peraviz previously restarted the full parent physical interval within every ChannelSet, including label-only sets. Single-value sets selected PhysicalFrom, so Slow, Medium and Fast all became 1 Hz; moving from Fast=200 to 198 immediately produced approximately 19.74 Hz. All raw updates arrived and were evaluated; this particular symptom was a physical-mapping error, independent of FPS or the magnitude of a preset jump.

**Sets that omit both physical attributes now retain the parent ChannelFunction's physical mapping.** The native setup compiler projects the parent curve onto the set's effective inclusive endpoints after clipping. A label-only singleton therefore receives the parent's value at that DMX input, not an arbitrary choice between the parent's two endpoints. Existing set-local evaluation and the numeric setup contract can consume those projected endpoints directly. No new live evaluator, protocol version, per-frame work or fixture-name exception is needed.

Sets with either physical attribute explicitly supplied retain their own local mapping. A missing opposite endpoint still inherits the corresponding parent endpoint independently. Explicit descending, fixed and discontinuous physical intervals remain authored behavior; malformed supplied attributes are not treated as omitted. An explicitly authored singleton still uses its PhysicalFrom value. Unnamed prefixes and clipped label-only sets retain the same parent curve.

This is a documented compatibility decision, authorized after the hardware/grandMA3 comparison. It resolves the inherited-domain ambiguity in favor of **Use Parent Physical** and does not claim access to grandMA3's interpolation implementation. The earlier audit's claims that these resets were intentional, or established a malformed fixture, were too strong and have been corrected.

## Source and corrected results

The source is [Perastage's MAC Quantum Wash GDTF](https://github.com/PeramatoG/Perastage/blob/47b480220688ee057e5288aa0216d157bdb0cb24/library/fixtures/Martin_Professional%40MAC_Quantum_Wash%40Perastage.gdtf), mode `Basic`, pinned to commit `47b480220688ee057e5288aa0216d157bdb0cb24`. Git blob: `6816edf404a467d95fc421575e98479393d0080f`; SHA-256: `3b7bbf13bfc535de0aede095bcab82c2101392c5c7da46de51c7c888a6ae2e4e`. The original archive was not changed. User confirmation associates it with their MVR; their local MVR was not independently hashed.

The regular strobe function spans 50–200 with PhysicalFrom=1 and PhysicalTo=20 Hz. Its sets start at 50, 51, 125, 126 and 200, with no physical overrides. The corrected mapping is `1 + 19 * (raw - 50) / 150`.

| DMX | Selection | Previous Hz | Corrected Hz |
| ---: | --- | ---: | ---: |
| 50 | Slow | 1 | 1 |
| 124 | Unnamed interval | 20 | 10.373333 |
| 125 | Medium | 1 | 10.5 |
| 126 | Unnamed interval | 1 | 10.626667 |
| 198 | Encoder below Fast | 19.739726 | 19.746667 |
| 199 | Before Fast | 20 | 19.873333 |
| 200 | Fast | 1 | 20 |
| 201–210 | Open | No periodic modulation | No periodic modulation |
| 254 | Random interval | 20 nominal | 19.568182 nominal |
| 255 | Random Fast | 1 nominal | 20 nominal |

Random timing remains an explicitly documented approximation. Regular strobe retains the existing 25 ms default duration because this source supplies no Duration override. [Martin's Basic-mode DMX chart](https://www.martin.com/en-US/site_elements/mac-quantum-wash-user-guide) describes 50–200 and 211–255 as slow-to-fast regular/random strobe respectively.

## Standard boundaries and evidence

[GDTF 1.2 Tables 60/61](https://gdtf-share.com/help/developers/gdtf_1_2/file-format-definition/index.html) define the end as the next start minus one, or the parent maximum. The inclusive set intervals are 50–50, 51–124, 125–125, 126–199 and 200–200. The next function starts at 201. There is no floating-point margin, overlap or fine-byte conversion in this one-byte source.

Table 61 specifies parent endpoint defaults but does not explicitly work through a label-only singleton with unequal inherited endpoints or resolve the interpolation domain. Simply swapping to PhysicalTo would make Slow, Medium and Fast all 20 Hz; it cannot explain the three expected speeds.

The official [Builder ChannelSet help](https://gdtf-share.com/help/users/gdtf_builder/dmx/addchannelset/index.html) documents default **Use Parent Physical**, and sets for minimum/maximum strobe speed. The official [libMVRgdtf implementation](https://github.com/mvrdevelopment/libMVRgdtf/blob/9f5a6420c72f24fdd249cfe8133f257026c5590b/src/GDTFManager.cpp#L6834) preserves that distinction: omitted physical attributes leave `fSetPhysical` false, `GetUsePhysicalFromParent()` reports its inverse, and serialization omits physical attributes in that case. Its physical getters are not a renderer/interpolation oracle. These sources support the compatibility decision; the specific projected-domain rule is stated above rather than presented as an explicit normative formula.

## Preset ingress and production reproduction

The original loopback probe accepted all 14 one-shot packets even before the fix: 50→200 arrived, but resolved to the same 1 Hz and legitimately required no new effective-output publication. Moving to 199 then appeared to unlock Fast. There is no magnitude threshold: mailbox filtering compares subscribed bytes for inequality, while sequence tracking compares packet sequence numbers, not channel values.

After the correction, a loopback UDP reproduction imported the untouched archive, compiled and serialized/deserialized the real setup, and exercised the production receiver, ArtDmx parser/sequence tracker, mailbox, coordinator, evaluator and `ShutterPlayback` ingestion. All **16** packets were accepted with zero out-of-order drops. Each change used one packet. The sequence included 50→125→200→198→199, 50→199, 0→255 and 255→0. Slow/Medium/Fast immediately published 1/10.5/20 Hz; 200→198 published approximately 19.746667 Hz. Random Fast=255 published nominal 20 Hz. No encoder packet was needed to activate a preset.

The separate archive probe evaluated 23 DMX values, then sampled 30-second holds at 15/20/30/45/60/120 FPS with the actual native playback. Source-evaluation counts stayed unchanged during all holds. This is a numerical production-path check, not measured GPU pixels or real-hardware frequency calibration.

## Frame sampling remains a separate limitation

A frozen native 20 Hz signal with 25 ms flashes resolves 20 visible rising edges/s at stable 45/120 FPS, 10 at 30 FPS and 5 at 15 FPS. At 20 FPS, the tested phase locks dark. These deterministic results remain unchanged by the mapping correction. An average of 45 FPS does not establish frame spacing; intermittent stalls, shorter pulses and random timing can miss events.

`load_scene.gd::_process` advances presentation once per process frame; `ShutterPlayback::tick` samples the instantaneous envelope rather than integrating exposure. Increasing Art-Net packet rate cannot remove that sampling limitation. No frequency, duration, duty or presentation policy was changed to make the result look smoother. Exposure integration is a possible future explicit approximation, not part of this fix.

## Similar reports and confirmed fixes

- [Capture 2025.0.34 revision notes](https://www.capture.se/Products/2025-Revision-History), released 2025-05-13, explicitly record a fix for incorrect strobe appearance at certain combinations of strobe and frame rates, plus separate duration/stuck-state bugs. The [support thread](https://www.capture.se/Support/Forum/aft/10572/afpg/2) includes a user's confirmation that the update solved their issue. This is a verified product precedent; its proprietary implementation is not published and cannot be assumed to be a particular filtering algorithm.
- [WYSIWYG shutter/strobe report](https://forum.malighting.com/forum/thread/58264-wysiwyg-shutter-and-strobe-problem/?postID=70170): users reported irregular shutter visualization even with high displayed FPS. One reported improvement after changing rendering settings. This is corroborating user experience, not a verified universal fix or a diagnosis of Peraviz.
- [RED's technical explanation of temporal aliasing](https://www.reddigitalcinema.com/red-101/cinema-temporal-aliasing) describes apparent slowing/reversal and missed strobe beats. Increasing sample cadence or applying temporal filtering addresses sampling artifacts; no finite-rate display can reproduce arbitrary short or fast pulses exactly.

## Regression coverage and validation

The focused native regressions cover the Quantum-style label pattern, Slow/Medium/Fast one-shot ArtDmx changes, adjacent encoder values, coalesced bursts, unchanged effective-output suppression for deliberately explicit equal endpoints, codec round trips, ascending/descending inherited curves at 8/16/24/32 bits, clipped sets, unnamed prefixes and one-sided explicit overrides. Public synthetic XML is used in CI; no vendor archive is committed.

```sh
export PATH=/workspace/.peraviz-tools/python/bin:$PATH
cmake --build native/build --parallel 5
ctest --test-dir native/build --output-on-failure --timeout 120
native/build/peraviz_native_visual_runtime_tests --shutter
native/build/peraviz_native_visual_runtime_tests --shutter-corpus /workspace/work/perastage-fixtures
bash tests/check_no_large_files.sh
bash tests/check_runtime_architecture.sh
git diff --check
```

Full native build and **15/15 CTests passed** (9.31 s); the focused shutter entry and both external archive probes passed. The optional corpus passed for **7 archives / 17 modes**. Godot `test_native_shutter.gd` passed in both Forward+ and Compatibility; `test_shutter_authority.gd` passed in Forward+. The Godot fixture now covers inherited Slow/Medium/Fast singletons and the existing explicitly fixed intervals, checking cached shaft/lens output and trace provenance. File-size, architecture and whitespace checks passed with existing large-file advisories. The initial shell build lacked CMake on PATH; the command above resolved it using the existing tool installation.

Godot commands (with `XDG_CACHE_HOME`, `XDG_DATA_HOME`, `XDG_CONFIG_HOME` directed to `/workspace/.peraviz-tools/cache`, `data`, `config`):

```sh
GODOT=/workspace/.peraviz-tools/godot/Godot_v4.7.1-stable_linux.x86_64
"$GODOT" --headless --audio-driver Dummy --rendering-method gl_compatibility --path . --script res://tests/gdscript/test_native_shutter.gd
"$GODOT" --headless --audio-driver Dummy --rendering-method forward_plus --path . --script res://tests/gdscript/test_native_shutter.gd
"$GODOT" --headless --audio-driver Dummy --rendering-method forward_plus --path . --script res://tests/gdscript/test_shutter_authority.gd
```

## Diagnostic access

The existing **Copy shutter diagnostic** button is developer-oriented: `PERAVIZ_SHUTTER_TRACE=<fixture UUID>` and `PERAVIZ_NATIVE_EVALUATION=serial` must be set before import. Pressing the button does not retrospectively enable trace metadata. It is not required to reproduce or benefit from this mapping correction. Restart the updated build and reimport the MVR so its setup is recompiled.
