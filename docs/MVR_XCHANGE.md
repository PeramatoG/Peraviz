# MVR-xchange support

Peraviz includes modular MVR-xchange support so it can act as a viewer/client for an upstream technical data source such as Perastage.

## Phase 1: discovery

The first phase discovers services advertised as `_mvrxchange._tcp.local.` and exposes them through the native `PeravizMvrXchangeClient` wrapper. The UI supports the MVR-xchange group preference, defaulting to `Default`, and an optional bind/interface IP preference for installations that need interface selection.

## Current phase: TCP join and manual MVR transfer

The current phase extends the same native client with TCP client behavior for the first real transfer workflow:

1. Peraviz registers its own `_mvrxchange._tcp.local.` mDNS service with `StationName` and `StationUUID` TXT records, as required by TCP mode.
2. Peraviz discovers peer stations through the existing mDNS discovery path.
3. The controller selects a station and asks the native client to join it asynchronously.
4. The native client sends `MVR_JOIN` using the official MVR-xchange TCP package header and tracks `MVR_JOIN_RET` / `MVR_COMMIT` information when it is received.
5. The local Peraviz TCP service also accepts inbound `MVR_JOIN` and `MVR_COMMIT` messages from peer stations that discovered Peraviz.
6. The UI enables `Update` only after a joined station has an available MVR revision.
7. Pressing `Update` sends `MVR_REQUEST` for the latest known file UUID.
8. The native client receives the binary MVR package on a background worker, writes it to a `.part` file, validates that the payload is non-empty and ZIP-like, and renames it to the final `.mvr` path only after success.
9. `scripts/load_scene.gd` receives the completed path and calls the existing MVR loading path without adding protocol logic to scene loading code.

Peraviz follows the MVR-xchange TCP package structure with the `778682` package header, package version `1`, JSON package type `0`, MVR binary package type `1`, and big-endian multi-byte fields. Peraviz stores received files in a user-writable MVR-xchange cache directory. Previously completed files are not deleted by the transfer path, so a loaded scene is not invalidated while it may still be in use.

## Project roles and scope

Perastage remains the technical data authority. Peraviz remains the MVR-xchange client/viewer and loads received MVR files exactly as it loads a local `.mvr` file.

This implementation does not introduce a proprietary Perastage-to-Peraviz bridge. It also does not implement incremental object synchronization, editing features, or non-standard MVR mutations.

## Auto-update

Auto-update remains off by default through the `mvr_xchange_auto_update` preference. Manual `Update` is the supported workflow for this phase. If automatic requesting is expanded later, it must remain opt-in and must not start while a transfer is already running.

## Build behavior

Native MVR-xchange support is controlled by `PERAVIZ_ENABLE_MVR_XCHANGE`, which defaults to `ON`. Builds with the option disabled still run the Godot project; the UI reports that native MVR-xchange support is unavailable and fails gracefully.
