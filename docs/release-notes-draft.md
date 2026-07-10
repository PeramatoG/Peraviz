# Peraviz v0.x.x

Changes since the previous Peraviz release.

## Highlights

- Improved documentation reliability by consolidating the runtime architecture guidance into one concise source of truth.

## Improvements

- Clarified the current native sectioned visual-frame runtime and the remaining transitional setup bridge.
- Simplified contributor and agent guidance so maintainers can focus on enforceable rules and current workflows.

## Documentation

- Removed overlapping architecture documents and stale migration history.
- Updated release notes to present user-visible changes first and keep internal architecture notes brief.

## Internal changes

- Consolidated the verified Dimmer, Pan, and Tilt runtime around parser-owned selected-mode ChannelFunction records, stable native component/render-target IDs, target-ID section application, capability-derived dirty masks, and diagnostics for unsupported domains. Restored robust selected-mode `DMXChannel` traversal, explicit/inferred full-resolution ChannelFunction ranges, compiled-scene-owned universe submission, truthful target-application counts, setup/live skip diagnostics, explicit native-loader versus renderer-target-registry wiring, mandatory manifest installation, full-node-index canonical target registration, detailed target-registry/unlinked-fixture diagnostics, property-oriented native Dimmer state, per-target intensity rows, normalized-versus-physical evaluation, Lightweight Prism renderer target resources, native Dimmer target resource prewarming/mutation reporting, safe cached lens-material application, and removal of the native DPT bound-fixture gate in the compiled path.
- Consolidated overlapping static runtime guardrails into one current architecture check.
- Removed shell checks that preserved transitional helper names instead of validating behavior.
