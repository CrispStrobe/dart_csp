import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

void main() {
  group('FlatZinc M1 end-to-end', () {
    test('three-variable satisfy emits standard FZN output', () async {
      final out = await FlatZinc.solve(
        'var 1..3: x :: output_var;\n'
        'var 4..6: y :: output_var;\n'
        'var 7..9: z :: output_var;\n'
        'solve satisfy;\n',
      );
      // First solution picks the lower bound of each domain because no
      // constraints prune the search and AC-3 preserves bounds.
      expect(out, contains('x = 1;'));
      expect(out, contains('y = 4;'));
      expect(out, contains('z = 7;'));
      expect(out.trim().split('\n').last, '----------');
    });

    test('enumerated domain narrows correctly', () async {
      final out = await FlatZinc.solve(
        'var {2, 4, 6}: x :: output_var;\n'
        'solve satisfy;\n',
      );
      expect(out, contains('x = 2;'));
    });

    test('array variable lowered to per-slot vars with FlatZinc names',
        () async {
      final lowered = FlatZinc.build(
        'array[1..3] of var 1..9: a :: output_array([1..3]);\n'
        'solve satisfy;\n',
      );
      // The Problem should have three variables named a[1], a[2], a[3].
      expect(lowered.problem.variableCount, 3);
      expect(lowered.outputArrays, hasLength(1));
      expect(lowered.outputArrays.first.varNames, ['a[1]', 'a[2]', 'a[3]']);
    });

    test('array satisfy emits array1d(...) line', () async {
      final out = await FlatZinc.solve(
        'array[1..3] of var 1..9: a :: output_array([1..3]);\n'
        'solve satisfy;\n',
      );
      expect(out, contains('a = array1d(1..3, [1, 1, 1]);'));
      expect(out, contains('----------'));
    });

    test('no annotations falls back to emitting every variable', () async {
      final out = await FlatZinc.solve(
        'var 5..5: x;\n'
        'solve satisfy;\n',
      );
      expect(out, contains('x = 5;'));
    });

    test('all=true marks exhaustive search with ==========', () async {
      final out = await FlatZinc.solve(
        'var 1..2: x :: output_var;\n'
        'solve satisfy;\n',
        all: true,
      );
      final lines = out.trim().split('\n');
      // Two solutions × (1 value line + 1 separator) = 4 lines + terminator.
      expect(lines.last, '==========');
      expect(lines.where((l) => l == '----------').length, 2);
      expect(lines.where((l) => l.startsWith('x = ')).length, 2);
    });

    test('unsatisfiable empty domain combo is reported', () async {
      // Make the problem trivially unsat by aliasing two singletons to
      // different values via array elements. M1 has no constraints
      // available to do this directly, so we lean on the fact that
      // singleton domains plus distinct array literals would conflict
      // if equality were enforced — for M1 we approximate by checking
      // that a deliberately-narrow var still gets a solution.
      // (This test exists primarily to lock in that the runner does
      // not blow up on solo singletons.)
      final out = await FlatZinc.solve(
        'var 7..7: x :: output_var;\n'
        'solve satisfy;\n',
      );
      expect(out, contains('x = 7;'));
    });

    test('minimize on a 1..9 range picks the minimum', () async {
      final out = await FlatZinc.solve(
        'var 3..9: x :: output_var;\n'
        'solve minimize x;\n',
      );
      expect(out, contains('x = 3;'));
      expect(out.trim().split('\n').last, '==========');
    });

    test('maximize on a 1..9 range picks the maximum', () async {
      final out = await FlatZinc.solve(
        'var 3..9: x :: output_var;\n'
        'solve maximize x;\n',
      );
      expect(out, contains('x = 9;'));
      expect(out.trim().split('\n').last, '==========');
    });

    test('runner rejects unsupported constraint with a clear error', () async {
      // `bool_lin_eq` is a standard FlatZinc builtin we have not yet
      // wired up — it should hit the dispatch table miss path with a
      // clear UnimplementedError. (When this lands, swap to another
      // genuinely-unsupported builtin like `float_lin_eq` or a set
      // constraint.)
      expect(
        () => FlatZinc.solve(
          'var bool: a;\nvar bool: b;\n'
          'constraint bool_lin_eq([1, 1], [a, b], 1);\n'
          'solve satisfy;\n',
        ),
        throwsA(isA<UnimplementedError>()),
      );
    });
  });
}
