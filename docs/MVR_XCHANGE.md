# MVR-xchange discovery

Peraviz includes a modular Phase 1 foundation for MVR-xchange discovery. This phase is intentionally limited to finding MVR-xchange stations on the local network and presenting them in the user interface.

## Scope of Phase 1

Phase 1 discovers services advertised as `_mvrxchange._tcp.local.` and exposes the station list to Godot through the native `PeravizMvrXchangeClient` wrapper. The discovery client supports a configurable MVR-xchange group, defaulting to `Default`, and an optional bind/interface IP field reserved for interface selection.

This phase does not request, download, import, or auto-load MVR files. The disabled `Update` button in the panel is only a placeholder for a later phase.

## Product role

Peraviz remains a visualization client and viewer. Technical data authoring and authoritative MVR production stay in the upstream technical system, such as Perastage. The MVR-xchange implementation is based on the standard discovery workflow and does not introduce a proprietary Perastage-to-Peraviz bridge.

## Build option

Native discovery support is controlled by `PERAVIZ_ENABLE_MVR_XCHANGE`, which defaults to `ON` and is independent from `PERAVIZ_ENABLE_DMX`. Builds with the option disabled still run the Godot project; the panel reports that native MVR-xchange support is unavailable.
