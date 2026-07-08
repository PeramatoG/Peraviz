# Peraviz and Perastage GDTF semantic contract

Peraviz and Perastage must share one coherent interpretation of GDTF. A Peraviz-only interpretation is not acceptable for parsing, semantic normalization, validation, canonical attribute handling, or serialization-neutral model types.

## Ownership split

Shared semantic layer:

- normalized specification model
- canonical IDs and references
- wildcard attribute parsing
- DMX value/range types
- validation diagnostics
- official attribute registry integration
- parser regression fixtures
- serialization-neutral data structures

Perastage owns editing commands, undo/redo, creation workflows, XML serialization, archive writing, user-facing validation tools, and round-trip preservation.

Peraviz owns immutable compiled fixture runtime tables, DMX lookup programs, physical-state resolution, dirty-state generation, the sectioned C++/Godot visual protocol, and renderer bindings.

## Versioning and tests

The semantic contract has an explicit version. Changes to shared semantics require synchronized updates, compatibility notes, and deterministic test vectors. At minimum, both projects must be able to normalize the same GDTF fixture and produce equivalent attribute identities, geometry references, DMX ranges, channel functions, wheel-slot references, ModeMaster/Relation records, and diagnostics.

## Divergence prevention

- Do not manually copy large semantic modules between repositories.
- Do not add broad substring guessing as canonical interpretation.
- Preserve unknown/custom attributes and report them.
- Keep Perastage editor/UI and Peraviz Godot/render code out of the shared layer.


## Perastage review notes

The current Perastage repository review found GDTF mutation and canonicalization ownership documented around `core/gdtf_canonicalizer`, `core/gdtf_mutation_audit`, truss GDTF generation, MVR export patching, dictionary lookup, and viewer3d GDTF loading. This confirms that Perastage already has editor/export responsibilities that must remain outside the shared semantic layer while sharing canonical parsing, validation, and normalized attribute behavior with Peraviz.


## Deterministic semantic contract artifacts
Checkpoint 2 adds neutral contract vectors under `docs/contract/gdtf/`. Perastage can run the same GDTF fixtures through its parser/compiler and compare normalized attributes, wildcard indexes, DMX functions, wheel references, physical ranges, and diagnostics without depending on Godot renderer details.

## Runtime contract checkpoint

Peraviz now treats the typed section protocol as the live renderer contract and the serialization-neutral compiled fixture model as the shared semantic target for Peraviz and Perastage. Contract snapshots must continue to include fixture type, selected mode, attributes, wildcard indexes, geometry paths, channel functions, channel sets, physical ranges, wheel data, resources, relations, and diagnostics. The native component runtime is prepared to consume these compiled identities without introducing Godot renderer state into shared GDTF semantics.
