# GDTF Mode and Channel Browser

The Mode and Channel Browser remains a read-only presentation surface for parsed GDTF mode/channel data. Checkpoint 08E3 extends the underlying inspection state with wheel resolution, active ChannelFunction and ChannelSet mapping, ColorCIE previews, Filter swatches, resource status, and graphic-wheel metadata.

The browser must continue to use typed model data rather than formatted UI strings. Active row highlighting is a presentation-only view of the pure DMX inspection result and must not force tree selection changes while the inspection value changes.

Truss workflows keep Modes hidden and do not load wheel resources.
