# Peraviz native/runtime modules and external libraries

## Local transform implementation

Peraviz now contains its own local matrix/transform utilities under `native/src/`.
These utilities were duplicated and adapted to keep Peraviz fully standalone.

- `native/src/types.h`
- `native/src/matrixutils.h`

Peraviz does not require the Perastage repository at build time.

## MVR/GDTF compatibility approach

Peraviz follows the same MVR/GDTF concepts used in lighting workflows, but owns its
local implementation for parsing, transform composition, and runtime behavior.

## External libraries

- `godot-cpp`
- `tinyxml2`
- `wxWidgets` (core/base)
