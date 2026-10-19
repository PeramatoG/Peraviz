#!/usr/bin/env python3
"""Validate fresh Godot import, normal startup and the real MVR lighting graph."""
from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

from run_gdscript_tests import classify_result


def run_stage(command: list[str], log: Path, timeout: int, environment: dict[str, str]) -> str:
    """Reject engine/script diagnostics even if Godot reports a zero exit status."""
    try:
        result = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                env=environment, timeout=timeout, check=False)
        output, status, timed_out = result.stdout, result.returncode, False
    except subprocess.TimeoutExpired as error:
        captured = error.stdout or b''
        output = captured.decode(errors='replace') if isinstance(captured, bytes) else captured
        status, timed_out = 124, True
    log.write_text(output, encoding='utf-8')
    outcome = classify_result(status, output, timed_out, timeout)
    if outcome.failed:
        raise RuntimeError(f'{log.name}: {outcome.message}; see {log}')
    print(f'PASS {log.stem}', flush=True)
    return output


def check_failure_contract(base: list[str], output: Path, environment: dict[str, str]) -> None:
    """Require one explicit error per deliberate failure, never a silent fallback/retry loop."""
    for flag, expected in [('--installation', 'Dense presentation installation failed'),
                           ('--initialization', 'Dense presentation beam initialization failed')]:
        result = subprocess.run(base + ['--script','res://tests/integration/test_dense_failure_contract.gd','--',flag],
                                text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                env=environment, timeout=60, check=False)
        log = output / f'expected{flag}.log'
        log.write_text(result.stdout, encoding='utf-8')
        errors = [line for line in result.stdout.splitlines() if line.startswith('ERROR:') or 'SCRIPT ERROR' in line]
        remaining = '\n'.join(line for line in result.stdout.splitlines() if not (line.startswith('ERROR:') and expected in line))
        unexpected = classify_result(0, remaining).failed
        if result.returncode or unexpected or len(errors) != 1 or expected not in errors[0] or 'EXPECTED_FAILURE_CONTRACT_PASSED' not in result.stdout:
            raise RuntimeError(f'Negative contract failed; see {log}')
        print(f'PASS {flag} (one deliberate diagnostic, fallback/retry rejected)', flush=True)


def main() -> int:
    """Remove only project-generated cache, then exercise the normal dependency graph."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', required=True)
    parser.add_argument('--project', type=Path, default=Path.cwd())
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    project, output = args.project.resolve(), args.output.resolve()
    if not (project / 'project.godot').is_file():
        parser.error('--project must contain project.godot')
    if output == project / '.godot' or project / '.godot' in output.parents:
        parser.error('--output must be outside the generated .godot directory')
    output.mkdir(parents=True, exist_ok=True)
    environment = os.environ.copy()
    # Keep user preferences (auto-load/DMX) separate from the user's installation.
    for key, folder in [('XDG_DATA_HOME','data'), ('XDG_CONFIG_HOME','config'), ('XDG_CACHE_HOME','cache')]:
        environment[key] = str(output / 'user' / folder)
    version = run_stage([args.godot, '--version'], output / 'version.log', 15, environment).strip()
    if not version.startswith('4.7.1.stable.'):
        raise RuntimeError(f'Requires pinned Godot 4.7.1 stable, got {version}')
    cache = project / '.godot'
    if cache.is_symlink():
        raise RuntimeError('Refusing to remove a symlinked .godot cache')
    if cache.exists():
        shutil.rmtree(cache)
    print('Cold cache: .godot absent before import', flush=True)
    base = [args.godot, '--headless', '--audio-driver', 'Dummy', '--rendering-method', 'gl_compatibility', '--path', str(project)]
    run_stage(base + ['--editor','--quit'], output / 'import.log', 120, environment)
    # Reproduce a normal checkout update without editor registration of the new
    # internal helper. This additional stage fails on 832882d after a clean import
    # succeeds, so import-only testing cannot hide the global-class dependency.
    class_cache = cache / 'global_script_class_cache.cfg'
    if not class_cache.is_file():
        raise RuntimeError('Fresh import did not generate the script class registry')
    registry = class_cache.read_text(encoding='utf-8')
    registry = re.sub(r'\{[^{}]*"class": &"BoundBeamState"[^{}]*\},?\s*', '', registry)
    registry = re.sub(r',\s*\]', '\n]', registry)
    class_cache.write_text(registry, encoding='utf-8')
    run_stage(base + ['--quit-after','5','--peraviz-perf-trace'], output / 'normal-startup.log', 60, environment)
    fixture = output / 'lifecycle.mvr'
    run_stage([sys.executable, str(project / 'tests/integration/generate_presentation_lifecycle_fixture.py'), str(fixture)], output / 'fixture.log', 15, environment)
    lifecycle = run_stage(base + ['--script','res://tests/integration/test_application_presentation_lifecycle.gd',
                                  '--peraviz-perf-trace','--','--mvr',str(fixture)], output / 'application-lifecycle.log', 60, environment)
    if not re.search(r'"dense_presentation_active": true', lifecycle) or '"dense_presentation":' not in lifecycle:
        raise RuntimeError('Application lifecycle did not confirm active dense presentation in stability telemetry')
    if 'Application presentation lifecycle passed' not in lifecycle:
        raise RuntimeError('Application lifecycle completion marker missing')
    run_stage(base + ['--script','res://tests/integration/test_application_presentation_lifecycle.gd',
                      '--peraviz-perf-trace','--','--mvr',str(fixture),'--legacy'], output / 'application-lifecycle-legacy.log', 60, environment)
    check_failure_contract(base, output, environment)
    print('Clean-cache application startup and presentation lifecycle passed.', flush=True)
    return 0


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except RuntimeError as error:
        print(f'FAIL {error}', file=sys.stderr)
        raise SystemExit(1)
