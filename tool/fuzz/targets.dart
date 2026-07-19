/// Shared fuzz target definitions for dart_csp's reader surfaces.
///
/// Every target here consumes untrusted text. The contract each one is held
/// to: parsing arbitrary input may *reject*, but must never crash with an
/// unexpected exception type, and must never hang. `isClean` is the
/// allow-list of legitimate rejections — anything else is an escape.
///
/// Used by both `fuzz_blind.dart` (fast, no setup) and the `covfuzz_*.dart`
/// coverage-guided harnesses.
library;

import 'package:dart_csp/dart_csp.dart';

/// One fuzzable entry point plus the contract it must uphold.
class FuzzTarget {
  const FuzzTarget({
    required this.name,
    required this.targetLib,
    required this.seeds,
    required this.entry,
    required this.isClean,
    this.stressors = const [],
  });

  final String name;

  /// Library URI for coverage scoping — `covFuzz`'s `targetLib`.
  final String targetLib;

  final List<String> seeds;
  final void Function(String input) entry;

  /// The allow-list: exceptions that represent a legitimate rejection.
  final bool Function(Object e) isClean;

  /// Structural cases random mutation rarely reaches on its own.
  final List<String> stressors;
}

// --- FlatZinc ---------------------------------------------------------------

// Named separately because they wrap across lines: an implicitly concatenated
// literal inside a list is indistinguishable from a missing comma at a glance.
const _seedLinLe = 'var 1..5: x;\nvar 1..5: y;\n'
    'constraint int_lin_le([1, -1], [x, y], 0);\nsolve satisfy;\n';
const _seedSearchAnn =
    'var 1..5: x;\nsolve :: int_search([x], first_fail, indomain_min, '
    'complete) satisfy;\n';

const _flatzincSeeds = <String>[
  'var int: x;\nsolve satisfy;\n',
  'var 1..10: x;\nsolve satisfy;\n',
  'var bool: b;\nsolve satisfy;\n',
  'var {1, 3, 5}: x;\nsolve satisfy;\n',
  'var int: x = 5;\nsolve satisfy;\n',
  'var 1..3: x :: output_var;\nsolve satisfy;\n',
  'var -2..2: x;\nsolve satisfy;\n',
  'var set of 1..3: s;\nsolve satisfy;\n',
  'array [1..2] of var 1..5: xs;\nsolve satisfy;\n',
  _seedLinLe,
  _seedSearchAnn,
  'var 1..5: x;\nsolve minimize x;\n',
];

/// Structural edge cases: deep nesting, huge repeats, extreme numeric literals.
/// These are exactly the shapes that produced the recursion-cap, oversized-
/// domain and non-numeric-operand fixes, so they stay as permanent regression
/// pressure.
///
/// Sizing matters for the SLOW heuristic, which flags any single parse over
/// 200ms. Inputs are kept in the low tens of KB — big enough to exercise the
/// caps (nesting still exceeds the parser's 2000-frame limit, declared
/// domains still exceed the lowering limit), small enough that linear
/// handling stays well under 200ms. A breach then means genuinely superlinear
/// behaviour rather than "the input was enormous".
final _flatzincStressors = <String>[
  'solve :: seq_search([${'f(' * 3000}x${')' * 3000}]) satisfy;\n',
  'var ${'9' * 400}..${'9' * 400}: x;\nsolve satisfy;\n',
  'array [1..${'9' * 18}] of var 1..5: xs;\nsolve satisfy;\n',
  'var -${'9' * 400}..0: x;\nsolve satisfy;\n',
  'var 1..${'9' * 18}: x;\nsolve satisfy;\n',
  'var set of 1..${'9' * 18}: s;\nsolve satisfy;\n',
  '${'var 1..5: x;\n' * 2000}solve satisfy;\n',
  'var {${List.filled(5000, '1').join(',')}}: x;\nsolve satisfy;\n',
  _stressDeepConstraint,
];

final _stressDeepConstraint = 'var 1..5: x;\n'
    'constraint ${'int_plus(' * 3000}x${')' * 3000};\n'
    'solve satisfy;\n';

/// `parseFlatZinc` documents exactly one rejection type.
bool _flatzincClean(Object e) => e is FormatException;

final flatzincParse = FuzzTarget(
  name: 'flatzinc-parse',
  targetLib: 'package:dart_csp/src/flatzinc/parser.dart',
  seeds: _flatzincSeeds,
  stressors: _flatzincStressors,
  entry: parseFlatZinc,
  isClean: _flatzincClean,
);

