#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

soft_limit=1200
hard_limit=1500
status=0

mapfile -t files < <(
  find . \
    -path './.git' -prune -o \
    -path './build' -prune -o \
    -path './cmake-build-*' -prune -o \
    -path './.godot' -prune -o \
    -type f \( \
      -name '*.cpp' -o -name '*.cc' -o -name '*.cxx' -o \
      -name '*.h' -o -name '*.hpp' -o -name '*.hh' -o \
      -name '*.gd' -o -name '*.shader' \
    \) -print
)

for file in "${files[@]}"; do
  lines=$(wc -l < "$file" | tr -d ' ')
  if (( lines >= hard_limit )); then
    echo "ERROR: $file has $lines LOC. Split this file before adding major behavior." >&2
    status=1
  elif (( lines >= soft_limit )); then
    echo "WARNING: $file has $lines LOC. Prefer extraction before adding new responsibilities." >&2
  fi
done

exit "$status"
