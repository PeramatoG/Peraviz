# Peraviz v0.x.x

Changes since the previous Peraviz release.

## Highlights

- Improved documentation reliability by consolidating the runtime architecture guidance into one concise source of truth.

## Improvements

- Consolidated the native GDTF color MVP for Beam targets: supported additive and CMY color ChannelFunctions now preserve target-local chromaticity and scalar color gain, support CMY transmission below 1.0 and RGBW gain above 1.0, and emit one renderer-ready `EmitterColor` row only when the cooked output changes.
- Added a 1 m reference cube toggle in the viewer toolbar so MVR scene scale can be checked directly in Godot.
- Clarified the current native sectioned visual-frame runtime and the remaining transitional setup bridge.
- Simplified contributor and agent guidance so maintainers can focus on enforceable rules and current workflows.

## Documentation

- Documented the corrected native color MVP contract, target-local renderer state ownership, Peraviz fallback color approximations, and deferred physical color features.

- Removed overlapping architecture documents and stale migration history.
- Updated release notes to present user-visible changes first and keep internal architecture notes brief.

## Internal changes

- Native GDTF color-wheel support now includes a verified seated discrete selection slice: parsed wheel slots, exact WheelSlotIndex bindings, compiled palettes, native DMX evaluation, WheelSelection rows, packed-scene transfer, and target-local renderer mutation for SpotLight, beam and lens resources. Indexed split, spin, random and Audio remain deferred.

- Expanded the native uniform color pipeline with parser-owned physical GDTF color resources, linked emitter/filter ColorCIE and spectral preparation, native direct CIE/CCT/Tint evaluation, and documentation for standard physical paths versus Peraviz fallbacks while preserving the compact renderer color payload.

- Added the first native BeamOptics foundation: setup-time Beam profiles, native Zoom ChannelFunction compilation, target-oriented BeamOptics rows, cached optics targets, official/model/render aperture-radius diagnostics, and parametric Lightweight Prism near/far spread updates, corrected lens-side/far-end axial radius mapping, and packed shader instance parameters to stay within Godot renderer limits, while using explicit GDTF BeamRadius as the preferred beam-only near-aperture source when available.
- Kept BeamOptics scale corrections limited to beam geometry and preserved imported 3D model sizes unchanged.
- Kept renderer color state target-local so Dimmer, Color and BeamOptics updates reuse cached per-Beam color/gain/intensity without fixture-wide color bleed.
- Consolidated Dimmer, Pan, and Tilt runtime around parser-owned selected-mode ChannelFunction records, stable native component/render-target IDs, target-ID section application, capability-derived dirty masks, and diagnostics for unsupported domains. Restored robust selected-mode `DMXChannel` traversal, explicit/inferred full-resolution ChannelFunction ranges, compiled-scene-owned universe submission, truthful target-application counts, setup/live skip diagnostics, explicit native-loader versus renderer-target-registry wiring, mandatory manifest installation, full-node-index canonical target registration through a focused `NativeRendererTargetRegistry`, detailed target-registry/unlinked-fixture diagnostics, property-oriented native Dimmer state, per-target intensity rows, normalized-versus-physical evaluation, Lightweight Prism renderer target resources, native Dimmer target resource prewarming/mutation reporting, safe cached lens-material application, and removal of the native DPT bound-fixture gate in the compiled path. BeamOptics now corrects the Lightweight Prism lens-side/far-end radius mapping while preserving native Dimmer, Pan, and Tilt behavior.
- Consolidated overlapping static runtime guardrails into one current architecture check.
- Removed shell checks that preserved transitional helper names instead of validating behavior.
- Fixed the native renderer target registry regression test so it parses cleanly under current Godot GDScript scope rules.

## Fixes

- Fixed Art-Net startup on Windows when another compatible lighting application is already bound to UDP port 6454, allowing Peraviz DMX reception to start without requiring users to restart the other application.
- Preserved multi-emitter photometric brightness when applying native Color rows so color gain now scales each Beam output’s existing luminous-flux distribution instead of overwriting every emitter with target-level energy.
- Beam intensity now respects each exact GDTF Beam geometry LuminousFlux value, including the official 10000 lm default, so multi-lens fixtures sum their declared projected output instead of repeating one full fixture-wide beam per lens. None and Glow beams remain emission-only and no longer add projected cone output.
- Reduced overly verbose DMX diagnostics in normal logs and compacted inline monitor summaries so diagnostic text no longer stretches panels across the viewer.
- Corrected visible beam geometry so the near aperture uses GDTF BeamRadius or exact Beam-owned lens measurement, long beams use an explicit 75 m visual length by default, and Lightweight/Volumetric renderers share the same full-angle far-spread contract without changing fixture or scene scale.
