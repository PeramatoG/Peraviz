# Peraviz v0.x.x

Changes since the previous Peraviz release.

## Highlights

- Improved documentation reliability by consolidating the runtime architecture guidance into one concise source of truth.

## Improvements
- Added a Beam Appearance Baseline that preserves GDTF BeamType provenance, uses the official missing-value Wash default, applies visible core/field beam resources for hard or soft edges, keeps long-beam extinction readable, and separates surface-light falloff modes.

- Added a 1 m reference cube toggle in the viewer toolbar so MVR scene scale can be checked directly in Godot.
- Clarified the current native sectioned visual-frame runtime and the remaining transitional setup bridge.
- Simplified contributor and agent guidance so maintainers can focus on enforceable rules and current workflows.

## Documentation

- Removed overlapping architecture documents and stale migration history.
- Updated release notes to present user-visible changes first and keep internal architecture notes brief.

## Internal changes

- Added the first native BeamOptics foundation: setup-time Beam profiles, native Zoom ChannelFunction compilation, target-oriented BeamOptics rows, cached optics targets, official/model/render aperture-radius diagnostics, and parametric Lightweight Prism near/far spread updates, corrected lens-side/far-end axial radius mapping, and packed shader instance parameters to stay within Godot renderer limits, while using explicit GDTF BeamRadius as the preferred beam-only near-aperture source when available.
- Kept BeamOptics scale corrections limited to beam geometry and preserved imported 3D model sizes unchanged.
- Consolidated the verified Dimmer, Pan, and Tilt runtime around parser-owned selected-mode ChannelFunction records, stable native component/render-target IDs, target-ID section application, capability-derived dirty masks, and diagnostics for unsupported domains. Restored robust selected-mode `DMXChannel` traversal, explicit/inferred full-resolution ChannelFunction ranges, compiled-scene-owned universe submission, truthful target-application counts, setup/live skip diagnostics, explicit native-loader versus renderer-target-registry wiring, mandatory manifest installation, full-node-index canonical target registration through a focused `NativeRendererTargetRegistry`, detailed target-registry/unlinked-fixture diagnostics, property-oriented native Dimmer state, per-target intensity rows, normalized-versus-physical evaluation, Lightweight Prism renderer target resources, native Dimmer target resource prewarming/mutation reporting, safe cached lens-material application, and removal of the native DPT bound-fixture gate in the compiled path. BeamOptics now corrects the Lightweight Prism lens-side/far-end radius mapping while preserving native Dimmer, Pan, and Tilt behavior.
- Consolidated overlapping static runtime guardrails into one current architecture check.
- Removed shell checks that preserved transitional helper names instead of validating behavior.

## Fixes

- Balanced projected output across multi-Beam fixtures by weighting final Beam emission and alpha per emitter while preserving single-Beam appearance and existing renderer intensity controls.
- Kept beam shader parameter usage within Godot renderer limits so Beam rendering initializes reliably on the clustered renderer.
- Reduced overly verbose DMX diagnostics in normal logs and compacted inline monitor summaries so diagnostic text no longer stretches panels across the viewer.
- Corrected visible beam geometry so the near aperture uses GDTF BeamRadius or exact Beam-owned lens measurement, long beams use an explicit 75 m visual length by default, and Lightweight/Volumetric renderers share the same full-angle far-spread contract without changing fixture or scene scale.
