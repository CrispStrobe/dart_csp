#!/usr/bin/env python3
"""Run common fixtures in an actual Chromium page, preserving every record.

This is a browser qualification lane. It does not substitute Node for a browser,
does not include rendering, and does not mix module load with interaction time.
"""
from __future__ import annotations

import argparse
import asyncio
import datetime
import functools
import hashlib
import http.server
import importlib.metadata
import importlib.util
import json
import math
import os
import pathlib
import platform
import random
import sys
import threading

HERE = pathlib.Path(__file__).resolve().parent
PARENT = HERE.parent
sys.path.insert(0, str(PARENT))
from fixtures import canonical, ladder, request  # noqa: E402
from oracle import check  # noqa: E402

native_spec = importlib.util.spec_from_file_location('native_comparison_runner', PARENT / 'run.py')
native = importlib.util.module_from_spec(native_spec)
native_spec.loader.exec_module(native)

DART_ENGINES = ['dart_3d_ad', 'dart_2d_ad', 'dart_2d_analytic']
ARTIFACTS = {
    'dart2js': ['dart_adapter.js'],
    'dart2wasm': ['dart_adapter.wasm', 'dart_adapter.mjs'],
    'solvent_wasm': ['solvent.wasm'],
}


def dump(path: pathlib.Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, allow_nan=False) + '\n')


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def cases(suite: str) -> list[dict]:
    if suite == 'smoke':
        return canonical() + [ladder(1, scale=1e-6)]
    return canonical() + [ladder(5), ladder(25), ladder(1, components=25),
                          ladder(5, scale=1e-6)]


class Handler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {**http.server.SimpleHTTPRequestHandler.extensions_map,
                      '.wasm': 'application/wasm', '.mjs': 'text/javascript'}

    def log_message(self, format: str, *args: object) -> None:
        pass

    def end_headers(self) -> None:
        self.send_header('Cache-Control', 'no-store')
        # The ordinary page is deliberately not cross-origin isolated. The
        # measured timer resolution is recorded instead of assumed.
        super().end_headers()


async def run_job(browser, address: str, target: str, req: dict,
                  output: pathlib.Path, timeout: float, sequence: int) -> dict:
    output.mkdir(parents=True, exist_ok=False)
    dump(output / 'request.json', req)
    records, metadata, errors, console = [], [], [], []
    page = await browser.new_page()
    page.on('console', lambda message: console.append(f'{message.type}: {message.text}'))
    page.on('pageerror', lambda error: console.append(f'pageerror: {error}'))
    complete = False
    timed_out = False
    with (output / 'stdout.jsonl').open('w') as raw:
        async def receive(record: dict) -> None:
            # Write the unmodified browser record before independently judging it.
            raw.write(json.dumps(record, allow_nan=False, separators=(',', ':')) + '\n')
            raw.flush()
            if record.get('record') == 'metadata':
                metadata.append(record)
                return
            try:
                native.validate_record(record, req, len(records))
                boundary = record.get('browser_boundary_ns')
                if type(boundary) not in (int, float) or not math.isfinite(boundary) or boundary < 0:
                    raise ValueError('invalid browser boundary duration')
                record['oracle'] = check(req, record)
                if req['engine'] == 'dart_3d_ad' and record['max_z'] > req['tolerance']:
                    record['oracle']['accepted'] = False
                    record['oracle']['violations'].append('workplane_z')
                records.append(record)
            except (ValueError, KeyError, TypeError, AttributeError, OverflowError) as error:
                errors.append(str(error))

        await page.expose_function('comparisonEmit', receive)

        async def evaluate() -> None:
            await page.goto(f'{address}/index.html?target={target}', wait_until='load')
            await page.wait_for_function(
                'globalThis.comparisonHost !== undefined || globalThis.comparisonLoadError !== undefined',
                timeout=timeout * 1000)
            load_error = await page.evaluate('globalThis.comparisonLoadError ?? null')
            if load_error:
                raise RuntimeError(load_error)
            await page.evaluate(
                'request => globalThis.comparisonHost.run(request, record => globalThis.comparisonEmit(record))',
                req)

        try:
            await asyncio.wait_for(evaluate(), timeout=timeout)
            complete = not errors and len(records) == req['warmups'] + req['samples']
        except asyncio.TimeoutError:
            timed_out = True
            errors.append(f'browser job exceeded {timeout} seconds')
        except Exception as error:
            errors.append(str(error))
        finally:
            await page.close()
    (output / 'console.txt').write_text('\n'.join(console) + ('\n' if console else ''))
    with (output / 'validated.jsonl').open('w') as validated:
        for record in records:
            validated.write(json.dumps(record, allow_nan=False, separators=(',', ':')) + '\n')
    summary = native.summarize(records, req)
    accepted = [r for r in records if not r['warmup'] and r['oracle']['accepted']]
    boundary = [r['browser_boundary_ns'] / 1e6 for r in accepted]
    summary.update(
        target=target, engine=req['engine'], mode=req['mode'], fixture_id=req['fixture']['id'],
        sequence=sequence, complete=complete, timed_out=timed_out, errors=errors,
        accepted_boundary_p50_ms=native.percentile(boundary, .50),
        accepted_boundary_p95_ms=native.percentile(boundary, .95),
        metadata=metadata,
        directory=str(output.resolve()),
    )
    dump(output / 'summary.json', summary)
    return summary


