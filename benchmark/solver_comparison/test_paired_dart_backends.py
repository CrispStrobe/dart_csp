"""Freeze and qualification boundaries for paired pure-Dart backend measurements."""
import argparse
import contextlib
import io
import json
from pathlib import Path
import shutil
import tempfile
import unittest
from unittest import mock

import paired_dart_backends as paired


class PairedDartBackendTest(unittest.TestCase):
    def test_changed_adapter_or_package_input_prevents_pairing(self):
        names = (*paired.ADAPTERS, 'pubspec.yaml', 'pubspec.lock')
        before = dict(source_sha256={name: 'same' for name in names})
        paired.require_identical_adapters(before, before)
        for name in names:
            after = dict(source_sha256={**before['source_sha256'], name: 'changed'})
            with self.subTest(name=name), self.assertRaisesRegex(ValueError, 'differ'):
                paired.require_identical_adapters(before, after)

    def test_pair_order_reverses_for_each_fixture_on_next_round(self):
        for case in range(3):
            for mode in range(2):
                for engine in range(2):
                    first = paired.paired_order(0, case, mode, engine, ['before', 'after'])
                    second = paired.paired_order(1, case, mode, engine, ['before', 'after'])
                    self.assertEqual(first, list(reversed(second)))
        self.assertEqual(paired.paired_order(1, 0, 0, 0, ['after']), ['after'])

    def test_failed_or_missing_side_never_receives_a_latency_ratio(self):
        field = 'median_process_accepted_p50_ms'
        good = dict(qualified_latency=True, **{field: 2.0})
        self.assertEqual(paired.qualified_ratio(good, {**good, field: 1.0}, field), 0.5)
        for bad in (None, {**good, 'qualified_latency': False}, {**good, field: 0.0}):
            with self.subTest(bad=bad):
                self.assertIsNone(paired.qualified_ratio(bad, good, field))

    def prepared(self, root, *, fail_warmup=False):
        root.mkdir()
        (root / 'harness').mkdir()
        for name in paired.HARNESSES:
            shutil.copyfile(paired.HERE / name, root / 'harness' / name)
        # Synthetic process output exercises orchestration/qualification only.
        # No Dart compilation or performance claim is part of these unit tests.
        program = '''#!/usr/bin/env python3
import copy,json,sys
r=json.load(open(sys.argv[1]))
for i in range(-r['warmups'],r['samples']):
 e=r['edits'][(i+r['warmups'])%len(r['edits'])]
 points=copy.deepcopy(e['known_solution'])
 accepted=True
 if FAIL_WARMUP and i<0:
  points[0][0]+=0.1
  accepted=False
 print(json.dumps(dict(schema_version=1,fixture_id=r['fixture']['id'],engine=r['engine'],mode=r['mode'],index=i,warmup=i<0,build_ns=1,solve_ns=2,elapsed_ns=3,coordinates=points,accepted=accepted)),flush=True)
'''.replace('FAIL_WARMUP', repr(fail_warmup))
        variants = {}
        for variant in ('before', 'after'):
            (root / variant).mkdir()
            executable = root / variant / 'fake-adapter'
            executable.write_text(program)
            executable.chmod(0o755)
            archive = root / variant / 'source.tar.gz'
            archive.write_bytes(b'synthetic-unit-test-source')
            variants[variant] = dict(source=dict(source_commit='a' * 40, library_tree='b' * 40,
                                                 test_tree='c' * 40, source_status=''),
                                     executable=str(executable.relative_to(root)), executable_sha256=paired.sha(executable),
                                     source_archive=str(archive.relative_to(root)), source_archive_sha256=paired.sha(archive))
        manifest = dict(status='complete', variants=variants,
                        harness_sha256={name: paired.sha(paired.HERE / name) for name in paired.HARNESSES})
        paired.dump(root / 'prepared.json', manifest)
        return manifest

    def test_replaced_executable_is_detected_before_execution(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder) / 'prepared'
            manifest = self.prepared(root)
            paired.verify_artifacts(root, manifest, ['before', 'after'])
            (root / manifest['variants']['after']['executable']).write_text('changed binary')
            with self.assertRaisesRegex(ValueError, 'executable changed'):
                paired.verify_artifacts(root, manifest, ['after'])

    def run_fake(self, directory, *, fail_warmup=False):
        prepared = directory / 'prepared'
        self.prepared(prepared, fail_warmup=fail_warmup)
        args = argparse.Namespace(rounds=2, samples=1, warmups=1, timeout=5,
                                  variants='before,after', engines='dart_2d_analytic', modes='cold',
                                  suites='smoke', fixtures='canonical_cell', prepared=prepared,
                                  cpu='none', out=directory / 'run', purpose='qualification')
        with contextlib.redirect_stdout(io.StringIO()):
            code = paired.run(args)
        return code, args.out

    def test_successful_pair_retains_identical_requests_and_raw_outputs(self):
        with tempfile.TemporaryDirectory() as folder:
            code, output = self.run_fake(Path(folder))
            self.assertEqual(code, 0)
            parent = json.loads((output / 'manifest.json').read_text())
            hashes = []
            for variant in ('before', 'after'):
                summary = json.loads((output / variant / 'summary.json').read_text())
                self.assertEqual(len(summary['jobs']), 2)
                manifest = json.loads((output / variant / 'manifest.json').read_text())
                self.assertEqual(manifest, summary['manifest'])
                self.assertEqual(manifest['status'], 'complete')
                self.assertEqual(manifest['completed_jobs'], 2)
                for key in ('finished_utc', 'analysis_finished_utc',
                            'protocol_ok', 'qualification_passed'):
                    self.assertEqual(manifest[key], parent[key])
                hashes.append([job['request_sha256'] for job in summary['jobs']])
                for job in summary['jobs']:
                    raw = Path(job['raw_directory'])
                    for name in ('request.json.gz', 'stdout.jsonl.gz', 'checked.jsonl.gz', 'stderr.txt', 'job.json'):
                        self.assertTrue((raw / name).is_file())
                    self.assertIn('started_utc', json.loads((raw / 'job.json').read_text()))
            self.assertEqual(*hashes)
            result = json.loads((output / 'comparison.json').read_text())
            self.assertTrue(result['qualification_passed'])
            self.assertEqual(result['groups'][0]['after_over_before_p50'], 1.0)

    def test_feasible_warmup_rejection_fails_candidate_qualification(self):
        with tempfile.TemporaryDirectory() as folder:
            code, output = self.run_fake(Path(folder), fail_warmup=True)
            self.assertEqual(code, 1)
            result = json.loads((output / 'comparison.json').read_text())
            self.assertTrue(result['protocol_ok'])
            self.assertFalse(result['qualification_passed'])
            for variant in ('before', 'after'):
                manifest = json.loads((output / variant / 'manifest.json').read_text())
                self.assertEqual(manifest['status'], 'complete')
                self.assertTrue(manifest['protocol_ok'])
                self.assertFalse(manifest['qualification_passed'])

    def test_interrupted_collection_preserves_failure_and_completed_job_counts(self):
        run_job = paired.run_job
        calls = 0

        def interrupt_second_job(*args, **kwargs):
            nonlocal calls
            calls += 1
            if calls == 2:
                raise RuntimeError('synthetic collection interruption')
            return run_job(*args, **kwargs)

        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder) / 'run'
            with mock.patch.object(paired, 'run_job', side_effect=interrupt_second_job), \
                    self.assertRaisesRegex(RuntimeError, 'synthetic collection interruption'):
                self.run_fake(Path(folder))
            parent = json.loads((output / 'manifest.json').read_text())
            self.assertEqual(parent['status'], 'failed')
            for variant, expected_jobs in (('before', 1), ('after', 0)):
                manifest = json.loads((output / variant / 'manifest.json').read_text())
                summary = json.loads((output / variant / 'summary.json').read_text())
                self.assertEqual(manifest, summary['manifest'])
                self.assertEqual(manifest['status'], 'failed')
                self.assertEqual(manifest['error'], 'synthetic collection interruption')
                self.assertEqual(manifest['finished_utc'], parent['finished_utc'])
                self.assertEqual(manifest['completed_jobs'], expected_jobs)
                self.assertEqual(len(summary['jobs']), expected_jobs)
                self.assertNotIn('analysis_finished_utc', manifest)
                self.assertNotIn('qualification_passed', manifest)


if __name__ == '__main__':
    unittest.main()
