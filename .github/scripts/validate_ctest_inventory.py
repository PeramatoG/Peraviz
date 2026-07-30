#!/usr/bin/env python3
"""Validate enabled CTests against the maintained required-test manifest."""

import argparse
import json
import xml.etree.ElementTree as ET
from pathlib import Path

MINIMUM_TEST_COUNT = 8
DEFAULT_MANIFEST = Path(__file__).parents[1] / "ctest-required-tests.txt"


def load_required_tests(manifest: Path) -> set[str]:
    """Load the version-controlled list of tests that may not disappear."""
    return {line.strip() for line in manifest.read_text(encoding="utf-8").splitlines() if line.strip() and not line.startswith("#")}


def main() -> int:
    """Reject empty, undersized, missing, disabled, or JUnit-divergent inventories."""
    parser = argparse.ArgumentParser()
    parser.add_argument("inventory", type=Path)
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument("--junit", type=Path)
    args = parser.parse_args()
    required = load_required_tests(args.manifest)
    tests = json.loads(args.inventory.read_text(encoding="utf-8")).get("tests", [])
    names = {test["name"] for test in tests}
    disabled = {
        test["name"]
        for test in tests
        if any(prop.get("name") == "DISABLED" and prop.get("value") for prop in test.get("properties", []))
    }
    missing = required - names
    errors = []
    if not names:
        errors.append("CTest registered zero tests")
    if len(names) < MINIMUM_TEST_COUNT:
        errors.append(f"CTest inventory contains {len(names)} tests; minimum is {MINIMUM_TEST_COUNT}")
    if missing:
        errors.append(f"Missing required tests: {sorted(missing)}")
    if disabled:
        errors.append(f"Disabled tests: {sorted(disabled)}")
    if args.junit:
        root = ET.parse(args.junit).getroot()
        total = int(root.get("tests", len(root.findall(".//testcase"))))
        skipped = int(root.get("skipped", 0))
        if total != len(names):
            errors.append(f"JUnit total {total} differs from validated inventory total {len(names)}")
        if skipped:
            errors.append(f"JUnit reports {skipped} skipped tests")
    if errors:
        print(f"Required tests: {sorted(required)}")
        print(f"Discovered tests: {sorted(names)}")
        for error in errors:
            print(error)
        return 1
    print(f"Validated {len(names)} enabled CTest tests against {len(required)} required tests.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
