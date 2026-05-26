import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

void main() {
  group('FlatZinc parser — variable declarations', () {
    test('var int: x; — unbounded int', () {
      final model = parseFlatZinc('var int: x;\nsolve satisfy;\n');
      expect(model.vars, hasLength(1));
      expect(model.vars.first.name, 'x');
      expect(model.vars.first.type, isA<VarTypeInt>());
      expect(model.vars.first.rhs, isNull);
      expect(model.vars.first.isOutput, isFalse);
      expect(model.solve.kind, 'satisfy');
    });

    test('var L..U: x; — integer range', () {
      final model = parseFlatZinc('var 1..10: x;\nsolve satisfy;\n');
      final type = model.vars.first.type;
      expect(type, isA<VarTypeRange>());
      expect((type as VarTypeRange).min, 1);
      expect(type.max, 10);
    });

    test('var bool: b; — boolean', () {
      final model = parseFlatZinc('var bool: b;\nsolve satisfy;\n');
      expect(model.vars.first.type, isA<VarTypeBool>());
    });

    test('var {1, 3, 5}: x; — enumerated domain', () {
      final model = parseFlatZinc('var {1, 3, 5}: x;\nsolve satisfy;\n');
      final type = model.vars.first.type;
      expect(type, isA<VarTypeSet>());
      expect((type as VarTypeSet).values, [1, 3, 5]);
    });

    test('var int: x = 5; — singleton alias', () {
      final model = parseFlatZinc('var int: x = 5;\nsolve satisfy;\n');
      expect(model.vars.first.rhs, isA<AstIntLit>());
      expect((model.vars.first.rhs! as AstIntLit).value, 5);
    });

    test('annotations: var int: x :: output_var;', () {
      final model =
          parseFlatZinc('var 1..3: x :: output_var;\nsolve satisfy;\n');
      expect(model.vars.first.isOutput, isTrue);
    });

    test('range with negative bounds', () {
      final model = parseFlatZinc('var -2..2: x;\nsolve satisfy;\n');
      final type = model.vars.first.type as VarTypeRange;
      expect(type.min, -2);
      expect(type.max, 2);
    });

    test('rejects set-of-int variables (out of v1 scope)', () {
      expect(
        () => parseFlatZinc('var set of int: s;\nsolve satisfy;\n'),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects empty enumerated domain', () {
      expect(
        () => parseFlatZinc('var {}: x;\nsolve satisfy;\n'),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects inverted ranges', () {
      expect(
        () => parseFlatZinc('var 5..1: x;\nsolve satisfy;\n'),
        throwsA(isA<FormatException>()),
      );
    });

    test('reports useful error messages with line/column', () {
      try {
        parseFlatZinc('var int x;\nsolve satisfy;\n');
        fail('Expected a FormatException');
      } on FormatException catch (e) {
        // Missing `:` between type and name.
        expect(e.toString(), contains('line 1'));
        expect(e.toString(), contains("':'"));
      }
    });
  });

  group('FlatZinc parser — array declarations', () {
    test('array[1..3] of var int: a;', () {
      final model =
          parseFlatZinc('array[1..3] of var int: a;\nsolve satisfy;\n');
      expect(model.arrays, hasLength(1));
      expect(model.arrays.first.name, 'a');
      expect(model.arrays.first.length, 3);
      expect(model.arrays.first.elementType, isA<VarTypeInt>());
      expect(model.arrays.first.elements, isNull);
    });

    test('array[1..2] of var 0..9: a = [3, x]; — aliased', () {
      final model = parseFlatZinc(
        'var 0..9: x;\n'
        'array[1..2] of var 0..9: a = [3, x];\n'
        'solve satisfy;\n',
      );
      final arr = model.arrays.first;
      expect(arr.elements, isNotNull);
      expect(arr.elements!.length, 2);
      expect((arr.elements![0] as AstIntLit).value, 3);
      expect((arr.elements![1] as AstIdent).name, 'x');
    });

    test('output_array annotation captured', () {
      final model = parseFlatZinc(
        'array[1..3] of var 1..9: a :: output_array([1..3]);\n'
        'solve satisfy;\n',
      );
      final arr = model.arrays.first;
      expect(arr.isOutput, isTrue);
      final dims = arr.outputArrayDims!;
      expect(dims, hasLength(1));
      expect(dims.first.min, 1);
      expect(dims.first.max, 3);
    });

    test('parameter array: array[1..3] of int: a = [1, 2, 3];', () {
      final model = parseFlatZinc(
        'array[1..3] of int: a = [1, 2, 3];\nsolve satisfy;\n',
      );
      expect(model.arrays, isEmpty);
      expect(model.params, hasLength(1));
      expect(model.params.first.name, 'a');
      expect(model.params.first.kind, 'array_int');
    });

    test('rejects non-1 array lower bound', () {
      expect(
        () => parseFlatZinc(
          'array[0..2] of var int: a;\nsolve satisfy;\n',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects array literal of wrong length', () {
      expect(
        () => parseFlatZinc(
          'array[1..3] of var int: a = [1, 2];\nsolve satisfy;\n',
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('FlatZinc parser — parameters', () {
    test('int: n = 5;', () {
      final model = parseFlatZinc('int: n = 5;\nsolve satisfy;\n');
      expect(model.params, hasLength(1));
      expect(model.params.first.name, 'n');
      expect(model.params.first.kind, 'int');
      expect((model.params.first.value as AstIntLit).value, 5);
    });

    test('bool: flag = true;', () {
      final model = parseFlatZinc('bool: flag = true;\nsolve satisfy;\n');
      expect(model.params.first.kind, 'bool');
      expect((model.params.first.value as AstBoolLit).value, isTrue);
    });
  });

  group('FlatZinc parser — solve item', () {
    test('solve satisfy;', () {
      final model = parseFlatZinc('var 1..2: x;\nsolve satisfy;\n');
      expect(model.solve.kind, 'satisfy');
      expect(model.solve.objective, isNull);
    });

    test('solve minimize x;', () {
      final model = parseFlatZinc('var 0..9: x;\nsolve minimize x;\n');
      expect(model.solve.kind, 'minimize');
      expect((model.solve.objective! as AstIdent).name, 'x');
    });

    test('solve maximize x;', () {
      final model = parseFlatZinc('var 0..9: x;\nsolve maximize x;\n');
      expect(model.solve.kind, 'maximize');
    });

    test('search annotations are parsed but kept on the SolveItem', () {
      final model = parseFlatZinc(
        'var 0..9: x;\n'
        'solve :: int_search([x], input_order, indomain_min, complete) '
        'satisfy;\n',
      );
      expect(model.solve.kind, 'satisfy');
      expect(model.solve.annotations, hasLength(1));
      expect(model.solve.annotations.first.name, 'int_search');
    });

    test('missing solve item is reported', () {
      expect(
        () => parseFlatZinc('var 1..2: x;\n'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('FlatZinc parser — comments and whitespace', () {
    test('skips % line comments', () {
      final model = parseFlatZinc(
        '% leading comment\n'
        'var 1..3: x; % trailing comment\n'
        'solve satisfy;\n',
      );
      expect(model.vars.first.name, 'x');
    });
  });

  group('FlatZinc parser — constraint items', () {
    test('parses constraint syntax even if lowering refuses', () {
      final model = parseFlatZinc(
        'var 1..3: x;\n'
        'var 1..3: y;\n'
        'constraint int_eq(x, y);\n'
        'solve satisfy;\n',
      );
      expect(model.constraints, hasLength(1));
      expect(model.constraints.first.name, 'int_eq');
      expect(model.constraints.first.args, hasLength(2));
    });
  });
}
