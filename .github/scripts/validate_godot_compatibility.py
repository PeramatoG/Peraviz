#!/usr/bin/env python3
"""Validate every repository surface against the Godot compatibility contract."""

from pathlib import Path
import re
import sys


ROOT = Path(__file__).resolve().parents[2]
CONTRACT = ROOT / "native/cmake/GodotCompatibility.cmake"


def read_contract() -> dict[str, str]:
    """Read the focused CMake contract without evaluating arbitrary CMake code."""
    values = dict(re.findall(r'^set\((PERAVIZ_[A-Z_]+) "([^"]+)"\)$', CONTRACT.read_text(), re.MULTILINE))
    required = {
        "PERAVIZ_GODOT_RUNTIME_VERSION",
        "PERAVIZ_GODOT_API_VERSION",
        "PERAVIZ_GODOT_CPP_REVISION",
        "PERAVIZ_GDEXTENSION_COMPATIBILITY_MINIMUM",
    }
    if values.keys() != required:
        raise ValueError(f"Unexpected compatibility keys: {sorted(values)}")
    return values


def require(pattern: str, path: str, description: str) -> None:
    """Require one contract-derived pattern in a repository file."""
    if not re.search(pattern, (ROOT / path).read_text(), re.MULTILINE):
        raise ValueError(f"{path} does not declare {description}")


def main() -> int:
    """Check project, CI, extension, build, and documentation version declarations."""
    try:
        contract = read_contract()
        runtime = re.escape(contract["PERAVIZ_GODOT_RUNTIME_VERSION"])
        api = re.escape(contract["PERAVIZ_GODOT_API_VERSION"])
        revision = contract["PERAVIZ_GODOT_CPP_REVISION"]
        minimum = re.escape(contract["PERAVIZ_GDEXTENSION_COMPATIBILITY_MINIMUM"])
        if not re.fullmatch(r"[0-9a-f]{40}", revision):
            raise ValueError("godot-cpp revision must be an immutable 40-character commit SHA")
        require(rf'^config/features=.*"{api}"', "project.godot", f"Godot feature version {api}")
        require(rf'^\s+GODOT_VERSION: {runtime}$', ".github/workflows/ci-tests.yml", f"Godot runtime {runtime}")
        require(rf'^compatibility_minimum = "{minimum}"$', "peraviz.gdextension", f"minimum Godot {minimum}")
        require(rf'Godot runtime/editor:\*\* {runtime} stable', "README.md", f"runtime {runtime}")
        require(rf'GDExtension API:\*\* Godot {api}', "README.md", f"API {api}")
        require(r'GODOTCPP_API_VERSION.*PERAVIZ_GODOT_API_VERSION', "native/CMakeLists.txt", "explicit godot-cpp API selection")
        require(r'GIT_TAG \$\{PERAVIZ_GODOT_CPP_REVISION\}', "native/CMakeLists.txt", "pinned godot-cpp revision")
    except (OSError, ValueError) as error:
        print(f"[godot-compatibility] {error}", file=sys.stderr)
        return 1
    print(
        "[godot-compatibility] "
        f"runtime={contract['PERAVIZ_GODOT_RUNTIME_VERSION']} "
        f"api={contract['PERAVIZ_GODOT_API_VERSION']} "
        f"godot-cpp={contract['PERAVIZ_GODOT_CPP_REVISION']} "
        f"minimum={contract['PERAVIZ_GDEXTENSION_COMPATIBILITY_MINIMUM']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
