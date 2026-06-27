# MVR-xchange support

Peraviz includes modular MVR-xchange support so it can act as a viewer/runtime client for an upstream technical data source such as Perastage. The implementation follows the official MVR-xchange TCP-mode package framing and keeps protocol, networking, and binary transfer logic in native C++.

## Supported official client behavior

Peraviz supports the manual viewer/client workflow:

1. Discover stations advertised as `_mvrxchange._tcp.local.`.
2. Filter service instances by MVR-xchange group, defaulting to `Default`.
3. Optionally bind discovery and the local TCP station to a selected interface IP when configured.
4. Register a local TCP-mode station with `StationName` and `StationUUID` TXT records.
5. Send official `MVR_JOIN` messages to selected stations.
6. Handle official `MVR_JOIN_RET` and `MVR_COMMIT` information when received.
7. Track available commit/revision metadata and canonicalize valid `FileUUID` values.
8. Send official `MVR_REQUEST` messages for a selected revision.
9. Receive the binary MVR payload using official MVR-xchange TCP package framing.
10. Load the completed MVR through the existing Peraviz MVR import path.

The TCP package header uses the official `778682` package header, package version `1`, JSON package type `0`, MVR binary package type `1`, and network byte order for multi-byte fields. Unknown, malformed, or unsupported data is handled conservatively and surfaced through native state/events instead of being treated as proprietary behavior.

## State and errors

The native client exposes discovery, station, commit, request, transfer, completion, failure, last error, file UUID, received path, and received byte-count information through the existing polling/event architecture. The Godot UI keeps the panel compact and reports the current state using concise labels such as discovering, joining, revision available, requesting, receiving, loaded, and failed.

## Received-file storage and safety

GDScript provides native code with a globalized `user://mvrxchange` cache path. Native transfer code writes received payloads to a temporary `.part` file, validates that the payload is non-empty, ZIP-like, and references `GeneralSceneDescription.xml`, then renames it to the final `.mvr` path only after successful completion.

A failed transfer does not create or replace a final `.mvr` file, and temporary `.part` files are removed where practical. Previously completed received files are intentionally not deleted by the transfer path, so a currently loaded scene is not invalidated while Godot may still be using it.

## Testing with Perastage

1. Build Peraviz with `PERAVIZ_ENABLE_MVR_XCHANGE=ON`.
2. Start Perastage with MVR-xchange enabled on the same local network.
3. Use the Peraviz MVR-xchange panel and keep the group as `Default`, unless Perastage is using a custom group.
4. Start discovery and select the Perastage station when it appears.
5. Wait until Peraviz reports that a revision is available.
6. Press `Update` to request the MVR.
7. Confirm that the status progresses through requesting/receiving/loading and that the scene loads through the normal importer.

No real network is required for the native unit tests; they cover service-name parsing, message/package handling, UUID canonicalization, commit tracking helpers, and safe received-file finalization.

## Not implemented in this phase

Peraviz remains a viewer/runtime client. This MVR-xchange layer does not add:

- Perastage automatic `Connect to Peraviz` workflows.
- Aggressive auto-accept or always-on auto-load behavior.
- Peraviz Live Link.
- Incremental table/object synchronization.
- Private MVR-xchange messages.
- Peraviz-side editing, rewriting, or mutation of MVR source data.
- Automatic Perastage launching.

If a protocol detail is ambiguous in the public specification, Peraviz keeps the behavior conservative and interoperable rather than inventing application-specific extensions.
