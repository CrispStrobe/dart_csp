/// Complete finite-domain assumption construction and solve batches.
///
/// The same harness runs at the before/after source revisions. Large domains
/// are compact ranges; the explicit 100-value case controls for added snapshot
/// overhead. Each operation creates its model and wrapper, posts one assumption
/// and solves. Per-operation statistics snapshots are inside the timer;
/// independent value checks and work aggregation are outside timers.
library;

import 'dart:convert';

import 'package:dart_csp/dart_csp.dart';

Map<String, Object> _measurement(
    List<int> samples, List<Map<String, int>> work) {
  final sorted = [...samples]..sort();
  final middle = sorted.length ~/ 2;
  return {
    'p50': sorted.length.isOdd
        ? sorted[middle]
        : (sorted[middle - 1] + sorted[middle]) / 2,
    'p95': sorted[(sorted.length * .95).ceil() - 1],
    'samples_us': samples,
    'work_per_sample': work,
  };
}

Future<void> main(List<String> arguments) async {
  var samples = 25, warmups = 5, operations = 8;
  for (final argument in arguments) {
    final parts = argument.split('=');
    if (parts.length != 2) throw ArgumentError('Unknown argument $argument.');
    switch (parts.first) {
      case '--samples':
        samples = int.parse(parts.last);
      case '--warmups':
        warmups = int.parse(parts.last);
      case '--operations':
        operations = int.parse(parts.last);
      default:
        throw ArgumentError('Unknown argument $argument.');
    }
  }
  if (samples < 1 || warmups < 0 || operations < 1) {
    throw ArgumentError('Use positive samples/operations and >=0 warmups.');
  }
  final results = <Map<String, Object>>[];
  for (final fixture in [
    (name: 'explicit_100', cardinality: 100, compact: false),
    (name: 'range_1000', cardinality: 1000, compact: true),
    (name: 'range_1000000', cardinality: 1000000, compact: true),
  ]) {
    for (final assumption in ['equals', 'not_equals', 'in_set']) {
      final timings = <int>[];
      final work = <Map<String, int>>[];
      for (var iteration = -warmups; iteration < samples; iteration++) {
        final outcomes = <({dynamic result, SolverStats stats})>[];
        final watch = Stopwatch()..start();
        for (var operation = 0; operation < operations; operation++) {
          final problem = Problem();
          if (fixture.compact) {
            problem.addRangeVariable('x', 0, fixture.cardinality - 1);
          } else {
            problem.addVariable('x', [
              for (var value = 0; value < fixture.cardinality; value++) value
            ]);
          }
          final solver = IncrementalSolver(problem);
          final target = fixture.cardinality ~/ 2 + operation % 2;
          switch (assumption) {
            case 'equals':
              solver.assumeEquals('x', target);
            case 'not_equals':
              solver.assumeNotEquals('x', 0);
            case 'in_set':
              solver.assumeInSet('x', {target});
          }
          final result = await solver.solve();
          outcomes.add((result: result, stats: CSP.lastStats!.snapshot()));
        }
        watch.stop();
        final counts = <String, int>{
          'operations': operations,
          'decisions': 0,
          'propagations': 0,
          'nary_revises': 0,
          'backtracks': 0,
        };
        for (var operation = 0; operation < operations; operation++) {
          final outcome = outcomes[operation];
          final expected = assumption == 'not_equals'
              ? 1
              : fixture.cardinality ~/ 2 + operation % 2;
          if (outcome.result is! Map<String, dynamic> ||
              (outcome.result as Map<String, dynamic>)['x'] != expected) {
            throw StateError('Independent assumption oracle failed for '
                '${fixture.name}/$assumption/$operation.');
          }
          counts['decisions'] = counts['decisions']! + outcome.stats.decisions;
          counts['propagations'] =
              counts['propagations']! + outcome.stats.propagations;
          counts['nary_revises'] =
              counts['nary_revises']! + outcome.stats.naryRevises;
          counts['backtracks'] =
              counts['backtracks']! + outcome.stats.backtracks;
        }
        if (iteration >= 0) {
          timings.add(watch.elapsedMicroseconds);
          work.add(counts);
        }
      }
      results.add({
        'name': '${fixture.name}/$assumption',
        'domain_cardinality': fixture.cardinality,
        'compact': fixture.compact,
        'complete_assumption_solve_us': _measurement(timings, work),
      });
    }
  }
  print(jsonEncode({
    'benchmark': 'incremental_assumptions',
    'units': 'microseconds_per_batch',
    'operations_per_batch': operations,
    'independent_checks': 'passed',
    'timed_work': 'model and wrapper construction, assumption posting, solve, '
        'result retention and statistics snapshot; excludes independent checks '
        'and work aggregation',
    'samples': samples,
    'warmups': warmups,
    'results': results,
  }));
}
