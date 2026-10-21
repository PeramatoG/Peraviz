#!/usr/bin/env python3
"""Bounded generic setup scalability comparison; proprietary inputs are never required."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile

from generate_render_group_fixture import generate


def main() -> None:
    """Generate valid distinct patches/transforms and retain phase/resource observations."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--instances', type=int, nargs='+', default=[1, 20, 100, 250])
    parser.add_argument('--reference', action='store_true', help='Disable template reuse and native/Godot setup indexes; can be substantially slower.')
    parser.add_argument('--rendered', action='store_true', help='Use a real Forward+ window; requires a graphical display and measures post-ready interaction gaps.')
    args = parser.parse_args()
    project = Path(__file__).resolve().parents[2]
    records = []
    environment = os.environ.copy()
    for key in ('PERAVIZ_SETUP_REFERENCE_GEOMETRY', 'PERAVIZ_SETUP_REFERENCE_INDEXES'):
        environment.pop(key, None)
        if args.reference:
            environment[key] = '1'
    with tempfile.TemporaryDirectory(prefix='peraviz-setup-') as directory:
        for count in args.instances:
            source = Path(directory) / 'generated.mvr'
            generate(source, sources=count, emission=False, wheel='basic', selected_mode='BasicControls', transforms=True)
            graphics = ['--windowed', '--resolution', '640x360', '--rendering-method', 'forward_plus'] if args.rendered else ['--headless', '--rendering-method', 'gl_compatibility']
            command = [args.godot, *graphics, '--audio-driver', 'Dummy',
                       '--path', str(project), '--script', 'res://tests/integration/scene_setup_benchmark.gd', '--', str(source)]
            result = subprocess.run(command, env=environment, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=300 if args.rendered else 120, check=True)
            for line in result.stdout.splitlines():
                if 'SCRIPT ERROR' in line or line.startswith('ERROR:'):
                    raise RuntimeError(line)
                if line.startswith('SETUP_BENCHMARK '):
                    record = json.loads(line.removeprefix('SETUP_BENCHMARK '))
                    record.update(instances=count, reference=args.reference, rendered=args.rendered)
                    records.append(record)
                    print(json.dumps(record), flush=True)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(records, indent=2)+'\n', encoding='utf-8')


if __name__ == '__main__':
    main()
