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

- Replaced the native visual runtime setup authority with a compiled scene contract for the verified Dimmer, Pan, and Tilt slice, including multi-fixture installation, partial-capability fixtures, stable runtime IDs, weighted contributors, physical Pan/Tilt degrees, multi-byte DMX source evaluation, and complete native source registration for the runtime compiler.
- Consolidated overlapping static runtime guardrails into one current architecture check.
- Removed shell checks that preserved transitional helper names instead of validating behavior.
