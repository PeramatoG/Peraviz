#!/usr/bin/env python3
"""Run every GDScript regression headlessly and emit logs plus JUnit XML."""

import argparse
import subprocess
import time
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class TestOutcome:
    """Describe the runner classification for one Godot process."""

    failed: bool
    message: str


def first_unexpected_diagnostic(output: str) -> str | None:
    """Return the first engine or script error that makes otherwise-zero output fail."""
    for line in output.splitlines():
        stripped = line.strip()
        if "SCRIPT ERROR:" in stripped or stripped.startswith("ERROR:"):
            return stripped
    return None


def classify_result(returncode: int, output: str, timed_out: bool = False, timeout_seconds: int = 60) -> TestOutcome:
    """Classify process status and strict Godot diagnostics with a causal summary."""
    diagnostic = first_unexpected_diagnostic(output)
    if timed_out:
        cause = diagnostic or "no preceding script or engine error was captured"
        return TestOutcome(True, f"Timed out after {timeout_seconds} seconds; first causal diagnostic: {cause}")
    if returncode:
        suffix = f"; first diagnostic: {diagnostic}" if diagnostic else ""
        return TestOutcome(True, f"Godot exited with status {returncode}{suffix}")
    if diagnostic:
        return TestOutcome(True, f"Godot emitted an unexpected diagnostic: {diagnostic}")
    return TestOutcome(False, "")


def main() -> int:
    """Execute discovered GDScript tests independently with explicit timeouts."""
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", required=True)
    parser.add_argument("--project", type=Path, default=Path.cwd())
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--timeout", type=int, default=60)
    args = parser.parse_args()
    scripts = sorted((args.project / "tests/gdscript").glob("test_*.gd"))
    if not scripts:
        raise SystemExit("No GDScript tests were discovered")
    args.output.mkdir(parents=True, exist_ok=True)
    suite = ET.Element("testsuite", name="Peraviz GDScript", tests=str(len(scripts)))
    failures = 0
    for script in scripts:
        started = time.monotonic()
        command = [args.godot, "--headless", "--audio-driver", "Dummy", "--rendering-method", "gl_compatibility", "--path", str(args.project), "--script", str(script.relative_to(args.project))]
        timed_out = False
        try:
            result = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=args.timeout, check=False)
            output, returncode = result.stdout, result.returncode
        except subprocess.TimeoutExpired as error:
            captured = error.stdout or ""
            output = captured.decode(errors="replace") if isinstance(captured, bytes) else captured
            output += f"\nTimed out after {args.timeout} seconds.\n"
            returncode = 124
            timed_out = True
        outcome = classify_result(returncode, output, timed_out, args.timeout)
        elapsed = time.monotonic() - started
        (args.output / f"{script.stem}.log").write_text(output, encoding="utf-8")
        case = ET.SubElement(suite, "testcase", classname="gdscript", name=script.stem, time=f"{elapsed:.3f}")
        ET.SubElement(case, "system-out").text = output
        if outcome.failed:
            failures += 1
            ET.SubElement(case, "failure", message=outcome.message).text = output
        print(f"{'FAIL' if outcome.failed else 'PASS'} {script.name} ({elapsed:.2f}s)")
    suite.set("failures", str(failures))
    suite.set("skipped", "0")
    ET.ElementTree(suite).write(args.output / "gdscript.junit.xml", encoding="utf-8", xml_declaration=True)
    print(f"GDScript total={len(scripts)} passed={len(scripts) - failures} failed={failures} skipped=0")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
