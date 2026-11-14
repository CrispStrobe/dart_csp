import gzip
import hashlib
import json
import pathlib
import shutil
import tarfile
import tempfile
import unittest

from analyze import analyze_runs, write_report


def saved_run(parent, name, specs, *, rounds=None, expected_feasible=True,
              executable='a' * 64):
    root = parent / name
    root.mkdir()
    manifest = dict(
        schema_version=1, suite='synthetic-regression', source_commit='b' * 40,
        library_tree='c' * 40, rounds=rounds or len(specs), samples=3, warmups=1,
        engines=['engine'], fixture_ids=['fixture'], modes=['warm'],
        platform='test-platform', cpu_model='test-cpu', pinned_cpu=0,
        thread_environment={'OMP_NUM_THREADS': '1'}, timing_contract='test-contract',
        executable_sha256={'engine': executable}, source_status='',
    )
    jobs = []
    for number, spec in enumerate(specs):
        repeat = spec.get('round', number + 1)
        directory = root / f'{number:04d}-r{repeat}-engine-warm-fixture'
        directory.mkdir()
        constraints = [dict(kind='distance', a=0, b=1, value=1.0)]
        values = [1.0]
        if not expected_feasible:
            constraints.append(dict(kind='distance', a=0, b=1, value=2.0))
            values.append(2.0)
        req = dict(
            schema_version=1, engine='engine', mode='warm', samples=3, warmups=1,
            tolerance=1e-7,
            fixture=dict(id='fixture', points=[[0., 0.], [1., 0.]], fixed=[0],
                         constraints=constraints, orientations=[],
                         expected_feasible=expected_feasible),
            edits=[dict(values=values)],
        )
        request_bytes = (json.dumps(req, separators=(',', ':')) + '\n').encode()
        (directory / 'request.json.gz').write_bytes(gzip.compress(request_bytes))
        times = spec.get('times', [1., 2., 3.])
        accepted = spec.get('accepted', [expected_feasible] * len(times))
        exceptions = spec.get('exceptions', [False] * len(times))
        native = spec.get('native', accepted)
        adapter_accepted = spec.get('adapter_accepted', accepted)
        errors = spec.get('errors', [0.0 if ok else 1.0 for ok in accepted])
        records = []
        for index in range(-1, len(times)):
            is_warmup = index < 0
            ok = expected_feasible if is_warmup else accepted[index]
            exception = False if is_warmup else exceptions[index]
            error = 0.0 if ok else 1.0
            if not is_warmup:
                error = errors[index]
            records.append(dict(
                schema_version=1, engine='engine', fixture_id='fixture', mode='warm',
                index=index, warmup=is_warmup, build_ns=0, solve_ns=0,
                elapsed_ns=(.1 if is_warmup else times[index]) * 1e6,
                coordinates=[[0., 0.], [1.0 + error, 0.]],
                accepted=ok if is_warmup else adapter_accepted[index],
                reported_success=ok if is_warmup else native[index],
                adapter_error='failure' if exception else None,
                iterations=2, model_reused=not is_warmup,
                oracle=dict(accepted=ok, max_error=error,
                            violations=[] if ok else ['adapter_error' if exception else 'constraint:0'],
                            expected_feasible=expected_feasible),
            ))
        raw = ''.join(json.dumps(record) + '\n' for record in records).encode()
        (directory / 'checked.jsonl.gz').write_bytes(gzip.compress(raw))
        complete = not spec.get('timed_out', False) and len(times) == 3
        jobs.append(dict(
            job_index=number, round=repeat, engine='engine', fixture_id='fixture', mode='warm',
            raw_directory=str(directory), timed_out=spec.get('timed_out', False),
            returncode=-9 if spec.get('timed_out', False) else 0, parse_errors=[],
            request_sha256=hashlib.sha256(request_bytes).hexdigest(),
            command=['/not-executed/engine', str(directory / 'request.json')],
            metadata=[], summary=dict(
                expected_samples=3, completed_samples=len(times), accepted_samples=sum(accepted),
                rejected_samples=len(times) - sum(accepted), complete=complete,
                completed_records=len(records), known_feasible=expected_feasible,
                adapter_exception_samples=sum(exceptions),
                reported_success_rejected=sum(n and not a for n, a in zip(native, accepted)),
                valid_physical_rejections=sum(not a and not e for a, e in zip(accepted, exceptions)),
                acceptance_disagreements=sum(a != b for a, b in zip(accepted, adapter_accepted)),
            ),
        ))
    (root / 'manifest.json').write_text(json.dumps(manifest))
    (root / 'summary.json').write_text(json.dumps(dict(manifest=manifest, jobs=jobs)))
    return root


class SavedAnalysisTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = pathlib.Path(self.temporary.name)

    def test_median_of_process_percentiles_is_not_pooled_percentile(self):
        run = saved_run(self.root, 'complete', [
            dict(times=[1., 2., 100.], errors=[1e-8, 2e-8, 3e-8]),
            dict(times=[3., 4., 5.], errors=[3e-8, 5e-8, 1e-7]),
        ])
        report = analyze_runs([run], include_metrics=True)
        group = report['groups'][0]
        self.assertTrue(group['qualified_latency'])
        self.assertEqual(group['median_process_accepted_p50_ms'], 3.0)
        self.assertEqual(group['median_process_accepted_p95_ms'], 52.5)
        self.assertEqual(group['main']['accepted'], 6)
        self.assertEqual(group['warmups']['accepted'], 2)
        self.assertEqual(group['main']['max_finite_error_over_tolerance'], 1.0)
        self.assertEqual(report['jobs'][0]['metrics']['iterations']['median'], 2)
        paths = write_report(report, self.root / 'output')
        self.assertTrue(all(path.is_file() for path in paths))
        json.loads(paths[0].read_text())
        self.assertIn('not a percentile of pooled observations', paths[1].read_text())

    def test_one_incomplete_process_suppresses_whole_group_headline(self):
        run = saved_run(self.root, 'partial', [
            dict(times=[1., 2., 3.]), dict(times=[.1, .2], timed_out=True),
        ])
        group = analyze_runs([run])['groups'][0]
        self.assertFalse(group['qualified_latency'])
        self.assertIsNone(group['median_process_accepted_p50_ms'])
        self.assertIsNone(group['median_process_accepted_p95_ms'])
        self.assertEqual(group['main']['accepted'], 5)
        self.assertEqual(group['main']['expected'], 6)
        self.assertEqual(group['complete_jobs'], 1)
        self.assertEqual(group['timeout_jobs'], 1)
        self.assertIsNotNone(group['descriptive_only']['median_available_process_accepted_p50_ms'])

    def test_rejected_sample_is_not_hidden_by_accepted_only_timings(self):
        run = saved_run(self.root, 'rejection', [
            dict(times=[.1, .2, 50.], accepted=[True, True, False]),
        ])
        group = analyze_runs([run])['groups'][0]
        self.assertEqual(group['complete_jobs'], 1)
        self.assertFalse(group['qualified_latency'])
        self.assertIsNone(group['median_process_accepted_p50_ms'])
        self.assertEqual(group['descriptive_only']['median_available_process_accepted_p50_ms'], .2)

    def test_contradiction_does_not_credit_exception(self):
        run = saved_run(self.root, 'contradiction-error', [
            dict(accepted=[False, False, False], exceptions=[False, True, False],
                 native=[True, False, True]),
        ], expected_feasible=False)
        group = analyze_runs([run])['groups'][0]
        self.assertEqual(group['main']['valid_rejections'], 2)
        self.assertEqual(group['main']['adapter_exceptions'], 1)
        self.assertEqual(group['main']['native_success_rejected'], 2)
        self.assertEqual(group['main']['expected'], 3)
        self.assertFalse(group['all_infeasible_jobs_validly_rejected'])
        self.assertFalse(group['qualified_latency'])

    def test_native_convergence_and_valid_physical_rejection_are_separate(self):
        run = saved_run(self.root, 'contradiction-valid', [
            dict(accepted=[False, False, False], native=[True, True, True]),
        ], expected_feasible=False)
        group = analyze_runs([run])['groups'][0]
        self.assertEqual(group['main']['valid_rejections'], 3)
        self.assertEqual(group['main']['native_success_rejected'], 3)
        self.assertTrue(group['all_infeasible_jobs_validly_rejected'])
        self.assertEqual(group['acceptance_disagreements'], 0)
        self.assertIsNone(group['median_process_accepted_p50_ms'])

    def test_missing_planned_round_is_not_dropped(self):
        run = saved_run(self.root, 'missing-round', [dict()], rounds=2)
        group = analyze_runs([run])['groups'][0]
        self.assertEqual(group['jobs'], 2)
        self.assertEqual(group['missing_jobs'], 1)
        self.assertEqual(group['main']['accepted'], 3)
        self.assertEqual(group['main']['expected'], 6)
        self.assertFalse(group['qualified_latency'])

    def test_different_executable_builds_are_not_pooled(self):
        first = saved_run(self.root, 'first', [dict()])
        second = saved_run(self.root, 'second', [dict()], executable='d' * 64)
        group = analyze_runs([first, second])['groups'][0]
        self.assertEqual(group['complete_jobs'], 2)
        self.assertIn('different_executable_builds', group['exclusion_reasons'])
        self.assertFalse(group['qualified_latency'])

    def test_packed_remote_evidence_matches_unpacked_counts_and_timings(self):
        run = saved_run(self.root, 'packed', [dict()])
        before = analyze_runs([run])['groups']
        summary = run / 'summary.json'
        (run / 'summary.json.gz').write_bytes(gzip.compress(summary.read_bytes()))
        summary.unlink()
        directories = [path for path in run.iterdir() if path.is_dir()]
        with tarfile.open(run / 'raw-000.tar.gz', 'w:gz') as archive:
            for directory in directories:
                archive.add(directory, arcname=directory.name)
        for directory in directories:
            shutil.rmtree(directory)
        after = analyze_runs([run])
        self.assertEqual(before, after['groups'])
        self.assertEqual(len(after['inputs'][0]['archives_read']), 1)
        self.assertTrue(after['groups'][0]['qualified_latency'])

    def test_saved_summary_disagreement_excludes_latency(self):
        run = saved_run(self.root, 'changed-summary', [dict()])
        path = run / 'summary.json'
        data = json.loads(path.read_text())
        data['jobs'][0]['summary']['accepted_samples'] = 2
        path.write_text(json.dumps(data))
        report = analyze_runs([run])
        self.assertIn('summary_mismatch:accepted_samples', report['jobs'][0]['analysis_issues'])
        self.assertFalse(report['groups'][0]['qualified_latency'])


if __name__ == '__main__':
    unittest.main()
