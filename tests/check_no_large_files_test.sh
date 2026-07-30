#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$TMP_DIR/tests"
cp "$ROOT/tests/check_no_large_files.sh" "$TMP_DIR/tests/check_no_large_files.sh"
git -C "$TMP_DIR" init -q
git -C "$TMP_DIR" config user.email "ci-policy-test@example.invalid"
git -C "$TMP_DIR" config user.name "CI Policy Test"

mkdir -p "$TMP_DIR/src" "$TMP_DIR/out/generated" "$TMP_DIR/.tools/dependency"
awk 'BEGIN { for (i = 0; i < 3001; ++i) print "// tracked" }' > "$TMP_DIR/src/tracked oversized.cpp"
awk 'BEGIN { for (i = 0; i < 3001; ++i) print "// generated" }' > "$TMP_DIR/out/generated/untracked.cpp"
awk 'BEGIN { for (i = 0; i < 3001; ++i) print "// dependency" }' > "$TMP_DIR/.tools/dependency/untracked.hpp"
git -C "$TMP_DIR" add "src/tracked oversized.cpp"

set +e
output="$(cd "$TMP_DIR" && tests/check_no_large_files.sh 2>&1)"
status=$?
set -e

if [[ "$status" -eq 0 ]]; then
  echo "Expected the tracked oversized source fixture to fail the policy." >&2
  exit 1
fi
if [[ "$output" != *"src/tracked oversized.cpp"* ]]; then
  echo "Tracked oversized source fixture was not reported." >&2
  exit 1
fi
if [[ "$output" == *"out/generated/untracked.cpp"* || "$output" == *".tools/dependency/untracked.hpp"* ]]; then
  echo "Untracked generated or dependency files were inspected." >&2
  exit 1
fi

echo "Tracked-file scope regression passed."
