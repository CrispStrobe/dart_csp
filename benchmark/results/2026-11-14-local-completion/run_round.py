#!/usr/bin/env python3
"""Run one predeclared local measurement block and preserve exact evidence.

Remote publication is a separate, checked step before the next invocation.
The existing harness supplies the 30-second deadline for each solver process.
"""
import argparse
import datetime
import json
from pathlib import Path
import shutil
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('cohort', choices=['cg', 'identity', 'combined', 'aa'])
    parser.add_argument('round', type=int, choices=range(1, 5))
    args = parser.parse_args()
    saved = Path(__file__).resolve().parent
    root = saved.parents[2]
    workspace = root.parent / 'comparisons'
    name = f'{args.cohort}-round{args.round}'
    output = workspace / 'runs' / name
    log = workspace / 'setup-logs' / (name + '.log')
    if output.exists() or (saved / (name + '-evidence.json')).exists():
        raise ValueError('A completed or interrupted block must not be overwritten')
    fixtures = [
        'axis_rectangle', 'ladder_3_components_1',
        'ladder_25_components_1', 'ladder_500_components_1', 'laman_free_100',
    ]
    if args.cohort != 'aa':
        fixtures.append('laman_free_500')
    command = [
        sys.executable, str(root / 'benchmark/solver_comparison/paired_dart_backends.py'),
        'run', '--prepared', str(workspace / ('prepared-' + args.cohort)),
        '--purpose', 'measurement', '--suites', 'smoke,confirm,coupled',
        '--fixtures', ','.join(fixtures),
        '--engines', 'dart_2d_analytic,dart_3d_ad', '--modes', 'cold,warm',
        '--rounds', '1', '--start-round', str(args.round - 1),
        '--warmups', '8', '--samples', '21', '--timeout', '30', '--cpu', '0',
        '--out', str(output),
    ]
    status = {'schema_version': 1, 'cohort': args.cohort, 'round': args.round,
              'command': command, 'source': 'Fresh Linux local cohort',
              'started_utc': datetime.datetime.now(datetime.timezone.utc).isoformat()}
    with log.open('w') as stream:
        process = subprocess.run(command, cwd=root, stdout=stream,
                                 stderr=subprocess.STDOUT)
    status.update(exit_code=process.returncode,
                  completed_utc=datetime.datetime.now(datetime.timezone.utc).isoformat())
    comparison_file = output / 'comparison.json'
    comparison = json.loads(comparison_file.read_text()) if comparison_file.exists() else None
    passed = (process.returncode == 0 and comparison is not None and
              comparison['protocol_ok'] and comparison['qualification_passed'])
    status['passed'] = passed
    if comparison is not None:
        shutil.copyfile(comparison_file, saved / (name + '-summary.json'))
        status['groups'] = len(comparison['groups'])
        status['measured_operations'] = sum(
            group[side]['main']['completed']
            for group in comparison['groups'] for side in ['before', 'after'])
    shutil.copyfile(log, saved / (name + '.log'))
    (saved / (name + '-status.json')).write_text(json.dumps(status, indent=2) + '\n')
    if output.exists():
        subprocess.run([
            sys.executable,
            str(root / 'benchmark/results/2026-11-14-performance-followup/pack_checkpoint.py'),
            str(output), str(saved), name,
        ], cwd=root, check=True)
    print(json.dumps(status), flush=True)
    if not passed:
        raise RuntimeError('Collection failed; preserve this checkpoint before investigating')


if __name__ == '__main__':
    main()
