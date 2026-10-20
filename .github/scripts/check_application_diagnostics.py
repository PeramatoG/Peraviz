#!/usr/bin/env python3
"""Exercise Peraviz user arguments and renderer policy in real Godot processes."""
from __future__ import annotations

import re
from pathlib import Path
from typing import Callable


def check_modes(base: list[str], fixture: Path, output: Path, environment: dict[str, str], run_stage: Callable) -> None:
    """Require controller configuration, resource policy, truthful telemetry and leak-free exit."""
    script = ['--verbose','--script','res://tests/integration/test_application_diagnostics.gd']
    cases = [
        ('transform-normal', [], ['--peraviz-perf-trace','--peraviz-transform-diagnostic=normal'], 'full', True, True),
        ('transform-mechanical-only', [], ['--peraviz-perf-trace','--peraviz-transform-diagnostic=mechanical-only','--reload'], 'full', True, True),
        ('transform-active-only', [], ['--peraviz-transform-diagnostic=active-only'], 'full', False, True),
        ('transform-before-separator', ['--peraviz-transform-diagnostic=mechanical-only'], [], 'full', False, False),
        ('default', [], [], 'full', False, False),
        ('full-off', [], ['--peraviz-render-diagnostic=full'], 'full', False, True),
        ('full-trace-reload', [], ['--peraviz-perf-trace','--peraviz-render-diagnostic=full','--reload'], 'full', True, True),
        ('no-beams', [], ['--peraviz-perf-trace','--peraviz-render-diagnostic=no-beams'], 'no-beams', True, True),
        ('transforms-only', [], ['--peraviz-perf-trace','--peraviz-render-diagnostic=transforms-only'], 'transforms-only', True, True),
        ('trace-only', [], ['--peraviz-perf-trace'], 'full', True, True),
        ('user-precedence', ['--peraviz-render-diagnostic=no-beams'], ['--peraviz-render-diagnostic=full'], 'full', False, True),
        ('legacy-rejected', ['--peraviz-render-diagnostic=no-beams'], [], 'full', False, False),
        ('duplicate-last-wins', [], ['--peraviz-render-diagnostic=full','--peraviz-render-diagnostic=no-beams'], 'no-beams', False, True),
    ]
    for name, engine, application, mode, trace, diagnostic in cases:
        transform = next((arg.split('=', 1)[1] for arg in reversed(application) if arg.startswith('--peraviz-transform-diagnostic=')), 'active-only')
        command = base + engine + script + ['--'] + application + [f'--expect-mode={mode}',f'--expect-trace={str(trace).lower()}',f'--expect-transform-mode={transform}',f'--fixture={fixture}']
        log = output / f'command-line-{name}.log'
        text = run_stage(command, log, 60, environment)
        lines = re.findall(r'^\[peraviz-diagnostic\].*$',text,re.M)
        expected = f'[peraviz-diagnostic] perf_trace={str(trace).lower()} render_mode={mode} transform_mode={transform}'
        if lines != ([expected] if diagnostic else []):
            raise RuntimeError(f'Incorrect/duplicate startup diagnostic in {log}: {lines}')
        if 'APPLICATION_DIAGNOSTICS_PASSED' not in text:
            raise RuntimeError(f'Missing successful resource/lifecycle checks in {log}')
        if trace:
            expected_visibility = 2 if mode == 'full' else 0
            if not re.search(rf'\[peraviz-perf\].*mode={mode} .*visible_beams={expected_visibility} visible_lights={expected_visibility}',text):
                raise RuntimeError(f'Production controller reported stale resource visibility in {log}')
        if engine and 'options before -- are ignored' not in text:
            raise RuntimeError(f'Legacy placement was not explicitly rejected in {log}')
