# Perastage-compatible runtime tables in Peraviz

Perastage remains the technical data authority and editor. Peraviz remains a read-only visualizer/runtime client. To prepare for future Perastage to Peraviz live synchronization, Peraviz now keeps GUI-independent runtime tables beside the existing render nodes, fixture patch metadata, DMX bindings, and MVR-xchange workflow.

This does not implement Live Link networking, proprietary cell-update transport, MVR editing UI, or non-standard MVR file mutation.

## Table identifiers

- `fixtures`
- `trusses`
- `scene_objects`

Rows are keyed by the MVR object UUID. Listed row order is deterministic by UUID and is not intended to mirror Perastage's visual sorting.

## Fixture columns

| Index | Name |
| ---: | --- |
| 0 | FixtureId |
| 1 | Name |
| 2 | Type |
| 3 | Layer |
| 4 | HangPosition |
| 5 | Universe |
| 6 | Channel |
| 7 | Mode |
| 8 | ChannelCount |
| 9 | ModelFile |
| 10 | PositionX |
| 11 | PositionY |
| 12 | PositionZ |
| 13 | Roll |
| 14 | Pitch |
| 15 | Yaw |
| 16 | Power |
| 17 | Weight |
| 18 | Category |
| 19 | VisualColor |
| 20 | MvrColor |

## Truss columns

| Index | Name |
| ---: | --- |
| 0 | Name |
| 1 | Layer |
| 2 | ModelFile |
| 3 | HangPosition |
| 4 | PositionX |
| 5 | PositionY |
| 6 | PositionZ |
| 7 | Roll |
| 8 | Pitch |
| 9 | Yaw |
| 10 | Manufacturer |
| 11 | Model |
| 12 | Length |
| 13 | Width |
| 14 | Height |
| 15 | Weight |
| 16 | Load |

## Scene object columns

| Index | Name |
| ---: | --- |
| 0 | Name |
| 1 | Layer |
| 2 | ModelFile |
| 3 | PositionX |
| 4 | PositionY |
| 5 | PositionZ |
| 6 | Roll |
| 7 | Pitch |
| 8 | Yaw |

## Value format policy

Runtime table values use stable model values, not localized or renderer-specific UI labels. Positions are numeric MVR base coordinates, rotations are numeric degrees without degree symbols, patch values are integers when available, and colors are stable strings when present in source metadata.

TODO: Future Perastage exporter or Live Link work should normalize any remaining display-value mismatches caused by UI units, degree symbols, color renderers, wxWidgets variants, or missing shared schema export.

## Future cell-update shape

A future protocol can target cells with:

- `table_id`
- `row_uuid`
- `column_index`
- `new_value`
- `base_change_uuid`
- `new_change_uuid`

This document only describes the table model used to receive such updates later.

## Soft sync and hard sync policy

- Updating a cell in an existing row is soft sync.
- Adding a row is hard sync.
- Deleting a row is hard sync.
- Loading or replacing an MVR file is hard sync.
- Table schema mismatch is hard sync.

Hard sync will later mean a full MVR refresh through the official MVR-xchange path.

## Perastage review notes

Perastage fixture columns are defined separately in `FixtureTableColumns`, while truss and scene object columns use `TableColumnIndices`. A future shared schema export would reduce drift risk. Perastage table display values may differ from Peraviz stable runtime values because editor UI code can apply units, degree symbols, color renderers, or wxWidgets-specific variants.
