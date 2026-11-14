"""Small synthetic collector checks; no Dart or profiling workload is run."""
import hashlib
import json
import pathlib
import sys
import tempfile
import unittest
from unittest import mock

import profile_cad_phases as collector


def fixture_result(samples):
    return dict(measured_iterations=samples, warmup_iterations=0,
                independent_physical_reuse_rollback_checks='passed',
                measurements={'selective_coupler_length_edit': {
                    'samples_us': list(range(1, samples + 1)),
                    'work_per_sample': [{} for _ in range(samples)]}})


def operation(index):
    return dict(ph='X', name='cad_operation/selective_coupler_length_edit',
                cat='Dart', pid=1, tid=1, ts=index * 1000, dur=100,
                args=dict(case='selective_coupler_length_edit', iteration=index))


class CollectorTest(unittest.TestCase):
    def test_background_compiler_end_arguments_and_p99(self):
        events = [operation(i) for i in range(100)] + [
            dict(ph='B', cat='Compiler', name='CompileFunctionOptimizedBackground',
                 pid=1, tid=2, ts=99010, args={'isolateId': 'test'}),
            dict(ph='E', cat='Compiler', name='CompileFunctionOptimizedBackground',
                 pid=1, tid=2, ts=99070, args={'function': 'target'}),
            dict(ph='X', cat='Compiler', name='Deoptimize', pid=1, tid=1, ts=99050, dur=30),
            dict(ph='X', cat='GC', name='Scavenge', pid=1, tid=1, ts=99030, dur=20),
            dict(ph='X', cat='GC', name='OtherProcess', pid=2, tid=1, ts=99000, dur=100),
        ]
        analysis = collector.analyze_trace(events, fixture_result(100), 100, 0)
        case = analysis['cases']['selective_coupler_length_edit']
        self.assertEqual(case['instrumented_stopwatch_p99_us'], 99)
        self.assertEqual(case['at_or_above_p99_count'], 2)
        top = case['top_samples'][0]
        self.assertEqual(top['iteration'], 99)
        self.assertEqual(top['same_thread_gc_overlap_us'], 20)
        self.assertEqual(top['any_thread_gc_overlap_us'], 20)
        self.assertEqual(top['same_thread_compiler_overlap_us'], 30)
        self.assertEqual(top['any_thread_compiler_overlap_us'], 70)
        background = next(e for e in top['compiler_events'] if not e['same_thread'])
        self.assertEqual(background['arguments'], {'isolateId': 'test', 'function': 'target'})
        self.assertEqual(background['overlap_us'], 60)

    def test_process_output_and_launch_failure_are_lossless(self):
        record = collector.process([sys.executable, '-c',
            'import os; os.write(1,b" \\xff\\r\\n "); os.write(2,b"err\\r\\n"); raise SystemExit(7)'], '.')
        self.assertEqual(record['exit_code'], 7)
        self.assertEqual(record['stdout'].encode('utf-8', 'surrogateescape'), b' \xff\r\n ')
        self.assertEqual(record['stdout_sha256'], hashlib.sha256(b' \xff\r\n ').hexdigest())
        failed = collector.process(['/no/such/collector-test-executable'], '.')
        self.assertIsNone(failed['exit_code'])
        self.assertTrue(failed['error'])

    def test_source_mapping_and_failure_checkpoint(self):
        with tempfile.TemporaryDirectory(prefix='phase-collector-test-') as directory:
            root = pathlib.Path(directory)
            roots = [root / label for label in ('before', 'after')]
            for checkout in roots:
                for relative in ('lib/probe.dart', 'pubspec.lock',
                                 'benchmark/cad_linkage.dart',
                                 'example/parametric_linkage.dart', 'example/nonlinear_linkage.dart'):
                    path = checkout / relative
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_text('fixture\n')
                (checkout / '.dart_tool').mkdir()
                (checkout / '.dart_tool/package_config.json').write_text(json.dumps({
                    'packages': [dict(name='dart_csp', rootUri='../', packageUri='lib/')]}))
            dart = root / 'fake-dart'
            dart.write_text('fake SDK identity\n')
            output = root / 'result.json'
            arguments = ['collector', '--before', str(roots[0]), '--after', str(roots[1]),
                         '--dart', str(dart), '--benchmarks', 'cad_linkage', '--modes', 'jit',
                         '--rounds', '1', '--samples', '1', '--warmups', '0', '--output', str(output)]
            def git(_root, *args):
                return '' if args[0] == 'status' else 'fixture-identity'
            def process(command, cwd, timeout):
                stdout = b'Dart SDK version: fixture\n'
                if '--version' not in command:
                    pathlib.Path(command[-3]).write_bytes(b'[invalid trace\xff\r\n')
                    stdout = b'invalid result\xff\r\n'
                return dict(command=command, cwd=str(cwd), stdout=stdout.decode('utf-8', 'surrogateescape'),
                            stderr='', stdout_sha256=collector.digest(stdout),
                            stderr_sha256=collector.digest(b''), exit_code=0, timed_out=False)
            with mock.patch.object(collector, 'git', git), mock.patch.object(collector, 'process', process):
                identity = collector.source_identity(roots[0])
                self.assertEqual(identity['package_mapping']['resolved_library'], str(roots[0] / 'lib'))
                with mock.patch.object(sys, 'argv', arguments), self.assertRaises(json.JSONDecodeError):
                    collector.main()
                data = json.loads(output.read_text())
                self.assertEqual(data['status'], 'failed')
                self.assertTrue(data['diagnostic_only'])
                self.assertEqual(len(data['process_records']), 2)  # SDK then one JIT, no compilation.
                self.assertEqual(data['runs'][0]['trace_utf8'].encode('utf-8', 'surrogateescape'),
                                 b'[invalid trace\xff\r\n')
                self.assertEqual(data['runs'][0]['status'], 'failed')
                config = roots[0] / '.dart_tool/package_config.json'
                config.write_text(json.dumps({'packages': [dict(
                    name='dart_csp', rootUri='../', packageUri='../after/lib/')]}))
                with self.assertRaisesRegex(ValueError, 'another source tree'):
                    collector.source_identity(roots[0])


if __name__ == '__main__':
    unittest.main()
