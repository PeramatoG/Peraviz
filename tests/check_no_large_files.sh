#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

soft_limit=1200
hard_limit=3000
status=0

while IFS= read -r -d '' file; do
  case "$file" in
    *.cpp|*.cc|*.cxx|*.h|*.hpp|*.hh|*.gd|*.shader) ;;
    *) continue ;;
  esac
  lines=$(wc -l < "$file" | tr -d ' ')
  if (( lines >= hard_limit )); then
    echo "ERROR: $file has $lines LOC, which exceeds the hard limit. Split this file before adding major behavior." >&2
    status=1
  elif (( lines >= soft_limit )); then
    echo "WARNING: $file has $lines LOC. Prefer extraction before adding new responsibilities." >&2
  fi
done < <(git ls-files -z)

exit "$status"
