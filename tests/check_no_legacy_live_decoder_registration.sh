#!/usr/bin/env bash
set -euo pipefail

if rg -n "ClassDB::register_class<PeravizDmxUniverseDecoder|PeravizDmxUniverseDecoder" native/src/register_types.cpp native/src/runtime scripts; then
  echo "Legacy live decoder fallback is registered or referenced in the Godot live path." >&2
  exit 1
fi

echo "Legacy live decoder registration guardrail passed."