/// The full frontend: parse *then* lower. Reaches the semantic checks that a
/// parse-only target never touches, since lowering only runs on input the
/// parser already accepted.
final flatzincLower = FuzzTarget(
  name: 'flatzinc-lower',
  targetLib: 'package:dart_csp/src/flatzinc/lowering.dart',
  seeds: _flatzincSeeds,
  stressors: _flatzincStressors,
  entry: (s) => lower(parseFlatZinc(s)),
  // A model can parse cleanly and still be semantically unsupported
  // (UnimplementedError) or internally inconsistent (StateError). Lowering
  // also reports malformed constraints — wrong arity, wrong argument type,
  // undeclared names — as ArgumentError, which `bin/dart_csp_fzn.dart`
  // deliberately maps to exit 65 alongside FormatException. That makes it a
  // designed rejection channel, not a leak, so it belongs in the allow-list.
  // RangeError and StackOverflowError are NOT listed: those would be real
  // defects.
  isClean: (e) =>
      e is FormatException ||
      e is UnimplementedError ||
      e is StateError ||
      e is ArgumentError,
);

// --- String constraint parser -----------------------------------------------

/// Fixed domains so the fuzzer varies the *constraint text*, not the
/// environment. Includes a non-numeric domain so type-confusion paths in the
/// evaluator are reachable.
final constraintDomains = <String, List<dynamic>>{
  'A': [1, 2, 3, 4, 5],
  'B': [1, 2, 3, 4, 5],
  'C': [1, 2, 3, 4, 5],
  'Z': ['red', 'green', 'blue'],
};

const _constraintSeeds = <String>[
  'A == B',
  'A > B',
  'A >= B',
  'A != B',
  'A + B == C',
  'A * 2 > B',
  'A + Z == 5',
  'A + B * C == 10',
  'A - B <= 3',
  'A in {1, 2, 3}',
  'A < B < C',
  '1 <= A <= 5',
  'A == 3',
];

/// Sized per the note on [_flatzincStressors].
final _constraintStressors = <String>[
  '${'(' * 3000}A${')' * 3000} == B',
  'A ${'+ B ' * 3000}== C',
  'A == ${'9' * 3000}',
  '${'A + ' * 3000}A == B',
  'A > ${'-' * 3000}1',
];

final constraintParse = FuzzTarget(
  name: 'constraint-parse',
  targetLib: 'package:dart_csp/src/constraint_parser.dart',
  seeds: _constraintSeeds,
  stressors: _constraintStressors,
  entry: (s) => ConstraintParser.parseConstraint(s, constraintDomains),
  // ConstraintParseException is the documented rejection; ArgumentError is
  // what the evaluator raises for operands it can't coerce.
  isClean: (e) => e is ConstraintParseException || e is ArgumentError,
);

// --- Expression evaluator ---------------------------------------------------

/// Bindings mixing numeric and non-numeric values, so the fuzzer can drive
/// the coercion paths that `_asNum` guards.
final _evalVars = <String, dynamic>{
  'A': 3,
  'B': 7,
  'C': -2,
  'Z': 'text',
};

const _evalSeeds = <String>[
  '1 + 2',
  '-5 + 3',
  'A + B',
  'A * B - C',
  '2 * (A + 1)',
  'A / B',
  'A % B',
  '((1))',
  '0',
];

/// Sized per the note on [_flatzincStressors]. The parenthesized case is the
/// one that caught the quadratic tokenizer, so it stays first.
final _evalStressors = <String>[
  '${'(' * 3000}1${')' * 3000}',
  '${'1 + ' * 3000}1',
  '${'-' * 3000}1',
  '9' * 3000,
  '1 / 0',
  '${'2 * ' * 3000}2',
];

final evalNumeric = FuzzTarget(
  name: 'eval-numeric',
  targetLib: 'package:dart_csp/src/constraint_parser.dart',
  seeds: _evalSeeds,
  stressors: _evalStressors,
  entry: (s) => ExpressionEvaluator.evaluateNumeric(s, _evalVars),
  isClean: (e) => e is ArgumentError || e is FormatException,
);

final evalBoolean = FuzzTarget(
  name: 'eval-boolean',
  targetLib: 'package:dart_csp/src/constraint_parser.dart',
  seeds: const [
    'A > B',
    'A == 3',
    '1 < 2',
    'A + 1 >= B',
    'Z == text',
    'A != B',
  ],
  stressors: _evalStressors.map((s) => '$s > 0').toList(),
  entry: (s) => ExpressionEvaluator.evaluateBoolean(s, _evalVars),
  isClean: (e) => e is ArgumentError || e is FormatException,
);

/// Every target, in the order the blind runner sweeps them.
final allTargets = <FuzzTarget>[
  flatzincParse,
  flatzincLower,
  constraintParse,
  evalNumeric,
  evalBoolean,
];
