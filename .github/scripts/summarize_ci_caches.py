#!/usr/bin/env python3
"""Write vcpkg, Godot, and sccache outcomes to the GitHub job summary."""

import argparse
import json
from pathlib import Path


def nested_number(data: dict, *paths: tuple[str, ...]) -> int:
    """Return the first numeric value found at one of the candidate paths."""
    for path in paths:
        value = data
        for key in path:
            if not isinstance(value, dict) or key not in value:
                break
            value = value[key]
        else:
            if isinstance(value, (int, float)):
                return int(value)
    return 0


def language_total(data: dict, field: str) -> int:
    """Sum the per-language counts reported for an sccache statistic."""
    value = data.get("stats", {}).get(field, {})
    counts = value.get("counts", {}) if isinstance(value, dict) else {}
    return sum(item for item in counts.values() if isinstance(item, (int, float)))


def main() -> int:
    """Append stable cache compatibility details and measured compiler statistics."""
    parser = argparse.ArgumentParser()
    parser.add_argument("--summary", type=Path, required=True)
    parser.add_argument("--stats", type=Path, required=True)
    parser.add_argument("--namespace", required=True)
    parser.add_argument("--compiler", required=True)
    parser.add_argument("--downloads-hit", required=True)
    parser.add_argument("--downloads-save", required=True)
    parser.add_argument("--binary-hit", required=True)
    parser.add_argument("--binary-save", required=True)
    parser.add_argument("--godot-hit", required=True)
    parser.add_argument("--godot-save", required=True)
    args = parser.parse_args()

    data = json.loads(args.stats.read_text(encoding="utf-8"))
    requests = nested_number(data, ("stats", "compile_requests"), ("compile_requests",))
    hits = language_total(data, "cache_hits")
    misses = language_total(data, "cache_misses")
    errors = language_total(data, "cache_errors")
    if requests == 0:
        requests = hits + misses
    if requests == 0:
        raise SystemExit("The native build recorded zero sccache compiler requests")
    hit_percentage = 100.0 * hits / (hits + misses) if hits + misses else 0.0

    with args.summary.open("a", encoding="utf-8") as summary:
        summary.write("## CI cache results\n\n")
        summary.write(f"- Compiler identity: `{args.compiler}`\n")
        summary.write(f"- sccache namespace: `{args.namespace}`\n")
        summary.write(f"- sccache requests: {requests}\n")
        summary.write(f"- sccache hits: {hits}\n")
        summary.write(f"- sccache misses: {misses}\n")
        summary.write(f"- sccache hit percentage: {hit_percentage:.2f}%\n")
        summary.write(f"- sccache cache errors: {errors}\n")
        summary.write(f"- vcpkg downloads restore hit: {args.downloads_hit}; save outcome: {args.downloads_save}\n")
        summary.write(f"- vcpkg binary restore hit: {args.binary_hit}; save outcome: {args.binary_save}\n")
        summary.write(f"- Godot restore hit: {args.godot_hit}; save outcome: {args.godot_save}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
