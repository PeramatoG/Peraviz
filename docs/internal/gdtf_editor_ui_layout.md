# GDTF Editor UI Layout

Checkpoint 08E3 reserves the lower inspector area for three read-only regions: exact DMX value controls, active mapping details, and resource preview or WheelSlot gallery. Only normalized layout ratios may be persisted through layout preferences. Slider values and inspection selections are transient UI state and are not project data.

Resource thumbnails are GUI-owned and cached by source, archive entry, and target size. The cache clears on source changes and contains no XML parsing, session mutation, or project logic.
