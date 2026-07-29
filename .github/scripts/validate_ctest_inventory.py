#!/usr/bin/env python3
"""Validate that the complete, enabled Peraviz CTest inventory is present."""

import argparse
import json
from pathlib import Path


EXPECTED_TESTS = {
    "peraviz_native_runtime_storage_tests",
    "peraviz_native_mvr_xchange_tests",
    "peraviz_native_dmx_tests",
    "peraviz_native_artnet_flow_tests",
    "peraviz_native_dmx_e2e_tests",
    "peraviz_native_visual_runtime_tests",
    "peraviz_native_gdtf_runtime_schema_tests",
    "peraviz_native_runtime_table_tests",
}


def main() -> int:
    """Reject missing, unexpected, or disabled CTest registrations."""
    parser = argparse.ArgumentParser()
    parser.add_argument("inventory", type=Path)
    args = parser.parse_args()
    tests = json.loads(args.inventory.read_text(encoding="utf-8")).get("tests", [])
    names = {test["name"] for test in tests}
    disabled = {
        test["name"]
        for test in tests
        if any(prop.get("name") == "DISABLED" and prop.get("value") for prop in test.get("properties", []))
    }
    if names != EXPECTED_TESTS or disabled:
        print(f"Expected tests: {sorted(EXPECTED_TESTS)}")
        print(f"Discovered tests: {sorted(names)}")
        print(f"Disabled tests: {sorted(disabled)}")
        return 1
    print(f"Validated {len(names)} enabled CTest tests.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
