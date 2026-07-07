# DMX visual runtime

The long-term live boundary is a versioned, schema-driven, sectioned protocol. The former single universal fixture row is deprecated because it cannot represent arbitrary GDTF attributes, repeated numbered families, or sparse dirty updates efficiently.

## Schema installation

A schema is installed after MVR load, selected DMX mode changes, fixture patch changes, geometry/component binding changes, or another structural rebuild. The schema contains protocol version, schema generation, stable section type IDs, row strides, and stable render/component IDs.

Godot must reject frames whose protocol version or schema generation does not match the active registry. Section offsets and strides are checked before buffer access.

## Packed buffers

- `PackedInt32Array`: protocol metadata, schema generation, section descriptors, IDs, counts, strides, masks, indexes.
- `PackedFloat32Array`: physical and render-ready numeric values.

The live loop must avoid per-fixture Dictionaries, strings, one call per fixture, section slicing, per-frame schema rebuilds, and duplicate protocols.
