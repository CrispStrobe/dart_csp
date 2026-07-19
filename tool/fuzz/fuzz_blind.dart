/// Blind mutation fuzzing across every dart_csp reader surface.
///
/// Fast (~1M execs/sec) and needs no VM service, so this is the pass that
/// belongs in CI. Exits non-zero if any target lets a non-allow-listed
/// exception escape, or parses slowly enough to suggest an allocation bomb.
///
///     dart run tool/fuzz/fuzz_blind.dart              # all targets
///     dart run tool/fuzz/fuzz_blind.dart flatzinc-parse
///     dart run tool/fuzz/fuzz_blind.dart --budget-ms 5000
library;

import 'dart:io';

import 'package:covfuzz/covfuzz.dart';

import 'targets.dart';

void main(List<String> args) {
  var budgetMs = 15000;
  var iterations = 200000;
  var allowSlow = false;
  final names = <String>[];

  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--budget-ms':
        budgetMs = int.parse(args[++i]);
      case '--iterations':
        iterations = int.parse(args[++i]);
      case '--allow-slow':
        allowSlow = true;
      case '--help' || '-h':
        stdout.writeln('usage: fuzz_blind.dart [--budget-ms N] '
            '[--iterations N] [--allow-slow] [target...]\n'
            'targets: ${allTargets.map((t) => t.name).join(', ')}');
        exit(0);
      default:
        names.add(args[i]);
    }
  }

  final selected = names.isEmpty
      ? allTargets
      : allTargets.where((t) => names.contains(t.name)).toList();

  if (selected.isEmpty) {
    stderr.writeln('no target matched ${names.join(', ')}; '
        'known: ${allTargets.map((t) => t.name).join(', ')}');
    exit(64);
  }

  var worst = 0;
  for (final target in selected) {
    stdout.writeln('\n=== ${target.name} ===');
    final report = fuzz<String>(
      seeds: target.seeds,
      entry: target.entry,
      mutate: mutateString,
      isClean: target.isClean,
      iterations: iterations,
      budgetMs: budgetMs,
      stressors: target.stressors,
    );
    final code = report.report();
    if (code > worst) worst = code;
  }

  // Exit 1 is a contract violation — deterministic given the fixed seed, so
  // it is safe to gate CI on. Exit 2 is the SLOW heuristic, an absolute
  // 200ms-per-parse threshold that a loaded shared runner can trip on timing
  // alone. `--allow-slow` keeps the warning visible without failing the
  // build; run without it locally when investigating performance.
  if (allowSlow && worst == 2) {
    stdout.writeln('\nSLOW reported above, but --allow-slow was passed: '
        'not failing. Re-run without it to gate on timing.');
    worst = 0;
  }

  stdout.writeln(worst == 0
      ? '\nAll ${selected.length} target(s) clean.'
      : '\nFAILED (exit $worst) — see above.');
  exit(worst);
}
