# ADR: Peraviz and Perastage own the GDTF parser and semantic model

## Decision

Peraviz and Perastage will keep a project-owned parser and shared serialization-neutral semantic contract instead of adopting `mvrdevelopment/libMVRgdtf` as a dependency.

## Context

Perastage needs editing, validation, creation, XML serialization, archive writing, undo/redo, and round-trip preservation. Peraviz needs immutable compiled runtime tables, native DMX resolution, dirty-state generation, and renderer transport. The official library was previously evaluated and discarded because it did not fit these architecture and workflow requirements.

## Consequences

- Official GDTF specification files and the predefined attribute registry are reference inputs and compatibility fixtures.
- XML parsing details must not leak into Peraviz compiled runtime structures.
- Unknown/custom data must be preserved for Perastage round-trip workflows and diagnosed in Peraviz.
- Parser changes require shared fixtures, semantic version notes, and compatibility checks in both projects or the canonical shared source.

## Synchronization strategy

The selected approach is **A: a shared repository/module** containing specification-facing model types, canonical attribute normalization, validation diagnostics, versioned schema definitions, parser fixtures, and compatibility tests. Until that module exists, Peraviz keeps mirrored foundation code in `native/src/gdtf_runtime/` and shared fixture expectations in tests. Manual copying of large modules is forbidden; mirrored code must be generated or synchronized from the canonical source once established.
