# Peraviz gobo support

This document summarizes how Peraviz parses and loads gobo data from GDTF fixtures.

## Parsing flow

- Peraviz reads `description.xml` from each `.gdtf` archive.
- Wheel images are discovered from `FixtureType/Wheels/Wheel/Slot` (and exporter variant `WheelSlot`).
- `Slot/@MediaFileName` is resolved as a resource stem and loaded from the archive, preferring:
  - `wheels/<MediaFileName>.png`
  - plus compatible fallback paths (`wheels/images/...` and stem-based archive lookup).
- DMX-to-slot mapping is parsed from `ChannelFunction/ChannelSet` using:
  - `ChannelSet/@DMXFrom`
  - `ChannelSet/@DMXTo` (optional, inferred from next range when missing)
  - `ChannelSet/@WheelSlotIndex`

Per GDTF, `WheelSlotIndex` is normalized to wheel slot order. Fixtures may also
repeat the same slot across different DMX windows (for example to reuse one gobo
with index/spin/shake behaviors). Runtime range matching therefore keeps fixture
`ChannelSet` declaration precedence: when more than one range matches the DMX
value, the latest matching row wins.

Peraviz accepts both common `ChannelSet` DMX encodings found in real GDTF files:
values authored as absolute DMX positions and values authored relative to the
parent `ChannelFunction` DMX window.

## DMX binding rules

- Gobo binding focuses on selector channels (`Gobo1`, `Gobo1Pos`, etc.).
- Non-selector channels are ignored for selection (`Spin`, `Shake`, `Time`, `Speed`, `Rotate`, etc.).
- Per-fixture bindings include all discovered gobo selector wheels (`gobo_wheels`) and keep wheel `1` mirrored as compatibility keys (`gobo1_*` / `gobo_*`).

## Transitional compatibility behavior

- Legacy inspection/projector code can still resolve an active gobo slot from cached DMX metadata, but it is not authoritative for the native seated live path.
- Slot textures are loaded and cached for each fixture.
- When media is missing or invalid, a temporary fallback gobo texture can be generated for DMX/debug validation.
- Legacy experiments may compose multiple cached wheel textures; the controlled native static baseline described below owns new seated composition behavior.

> Note: projection/emission logic was intentionally removed from Peraviz runtime. The loaded textures remain available in fixture metadata for upcoming refactors.

## Native static seated slice

- Native selected-mode programs resolve exact indexed wheel and one-based slot identity and emit dirty-only `GoboSelection` rows with stable numeric asset and Beam target IDs.
- Godot installs original PNGs and normalized vector topology once per scene generation. Missing media publishes no stale path and open slots clear the prism with asset ID zero.
- One seated binary asset uses reusable normalized topology whose cache identity excludes zoom, beam length, dimmer, color, and fixture UUID.
- Two or more static seated binary assets use one deterministic cached mask multiplication, one bounded vectorization under the 280-point limit, and one normalized composed topology per unique combination.
- Original and composed masks remain available for future projection. Surface projectors and independently rotating, indexing, or shaking multi-wheel composition are not implemented.

The production MVR/GDTF lifetime smoke test requires a built GDExtension. Generate its sanitized archive with `python3 tests/integration/generate_mvr_gdtf_lifetime_fixture.py /tmp/peraviz-lifetime.mvr`, then run `godot --headless --path . --script res://tests/integration/test_mvr_gdtf_asset_lifetime_smoke.gd -- --mvr /tmp/peraviz-lifetime.mvr`.
