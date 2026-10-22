#!/usr/bin/env python3
"""Run real mesh/lifetime coverage from equivalent ASCII and Unicode source paths."""
from __future__ import annotations
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", required=True)
    args = parser.parse_args()
    project = Path(__file__).resolve().parents[2]
    with tempfile.TemporaryDirectory(prefix="peraviz-import-") as temporary:
        root = Path(temporary)
        original = root / "ascii" / "scene.mvr"
        subprocess.run([sys.executable, str(Path(__file__).with_name("generate_mvr_gdtf_lifetime_fixture.py")), str(original)], check=True)
        signature = None
        for folder, name in [("ascii", "scene.mvr"), ("ascii", "sceneñ.mvr"), ("répertoire模型", "escenaé灯.mvr")]:
            destination = root / folder
            destination.mkdir(exist_ok=True)
            for source in original.parent.iterdir():
                if source.is_file() and source.parent != destination:
                    shutil.copyfile(source, destination / source.name)
            fixture = destination / name
            if fixture != original:
                shutil.copyfile(original, fixture)
            command = [args.godot, "--headless", "--audio-driver", "Dummy", "--rendering-method", "gl_compatibility", "--path", str(project),
                       "--script", "tests/integration/test_mvr_gdtf_asset_lifetime_smoke.gd", "--", "--mvr", str(fixture)]
            environment = os.environ.copy()
            if folder != "ascii":
                unicode_temp = destination / "temporaryñ灯"
                unicode_temp.mkdir()
                environment.update({key: str(unicode_temp) for key in ("TMPDIR", "TEMP", "TMP")})
            result = subprocess.run(command, capture_output=True, text=True, encoding="utf-8", env=environment, timeout=60)
            print(result.stdout, end="")
            print(result.stderr, end="", file=sys.stderr)
            if result.returncode or any(marker in result.stdout + result.stderr for marker in ["ERROR:", "SCRIPT ERROR", "was leaked", "were leaked"]):
                raise SystemExit(f"Importer smoke failed for {folder}/{name}")
            current = next((line for line in result.stdout.splitlines() if line.startswith("Geometry identity signature=")), None)
            if current is None or (signature is not None and current != signature):
                raise SystemExit("ASCII and Unicode geometry identities differ")
            signature = current
        print("PASS: ASCII, ñ, accented/non-Latin source paths; identical geometry identities")


if __name__ == "__main__":
    main()
