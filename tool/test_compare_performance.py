"""Runner boundary regressions, using fake processes rather than Dart timings."""
import hashlib
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import unittest


RUNNER = pathlib.Path(__file__).with_name('compare_performance.py')
STDOUT = b' \r\n{"ok":true}\r\n '
STDERR = b'\xff warning\r\n '
FAKE = '''import os, pathlib, sys, time
if '--version' in sys.argv:
    print('Dart test fixture')
elif 'compile' in sys.argv:
    target = pathlib.Path(sys.argv[sys.argv.index('-o') + 1])
    target.write_text(pathlib.Path(__file__).read_text())
    target.chmod(0o755)
else:
    os.write(1, b' \\r\\n{"ok":true}\\r\\n ')
    os.write(2, b'\\xff warning\\r\\n ')
    mode = os.environ.get('FAKE_MODE')
    if mode == 'timeout':
        time.sleep(5)
    if mode == 'mutate':
        pathlib.Path('lib/probe.dart').write_text('// changed during execution\\n')
    sys.exit(7 if mode == 'fail' else 0)
'''


class RunnerBoundaryTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='runner-test-')
        self.addCleanup(self.temporary.cleanup)
        self.root = pathlib.Path(self.temporary.name)
        self.before, self.after = [self.root / label for label in ('before', 'after')]
        self.before.mkdir()
        for relative in ('lib/probe.dart', 'benchmark/probe.dart', 'pubspec.lock'):
            path = self.before / relative
            path.parent.mkdir(exist_ok=True)
            path.write_text('// fixture\n')
        self.git(self.before, 'init', '-q')
        self.git(self.before, 'add', '.')
        self.git(self.before, '-c', 'user.name=Runner test', '-c',
                 'user.email=runner@example.invalid', 'commit', '-qm', 'fixture')
        self.git(self.root, 'clone', '--quiet', '--local', str(self.before), str(self.after))
        for root in (self.before, self.after):
            (root / '.dart_tool').mkdir()
            self.write_config(root)
        self.dart = self.root / 'fake-dart'
        self.dart.write_text('#!' + sys.executable + '\n' + FAKE)
        self.dart.chmod(0o755)
        self.output = self.root / 'result.json'

    def git(self, root, *arguments):
        return subprocess.run(['git', *arguments], cwd=root, capture_output=True, check=True)

    def write_config(self, root, **overrides):
        package = dict(name='dart_csp', rootUri='../', packageUri='lib/')
        package.update(overrides)
        (root / '.dart_tool/package_config.json').write_text(json.dumps(
            dict(configVersion=2, packages=[package])))

    def execute(self, mode='jit', fake_mode=''):
        completed = subprocess.run([
            sys.executable, str(RUNNER), '--before', str(self.before),
            '--after', str(self.after), '--dart', str(self.dart),
            '--benchmarks', 'probe', '--modes', mode, '--rounds', '1',
            '--run-timeout', '1', '--output', str(self.output),
        ], capture_output=True, env={**os.environ, 'FAKE_MODE': fake_mode})
        return completed, json.loads(self.output.read_text())

    def test_mode_selection_and_exact_output(self):
        for mode in ('jit', 'aot'):
            with self.subTest(mode=mode):
                completed, data = self.execute(mode)
                self.assertEqual(completed.returncode, 0, completed.stderr)
                self.assertEqual(data['status'], 'completed')
                self.assertTrue(data['diagnostic_only'])
                self.assertEqual([run['mode'] for run in data['runs']], [mode, mode])
                compiled = [p for p in data['process_records']
                            if p['context'] and p['context']['phase'] == 'compile']
                self.assertEqual(len(compiled), 2 if mode == 'aot' else 0)
                for run in data['runs']:
                    self.assertEqual(run['result'], {'ok': True})
                    process = data['process_records'][run['process_record']]
                    self.assertEqual(process['stdout'].encode('utf-8', 'surrogateescape'), STDOUT)
                    self.assertEqual(process['stderr'].encode('utf-8', 'surrogateescape'), STDERR)
                    self.assertEqual(process['stdout_sha256'], hashlib.sha256(STDOUT).hexdigest())
                configured = compiled if mode == 'aot' else [data['process_records'][r['process_record']] for r in data['runs']]
                self.assertTrue(all('--packages=' + p['cwd'] + '/.dart_tool/package_config.json' in p['command'] for p in configured))
                revision = data['revisions']['before']
                self.assertEqual(revision['package_mapping']['resolved_library'], str(self.before / 'lib'))
                self.assertEqual(revision['library_file_sha256'], {'lib/probe.dart': hashlib.sha256(b'// fixture\n').hexdigest()})

    def test_rejects_wrong_effective_package_root(self):
        for override in ({'rootUri': self.before.as_uri() + '/'}, {'packageUri': '../before/lib/'}):
            with self.subTest(override=override):
                self.write_config(self.after, **override)
                completed, data = self.execute()
                self.assertNotEqual(completed.returncode, 0)
                self.assertEqual(data['status'], 'failed')
                self.assertIn('another source tree', data['failure'])
                self.assertEqual(data['runs'], [])

    def test_rejects_untracked_library_file(self):
        (self.after / 'lib/untracked.dart').write_text('// untracked\n')
        completed, data = self.execute()
        self.assertNotEqual(completed.returncode, 0)
        self.assertIn('clean and committed', data['failure'])

    def test_failure_and_timeout_are_saved(self):
        for mode in ('fail', 'timeout'):
            with self.subTest(mode=mode):
                completed, data = self.execute(fake_mode=mode)
                self.assertNotEqual(completed.returncode, 0)
                self.assertEqual(data['status'], 'failed')
                process = data['process_records'][data['failed_process_record']]
                self.assertEqual(process['stdout'].encode('utf-8', 'surrogateescape'), STDOUT)
                self.assertEqual(process['stderr'].encode('utf-8', 'surrogateescape'), STDERR)
                self.assertEqual(process['exit_code'], None if mode == 'timeout' else 7)
                self.assertEqual(process['timed_out'], mode == 'timeout')

    def test_source_mutation_fails_final_identity_check(self):
        completed, data = self.execute(fake_mode='mutate')
        self.assertNotEqual(completed.returncode, 0)
        self.assertIn('clean and committed', data['failure'])
        self.assertTrue(data['runs'])


if __name__ == '__main__':
    unittest.main()
