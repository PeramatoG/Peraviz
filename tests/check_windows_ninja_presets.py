#!/usr/bin/env python3
"""Validate the portable policy contract for Windows Ninja CMake presets."""

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PRESETS_PATH = ROOT / "native" / "CMakePresets.json"
EXPECTED = {
    "win-x64-debug-ninja": "Debug",
    "win-x64-release-ninja": "Release",
}
RUNTIME = "MultiThreaded$<$<CONFIG:Debug>:Debug>DLL"


def require(condition: bool, message: str) -> None:
    """Fail validation with a focused policy error when a condition is false."""
    if not condition:
        raise ValueError(message)


def indexed(items: list[dict]) -> dict[str, dict]:
    """Index preset records by their unique names."""
    return {item["name"]: item for item in items}


def main() -> None:
    """Assert the shared static-link policy and each Ninja workflow mapping."""
    document = json.loads(PRESETS_PATH.read_text(encoding="utf-8"))
    configure = indexed(document["configurePresets"])
    builds = indexed(document["buildPresets"])
    tests = indexed(document["testPresets"])

    base = configure["windows-static-base"]
    require(base["hidden"] is True, "windows-static-base must remain hidden")
    shared = base["cacheVariables"]
    require(shared["VCPKG_TARGET_TRIPLET"] == "x64-windows-static-md", "static-md triplet is required")
    require(shared["BUILD_SHARED_LIBS"] == "OFF", "shared dependency builds must remain disabled")
    require(shared["CMAKE_MSVC_RUNTIME_LIBRARY"] == RUNTIME, "dynamic MSVC runtime policy is required")

    for name, build_type in EXPECTED.items():
        preset = configure[name]
        require(preset["inherits"] == "windows-static-base", f"{name} must inherit shared policy")
        require(preset["generator"] == "Ninja", f"{name} must use Ninja")
        require(
            preset["architecture"] == {"value": "x64", "strategy": "external"},
            f"{name} must use external x64 architecture selection",
        )
        require(preset["cacheVariables"]["CMAKE_BUILD_TYPE"] == build_type, f"{name} has the wrong build type")
        require(preset["cacheVariables"]["CMAKE_EXPORT_COMPILE_COMMANDS"] == "ON", f"{name} must export compile commands")
        require(builds[name]["configurePreset"] == name, f"{name} build preset is mismatched")
        require("configuration" not in builds[name], f"{name} build preset must remain single-config")
        require(tests[name]["configurePreset"] == name, f"{name} test preset is mismatched")
        require("configuration" not in tests[name], f"{name} test preset must remain single-config")

    print("Windows Ninja preset policy passed.")


if __name__ == "__main__":
    main()
