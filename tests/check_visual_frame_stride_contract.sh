#!/usr/bin/env bash
set -euo pipefail

if rg -n "Visual frame stride must remain 25|fixed 25-float contract" tests native/src scripts --glob '!tests/check_visual_frame_stride_contract.sh'; then
  echo "A guardrail still preserves the obsolete fixed 25-float contract." >&2
  exit 1
fi

rg -q "kVisualProtocolVersion" native/src/runtime/visual_frame_schema.h
rg -q "VisualSectionType" native/src/runtime/visual_frame_schema.h
rg -q "validate_sectioned_visual_frame" native/src/runtime/visual_frame_schema.cpp
rg -q "CompiledGdtfFixtureType" native/src/gdtf_runtime/compiled_gdtf_fixture.h

echo "Sectioned visual frame protocol guardrail passed."
