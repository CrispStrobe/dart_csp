/// Worked examples for the conflict-explanation API: deletion-based
/// MUS, QuickXplain, and per-`addX`-call labels surfaced on
/// `ConstraintRef.label`.
///
/// Run with:
///
///   dart run example/conflict_explanation.dart
///
/// See `doc/conflict-explanation.md` for the algorithmic background.
library;

import 'package:dart_csp/dart_csp.dart';

Future<void> main() async {
  print('=== Conflict-explanation examples ===\n');

  await unlabeledTriangle();
  await labeledTriangle();
  await algorithmComparison();
  await decomposedHelperCluster();
  await schedulingScenario();
}

/// Without labels, MUS output is technically correct but not very
/// readable on real models — refs are auto-named `b0` / `n3` / etc.
Future<void> unlabeledTriangle() async {
  print('1. Triangle 3-coloring with 2 colors — no labels');
  final p = Problem()
    ..addVariables(['a', 'b', 'c'], [1, 2])
    ..addConstraint(['a', 'b'], (dynamic a, dynamic b) => a != b)
    ..addConstraint(['b', 'c'], (dynamic b, dynamic c) => b != c)
    ..addConstraint(['a', 'c'], (dynamic a, dynamic c) => a != c)
    ..addConstraint(['a', 'b'],
        (dynamic a, dynamic b) => (a as num) < (b as num)); // redundant

  final mus = await p.findMinimalUnsatisfiableSubset();
  print('   MUS:');
  for (final ref in mus!) {
    print('     $ref');
  }
  print('');
}

/// With labels, the MUS surfaces the user-level rule names directly.
Future<void> labeledTriangle() async {
  print('2. Same triangle with labels — readable MUS output');
  final p = Problem()
    ..addVariables(['a', 'b', 'c'], [1, 2])
    ..addConstraint(['a', 'b'], (dynamic a, dynamic b) => a != b,
        label: 'edge:a-b')
    ..addConstraint(['b', 'c'], (dynamic b, dynamic c) => b != c,
        label: 'edge:b-c')
    ..addConstraint(['a', 'c'], (dynamic a, dynamic c) => a != c,
        label: 'edge:a-c')
    ..addConstraint(
        ['a', 'b'], (dynamic a, dynamic b) => (a as num) < (b as num),
        label: 'ordering:a-before-b'); // redundant for unsat

  final mus = await p.findMinimalUnsatisfiableSubset();
  print('   MUS:');
  for (final ref in mus!) {
    print('     $ref');
  }
  print('');
}

/// Both MUS algorithms agree on this problem (the triangle has
/// exactly one minimal UNSAT subset). On problems with multiple
/// locally-minimal MUSes they may surface different ones — both are
/// sound; finding the smallest is NP-hard and not the contract.
Future<void> algorithmComparison() async {
  print('3. Deletion vs QuickXplain — identical MUS on this instance');
  Problem build() => Problem()
    ..addVariables(['a', 'b', 'c'], [1, 2])
    ..addAllDifferent(['a', 'b', 'c'], label: 'pigeons:3-in-2');

  final del = await build().findMinimalUnsatisfiableSubset();
  final qx = await build().findMinimalUnsatisfiableSubsetQuickXplain();
  print('   deletion:    ${_format(del)}');
  print('   QuickXplain: ${_format(qx)}');
  print('');
}

/// When a decomposed helper like `addInverse` posts n² binaries
/// internally, labeling lets users see the entire cluster as one
/// logical unit rather than as a cloud of opaque `b{i}` refs.
Future<void> decomposedHelperCluster() async {
  print('4. Decomposed helper (addInverse) — label propagates to all pieces');
  final p = Problem()
    ..addVariables(['f0', 'f1', 'f2', 'i0', 'i1', 'i2'], [0, 1, 2])
    ..addInverse(['f0', 'f1', 'f2'], ['i0', 'i1', 'i2'], label: 'task-channel')
    // Force every f to the same value, contradicting the channel's
    // permutation property.
    ..addAllDifferent(['f0', 'f1', 'f2'], label: 'must-differ')
    ..addConstraint(['f0', 'f1'], (dynamic a, dynamic b) => a == b,
        label: 'force-collision');

  final mus = await p.findMinimalUnsatisfiableSubset();
  print('   MUS contains ${mus!.length} refs;');
  print('   labels in the MUS:');
  final labels = mus.map((r) => r.label ?? '<unlabeled>').toSet();
  for (final l in labels) {
    print('     $l');
  }
  print('');
}

/// Realistic-shape rostering: two staff, a hard "captain required"
/// rule, a hard "no double-booking" rule, and a contradiction the
/// user added by mistake. MUS surfaces the offending rules by
/// their human-readable labels.
Future<void> schedulingScenario() async {
  print('5. Rostering scenario — MUS as a debugging aid');
  final p = Problem()
    ..addSetVariable('Team',
        universe: ['alice', 'bob', 'carol', 'dave', 'erin'])
    ..addSetVariable('Bench',
        universe: ['alice', 'bob', 'carol', 'dave', 'erin'])
    ..addSetCardinality('Team', 3, label: 'team-size-3')
    ..addSetCardinality('Bench', 2, label: 'bench-size-2')
    ..addSetDisjoint('Team', 'Bench', label: 'no-double-booking')
    ..addRequiredInSet('Team', 'alice', label: 'alice-is-captain')
    // Mistake: also added a rule excluding Alice from Team.
    ..addExcludedFromSet('Team', 'alice', label: 'alice-on-leave');

  final mus = await p.findMinimalUnsatisfiableSubsetQuickXplain();
  print('   MUS labels (deduplicated):');
  final labels = mus!.map((r) => r.label ?? '<unlabeled>').toSet();
  for (final l in labels) {
    print('     $l');
  }
  print('   ↑ surfaces the two conflicting rules directly.');
  print('');
}

String _format(List<ConstraintRef>? mus) {
  if (mus == null) return '(satisfiable — no MUS)';
  return mus.map((r) => r.toString()).join(', ');
}