async def main_async(args) -> int:
    from playwright.async_api import async_playwright

    args.out.mkdir(parents=True, exist_ok=False)
    artifacts = {}
    for target in args.targets:
        artifacts[target] = []
        for name in ARTIFACTS[target]:
            path = HERE / 'build' / name
            if not path.is_file():
                raise RuntimeError(f'Missing compiled browser artifact: {path}')
            artifacts[target].append(dict(file=name, bytes=path.stat().st_size, sha256=sha(path)))
    source_hashes = {str(p.relative_to(PARENT)): sha(p) for p in [
        HERE / 'dart_entry.dart', HERE / 'host.mjs', HERE / 'solvent.mjs',
        HERE / 'run_browser.py', PARENT / 'dart_adapter_core.dart',
        PARENT / 'fixtures.py', PARENT / 'oracle.py', PARENT / 'run.py',
    ]}
    selected = cases(args.suite)
    if args.fixtures:
        wanted = set(args.fixtures)
        selected = [case for case in selected if case['fixture']['id'] in wanted]
        missing = wanted - {case['fixture']['id'] for case in selected}
        if missing:
            raise ValueError(f'Unknown fixture ids in selected suite: {sorted(missing)}')
    jobs = []
    for target in args.targets:
        engines = ['solvent_cabi_wasm'] if target == 'solvent_wasm' else args.engines
        for engine in engines:
            for mode in args.modes:
                for case in selected:
                    jobs.append((target, request(case, engine, mode, args.warmups, args.samples)))
    random.Random(args.seed).shuffle(jobs)
    environment = dict(
        created_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),
        suite=args.suite, artifacts=artifacts, source_hashes=source_hashes,
        platform=platform.platform(), python=sys.version,
        cpu_affinity=sorted(os.sched_getaffinity(0)) if hasattr(os, 'sched_getaffinity') else None,
        playwright=importlib.metadata.version('playwright'), chromium_executable=args.chromium,
        headless=True, rendering_included=False, targets=args.targets,
        warmups=args.warmups, samples=args.samples, job_count=len(jobs), random_seed=args.seed,
        job_timeout_seconds=args.timeout,
        interpretation='Browser computation and boundary qualification; module load separate; no rendering or UI-frame claim.',
    )
    dump(args.out / 'environment.json', environment)
    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), functools.partial(Handler, directory=str(HERE)))
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    address = f'http://127.0.0.1:{server.server_port}'
    summaries = []
    try:
        async with async_playwright() as playwright:
            browser = await playwright.chromium.launch(
                executable_path=args.chromium, headless=True, args=['--disable-dev-shm-usage'])
            environment['browser_version'] = browser.version
            dump(args.out / 'environment.json', environment)
            try:
                for sequence, (target, req) in enumerate(jobs):
                    name = f"{sequence:03d}_{target}_{req['engine']}_{req['mode']}_{req['fixture']['id']}"
                    summary = await run_job(browser, address, target, req, args.out / name,
                                            args.timeout, sequence)
                    summaries.append(summary)
                    dump(args.out / 'summary.json', summaries)
                    print(json.dumps({k: summary[k] for k in [
                        'sequence', 'target', 'engine', 'mode', 'fixture_id', 'complete',
                        'accepted_samples', 'expected_samples', 'acceptance_disagreements',
                        'accepted_p50_ms', 'accepted_boundary_p50_ms',
                    ]}), flush=True)
            finally:
                await browser.close()
    finally:
        server.shutdown()
        server.server_close()
    return 0 if all(s['complete'] and not s['acceptance_disagreements'] for s in summaries) else 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', type=pathlib.Path, required=True)
    parser.add_argument('--chromium', default='/usr/bin/chromium')
    parser.add_argument('--targets', nargs='+', choices=list(ARTIFACTS), default=['dart2js', 'dart2wasm'])
    parser.add_argument('--engines', nargs='+', choices=DART_ENGINES, default=DART_ENGINES)
    parser.add_argument('--modes', nargs='+', choices=['cold', 'warm'], default=['cold', 'warm'])
    parser.add_argument('--suite', choices=['smoke', 'portable'], default='portable')
    parser.add_argument('--fixtures', nargs='+')
    parser.add_argument('--warmups', type=int, default=3)
    parser.add_argument('--samples', type=int, default=10)
    parser.add_argument('--timeout', type=float, default=60)
    parser.add_argument('--seed', type=int, default=20261114)
    args = parser.parse_args()
    if args.warmups < 0 or args.samples < 1 or args.timeout <= 0:
        parser.error('warmups must be nonnegative and samples/timeout positive')
    return asyncio.run(main_async(args))


if __name__ == '__main__':
    raise SystemExit(main())
