/// Coverage-guided fuzzing for a single dart_csp reader surface.
///
/// Slower than `fuzz_blind.dart` (~100–1000 execs/sec, since every input is
/// followed by a VM-service coverage query), but it evolves a corpus toward
/// the deep paths behind preconditions that blind mutation rarely satisfies —
/// e.g. constraint handlers that only run once a model parses *and* lowers.
///
/// Must run with the VM service enabled:
///
///     dart run --enable-vm-service=0 --no-pause-isolates-on-exit \
///       tool/fuzz/covfuzz_target.dart flatzinc-lower
///
/// The corpus persists under `.fuzz-corpus/<target>/` and is reloaded on the
/// next run, so coverage accumulates across sessions. Crashes land in
/// `.fuzz-crashes/<target>/`. Both are gitignored.
library;

import 'dart:io';

import 'package:covfuzz/covfuzz.dart';

import 'targets.dart';

Future<void> main(List<String> args) async {
  var budgetMs = 60000;
  var iterations = 20000;
  final names = <String>[];

  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--budget-ms':
        budgetMs = int.parse(args[++i]);
      case '--iterations':
        iterations = int.parse(args[++i]);
      case '--help' || '-h':
        stdout.writeln('usage: dart run --enable-vm-service=0 '
            '--no-pause-isolates-on-exit covfuzz_target.dart '
            '[--budget-ms N] [--iterations N] <target>\n'
            'targets: ${allTargets.map((t) => t.name).join(', ')}');
        exit(0);
      default:
        names.add(args[i]);
    }
  }

  if (names.length != 1) {
    stderr.writeln('expected exactly one target; '
        'known: ${allTargets.map((t) => t.name).join(', ')}');
    exit(64);
  }

  final target = allTargets.firstWhere(
    (t) => t.name == names.single,
    orElse: () {
      stderr.writeln('unknown target ${names.single}');
      exit(64);
    },
  );

  stdout.writeln('=== ${target.name} (coverage-guided) ===');
  final report = await covFuzz<String>(
    seeds: target.seeds,
    entry: target.entry,
    mutate: mutateString,
    targetLib: target.targetLib,
    isClean: target.isClean,
    iterations: iterations,
    budgetMs: budgetMs,
    corpusDir: '.fuzz-corpus/${target.name}',
    crashDir: '.fuzz-crashes/${target.name}',
    log: true,
  );
  exit(report.report());
}
