// Smoke tests for `bin/dart_csp_fzn.dart`. Runs the binary as a
// subprocess so the test exercises the same code path a MiniZinc
// solver configuration would invoke.

import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';

Future<({int exit, String stdout, String stderr})> runCli(
  List<String> args, {
  String? stdinSource,
}) async {
  final process = await Process.start(
    Platform.executable,
    <String>[
      'run',
      '/Users/christianstrobele/code/dart_csp/bin/dart_csp_fzn.dart',
      ...args,
    ],
    workingDirectory: '/Users/christianstrobele/code/dart_csp',
  );
  if (stdinSource != null) {
    process.stdin.write(stdinSource);
  }
  unawaited(process.stdin.close());
  final outFut =
      process.stdout.transform(const SystemEncoding().decoder).join();
  final errFut =
      process.stderr.transform(const SystemEncoding().decoder).join();
  final exit = await process.exitCode;
  return (exit: exit, stdout: await outFut, stderr: await errFut);
}

void main() {
  group('dart_csp_fzn CLI', () {
    test('--help prints usage and exits 0', () async {
      final r = await runCli(['--help']);
      expect(r.exit, 0);
      expect(r.stdout, contains('FlatZinc frontend'));
      expect(r.stdout, contains('Options:'));
    });

    test('reads from stdin and emits standard FZN output', () async {
      final r = await runCli([], stdinSource: '''
var 1..3: x :: output_var;
constraint int_eq(x, 2);
solve satisfy;
''');
      expect(r.exit, 0);
      expect(r.stdout, contains('x = 2;'));
      expect(r.stdout, contains('----------'));
    });

    test('reads from a file path', () async {
      final tmp = await File('${Directory.systemTemp.path}/'
              'dart_csp_cli_test_${DateTime.now().microsecondsSinceEpoch}.fzn')
          .create();
      await tmp.writeAsString('''
var 0..9: x :: output_var;
solve minimize x;
''');
      try {
        final r = await runCli([tmp.path]);
        expect(r.exit, 0);
        expect(r.stdout, contains('x = 0;'));
        expect(r.stdout.trim().split('\n').last, '==========');
      } finally {
        await tmp.delete();
      }
    });

    test('-a streams every solution and terminates with ==========', () async {
      final r = await runCli(['-a'], stdinSource: '''
var 1..3: x :: output_var;
solve satisfy;
''');
      expect(r.exit, 0);
      final lines = r.stdout.trim().split('\n');
      expect(lines.last, '==========');
      expect(lines.where((l) => l == '----------').length, 3);
    });

    test('-s appends an mzn-stat block', () async {
      final r = await runCli(['-s'], stdinSource: '''
var 1..3: x :: output_var;
solve satisfy;
''');
      expect(r.exit, 0);
      expect(r.stdout, contains('%%%mzn-stat: decisions='));
      expect(r.stdout, contains('%%%mzn-stat-end'));
    });

    test('parse errors exit with non-zero status', () async {
      final r = await runCli([], stdinSource: 'this is not flatzinc\n');
      expect(r.exit, isNot(0));
      expect(r.stderr, contains('dart_csp_fzn:'));
    });

    test('unknown option exits 64 (EX_USAGE)', () async {
      final r = await runCli(['--bogus-flag']);
      expect(r.exit, 64);
      expect(r.stderr, contains('unknown option'));
    });

    test('missing file exits 66 (EX_NOINPUT)', () async {
      final r = await runCli(['/no/such/file.fzn']);
      expect(r.exit, 66);
      expect(r.stderr, contains('file not found'));
    });
  });
}
