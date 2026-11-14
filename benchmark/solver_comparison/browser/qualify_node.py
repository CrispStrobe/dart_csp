#!/usr/bin/env python3
"""Correctness only: exact built modules in Node, never a browser benchmark."""
from __future__ import annotations

import argparse
import importlib.util
import json
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
from fixtures import corpus, request  # noqa: E402

spec = importlib.util.spec_from_file_location('native_comparison_runner', HERE.parent / 'run.py')
native = importlib.util.module_from_spec(spec)
spec.loader.exec_module(native)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', type=pathlib.Path, required=True)
    parser.add_argument('--node', default='node')
    parser.add_argument('--timeout', type=float, default=30)
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=False)
    jobs, results = [], []
    dart = ['dart_3d_ad', 'dart_2d_ad', 'dart_2d_analytic']
    for target, engines in [('dart2js', dart), ('dart2wasm', dart), ('solvent_wasm', ['solvent_cabi_wasm'])]:
        for engine in engines:
            for mode in ['cold', 'warm']:
                for case in corpus('smoke'):
                    req = request(case, engine, mode, 1, 2)
                    req['run_purpose'] = 'correctness-smoke; no performance claim; build window may contain concurrent work'
                    jobs.append((target, req))
    for index, (target, req) in enumerate(jobs):
        path = args.out / f"{index:03d}_{target}_{req['engine']}_{req['mode']}_{req['fixture']['id']}"
        row = native.run_job([args.node, str(HERE / 'node_host.mjs'), target], req,
                             path, args.timeout, None, index)
        row['purpose'] = 'correctness/portability only; not a benchmark'
        row['summary']['ranking_eligible'] = False
        row['summary']['latency_evidence'] = 'not_measurement_correctness_only'
        native.dump(path / 'job.json', row)
        # The raw solver timestamps are preserved for protocol diagnostics only.
        # This correctness summary deliberately omits latency statistics.
        results.append({
            'target': target, 'engine': req['engine'], 'mode': req['mode'],
            'fixture_id': req['fixture']['id'], 'directory': str(path.resolve()),
            'timed_out': row['timed_out'],
            **{key: row['summary'][key] for key in ['complete', 'accepted_samples',
                                                   'expected_samples', 'completed_samples',
                                                   'acceptance_disagreements', 'known_feasible']},
        })
        print(json.dumps(results[-1]), flush=True)
    passed = all(r['complete'] and r['acceptance_disagreements'] == 0 and
                 r['accepted_samples'] == (r['expected_samples'] if r['known_feasible'] else 0)
                 for r in results)
    summary = {'purpose': 'correctness/portability only', 'runtime': 'Node.js',
               'browser': False, 'passed': passed, 'jobs': results,
               'note': 'Durations emitted by adapters are not benchmark evidence from this run.'}
    (args.out / 'qualification.json').write_text(json.dumps(summary, indent=2) + '\n')
    return 0 if passed else 1


if __name__ == '__main__':
    raise SystemExit(main())
