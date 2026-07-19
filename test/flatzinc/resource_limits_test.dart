import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

/// Regression tests for resource-exhaustion guards found by `tool/fuzz`.
///
/// Each case is a small input that previously caused unbounded work: the
/// FlatZinc frontend materializes domains as explicit element lists, so a
/// declared width is also an allocation size. All of these must now be
/// rejected in bounded time rather than hanging.
void main() {
  group('FlatZinc resource limits', () {
    // A declared bound near the 64-bit limit. Small input, enormous ask.
    const huge = '999999999999999999';

    test('oversized array length is rejected, not materialized', () {
      expect(
        () => lower(parseFlatZinc(
            'array [1..$huge] of var 1..5: xs;\nsolve satisfy;\n')),
        throwsA(isA<FormatException>()),
      );
    });

    test('oversized scalar domain is rejected, not materialized', () {
      expect(
        () => lower(parseFlatZinc('var 1..$huge: x;\nsolve satisfy;\n')),
        throwsA(isA<FormatException>()),
      );
    });

    test('oversized set universe is rejected at parse time', () {
      // This one is caught in the parser, which expands `set of L..U` eagerly.
      expect(
        () => parseFlatZinc('var set of 1..$huge: s;\nsolve satisfy;\n'),
        throwsA(isA<FormatException>()),
      );
    });

    test('domain width near the 64-bit limit does not overflow', () {
      // `max - min` wraps to a negative int here; the guard computes the
      // width in BigInt so the range is still recognized as too wide.
      expect(
        () => lower(
            parseFlatZinc('var -9223372036854775808..9223372036854775807: x;\n'
                'solve satisfy;\n')),
        throwsA(isA<FormatException>()),
      );
    });

    test('domains at a workable size still lower', () {
      final m = lower(parseFlatZinc('var 1..1000: x;\nsolve satisfy;\n'));
      expect(m.problem.variables['x'], hasLength(1000));
    });

    test('arrays at a workable size still lower', () {
      final m = lower(
          parseFlatZinc('array [1..50] of var 1..5: xs;\nsolve satisfy;\n'));
      expect(m.problem.variables['xs[50]'], hasLength(5));
    });

    test('redeclaration is a FormatException naming the line', () {
      expect(
        () => lower(
            parseFlatZinc('var 1..5: x;\nvar 1..5: x;\nsolve satisfy;\n')),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            allOf(contains("'x'"), contains('line 2')),
          ),
        ),
      );
    });

    test('an array may not reuse a scalar name', () {
      expect(
        () => lower(parseFlatZinc(
            'var 1..5: x;\narray [1..2] of var 1..5: x;\nsolve satisfy;\n')),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('expression evaluator scales linearly', () {
    // Tokens were accumulated with `+=` per character, which is quadratic in
    // token length. An expression with no top-level operator is a single
    // token, so this input is the worst case.
    //
    // Sizing is a deliberate tradeoff. `dart test` runs files in parallel and
    // this suite has neighbours that assert on wall-clock duration, so a test
    // that burns CPU makes *them* flaky. n is picked to separate the two
    // regimes sharply while still costing well under a second. Measured: this
    // input takes 2m01s against the pre-fix tokenizer and ~75ms against the
    // current one. The 4s bound sits ~30x above the linear time and ~30x
    // below the quadratic one, so it neither flakes under load nor passes if
    // the quadratic path returns.
    test('a deeply parenthesized expression finishes promptly', () {
      const n = 150000;
      final expr = '${'(' * n}1${')' * n}';
      final sw = Stopwatch()..start();
      try {
        ExpressionEvaluator.evaluateNumeric(expr, const {});
        // Rejecting is fine — the point is that it returns at all, so both
        // the reject types are swallowed here.
        // ignore: avoid_catching_errors
      } on ArgumentError {
        // ignore: avoid_catching_errors
      } on FormatException {
        // Intentionally empty.
      }
      expect(sw.elapsed, lessThan(const Duration(seconds: 4)));
    });

    // The many-token case, which was already linear. Kept as a guard that the
    // slicing rewrite did not regress the ordinary path, so it stays small.
    test('a long operator chain finishes promptly', () {
      final expr = '${'1 + ' * 50000}1';
      final sw = Stopwatch()..start();
      expect(ExpressionEvaluator.evaluateNumeric(expr, const {}), 50001);
      expect(sw.elapsed, lessThan(const Duration(seconds: 4)));
    });

    test('tokenization is unchanged by the slicing rewrite', () {
      const vars = <String, dynamic>{'A': 3, 'B': 7};
      expect(ExpressionEvaluator.evaluateNumeric('1 + 2', vars), 3);
      expect(ExpressionEvaluator.evaluateNumeric('-5 + 3', vars), -2);
      expect(ExpressionEvaluator.evaluateNumeric('A + B', vars), 10);
      expect(ExpressionEvaluator.evaluateNumeric('A * B', vars), 21);
      expect(ExpressionEvaluator.evaluateNumeric('B - A', vars), 4);
      expect(ExpressionEvaluator.evaluateNumeric('2 * 3 + 4', vars), 10);
      expect(ExpressionEvaluator.evaluateNumeric('A * -2', vars), -6);
      expect(ExpressionEvaluator.evaluateNumeric('10 / 2', vars), 5);
    });
  });
}
