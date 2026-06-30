#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ ! -d "godot" ]]; then
  echo "No godot/ directory found. Update peraviz_tree.md and this check if the Godot project lives elsewhere."
  exit 0
fi

status=0
patterns=(
  "PacketPeerUDP"
  "UDPServer"
  "ArtNet"
  "Art-Net"
  "sACN"
  "E131"
  "DMX"
  "GDTF"
  "GeneralSceneDescription"
)

for pattern in "${patterns[@]}"; do
  if grep -RIn --include='*.gd' --include='*.cs' --include='*.tscn' "$pattern" godot >/tmp/peraviz_boundary_hits.txt; then
    echo "Potential heavy/protocol logic found in Godot for pattern '$pattern':" >&2
    cat /tmp/peraviz_boundary_hits.txt >&2
    echo "Move live protocol/fixture-resolution logic to native C++ or document why this occurrence is UI/import-only." >&2
    status=1
  fi
done

rm -f /tmp/peraviz_boundary_hits.txt
exit "$status"
