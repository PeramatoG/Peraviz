#!/usr/bin/env python3
"""Run every GDScript regression headlessly and emit logs plus JUnit XML."""

import argparse
import subprocess
import time
import xml.etree.ElementTree as ET
from pathlib import Path


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
        try:
            result = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=args.timeout, check=False)
            output, returncode = result.stdout, result.returncode
        except subprocess.TimeoutExpired as error:
            captured = error.stdout or ""
            output = captured.decode(errors="replace") if isinstance(captured, bytes) else captured
            output += f"\nTimed out after {args.timeout} seconds.\n"
            returncode = 124
        if "SCRIPT ERROR:" in output or "ERROR:" in output:
            returncode = returncode or 1
        elapsed = time.monotonic() - started
        (args.output / f"{script.stem}.log").write_text(output, encoding="utf-8")
        case = ET.SubElement(suite, "testcase", classname="gdscript", name=script.stem, time=f"{elapsed:.3f}")
        ET.SubElement(case, "system-out").text = output
        if returncode:
            failures += 1
            ET.SubElement(case, "failure", message=f"Godot exited with status {returncode}").text = output
        print(f"{'PASS' if returncode == 0 else 'FAIL'} {script.name} ({elapsed:.2f}s)")
    suite.set("failures", str(failures))
    suite.set("skipped", "0")
    ET.ElementTree(suite).write(args.output / "gdscript.junit.xml", encoding="utf-8", xml_declaration=True)
    print(f"GDScript total={len(scripts)} passed={len(scripts) - failures} failed={failures} skipped=0")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
