#!/usr/bin/env bash
set -euo pipefail

required_files=(
  "native/src/dmx/gdtf_wheel_catalog.h"
  "native/src/dmx/gdtf_wheel_catalog.cpp"
  "native/src/dmx/gdtf_color_cie.h"
  "native/src/dmx/gdtf_archive_resource_reader.h"
  "native/src/dmx/gdtf_dmx_inspector.h"
  "native/src/gui/gdtf/gdtf_resource_bitmap_cache.h"
  "native/tests/gdtf_wheel_attribute_inspector_test.cpp"
)
for file in "${required_files[@]}"; do
  test -f "$file" || { echo "Missing Checkpoint 08E3 file: $file" >&2; exit 1; }
done

rg -q "WheelSlotIndex|wheel_slot_index" native/src/dmx/gdtf_dmx_inspector.* native/tests/gdtf_wheel_attribute_inspector_test.cpp
rg -q "GraphicWheel|graphic_wheel|is_graphic_wheel" native/src/dmx/gdtf_wheel_catalog.* native/tests/gdtf_wheel_attribute_inspector_test.cpp
rg -q "read_gdtf_wheel_resource|unsafe_path|oversized_resource|ambiguous_resource" native/src/dmx/gdtf_archive_resource_reader.*
rg -q "xyY|convert_cie_xyy_to_srgb_preview|srgb_clipped" native/src/dmx/gdtf_color_cie.*
rg -q "normalized_value|bytes|percentage|is_virtual" native/src/dmx/gdtf_dmx_inspector.*
rg -q "get_or_store_placeholder|clear_for_source" native/src/gui/gdtf/gdtf_resource_bitmap_cache.*

if rg -q "wxBitmap|tinyxml2|XMLDocument|GdtfEditSession|Apply|live DMX|XmlWriter|write_xml" native/src/gui/gdtf/gdtf_resource_bitmap_cache.*; then
  echo "GUI bitmap cache must not parse XML, mutate sessions, write XML, or send live DMX" >&2
  exit 1
fi

if rg -q "extract_file\(" native/src/dmx/gdtf_archive_resource_reader.*; then
  echo "08E3 resource reader must not extract full archives or files" >&2
  exit 1
fi

tests/check_runtime_architecture.sh

echo "Checkpoint 08E3 Wheel and Attribute Inspector guard passed."
