#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

required_files=(
  "AGENTS.md"
  "peraviz_tree.md"
  "docs/architecture.md"
  "docs/godot_performance_guidelines.md"
)

missing=0
for path in "${required_files[@]}"; do
  if [[ ! -f "$path" ]]; then
    echo "Missing required architecture file: $path" >&2
    missing=1
  fi
done

if [[ "$missing" -ne 0 ]]; then
  exit 1
fi

# These terms define the intended high-level boundary and should remain documented.
for term in "native" "Godot" "C++" "frame snapshot" "MultiMesh" "RenderingServer"; do
  if ! grep -Riq "$term" AGENTS.md peraviz_tree.md docs/architecture.md docs/godot_performance_guidelines.md; then
    echo "Architecture documentation does not mention required concept: $term" >&2
    exit 1
  fi
done

echo "Peraviz architecture documentation files are present and mention the required boundary concepts."
