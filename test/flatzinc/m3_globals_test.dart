import 'package:dart_csp/dart_csp.dart';
import 'package:test/test.dart';

({Map<String, int> values, Map<String, List<int>> arrays}) parse(String out) {
  final values = <String, int>{};
  final arrays = <String, List<int>>{};
  for (final raw in out.trim().split('\n')) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('---') || line.startsWith('===')) {
      continue;
    }
    final eq = line.indexOf('=');
    if (eq < 0) continue;
    final name = line.substring(0, eq).trim();
    final rhs = line.substring(eq + 1, line.length - 1).trim();
    if (rhs.startsWith('array1d')) {
      final start = rhs.indexOf('[');
      final end = rhs.lastIndexOf(']');
      final inner = rhs.substring(start + 1, end);
      arrays[name] =
          inner.split(',').map((s) => _parseBoolOrInt(s.trim())).toList();
    } else if (rhs == 'true') {
      values[name] = 1;
    } else if (rhs == 'false') {
      values[name] = 0;
    } else {
      final v = int.tryParse(rhs);
      if (v != null) values[name] = v;
    }
  }
  return (values: values, arrays: arrays);
}

int _parseBoolOrInt(String s) {
  if (s == 'true') return 1;
  if (s == 'false') return 0;
  return int.parse(s);
}

void main() {
  group('FlatZinc M3 — all_different_int', () {
    test('4-queens with all_different_int on rows', () async {
      // The diagonal constraints would normally come from int_lin_ne;
      // here we just check the row-distinct constraint to keep the
      // model small.
      final out = await FlatZinc.solve(
        'array[1..4] of var 1..4: row :: output_array([1..4]);\n'
        'constraint all_different_int(row);\n'
        'solve satisfy;\n',
      );
      final r = parse(out).arrays['row']!;
      expect(r.toSet().length, 4);
    });

    test('all_different_int on inline literal array', () async {
      final out = await FlatZinc.solve(
        'var 1..3: a :: output_var;\n'
        'var 1..3: b :: output_var;\n'
        'var 1..3: c :: output_var;\n'
        'constraint all_different_int([a, b, c]);\n'
        'solve satisfy;\n',
      );
      final v = parse(out).values;
      expect({v['a'], v['b'], v['c']}.length, 3);
    });
  });

  group('FlatZinc M3 — array_int_element', () {
    test('idx variable selects the right slot (1-based)', () async {
      // arr = [10, 20, 30]; idx = 2 → val = 20.
      final out = await FlatZinc.solve(
        'array[1..3] of int: arr = [10, 20, 30];\n'
        'var 1..3: idx :: output_var;\n'
        'var 0..100: val :: output_var;\n'
        'constraint int_eq(idx, 2);\n'
        'constraint array_int_element(idx, arr, val);\n'
        'solve satisfy;\n',
      );
      expect(parse(out).values['val'], 20);
    });

    test('val variable is uniquely determined', () async {
      final out = await FlatZinc.solve(
        'var 1..3: idx :: output_var;\n'
        'var 0..100: val :: output_var;\n'
        'constraint int_eq(idx, 3);\n'
        'constraint array_int_element(idx, [5, 7, 11], val);\n'
        'solve satisfy;\n',
      );
      expect(parse(out).values['val'], 11);
    });
  });

  group('FlatZinc M3 — circuit / subcircuit', () {
    test('3-circuit produces a permutation forming one cycle', () async {
      // 3 nodes, all-different successor list. The unique sol is
      // either (2,3,1) or (3,1,2); the search returns the first.
      final out = await FlatZinc.solve(
        'array[1..3] of var 1..3: nxt :: output_array([1..3]);\n'
        'constraint circuit(nxt);\n'
        'solve satisfy;\n',
      );
      final arr = parse(out).arrays['nxt']!;
      // Walk the cycle starting at 1 and assert all nodes visited.
      final visited = <int>{};
      var cur = 1;
      for (var k = 0; k < 3; k++) {
        if (!visited.add(cur)) {
          fail('cycle revisited node before completing tour');
        }
        cur = arr[cur - 1];
      }
      expect(cur, 1);
      expect(visited, {1, 2, 3});
    });

    test('subcircuit allows self-loops as "not in cycle"', () async {
      // 3 nodes, the only constraint says subcircuit. Search returns
      // a valid subcircuit; minimum is all-self-loops.
      final out = await FlatZinc.solve(
        'array[1..3] of var 1..3: nxt :: output_array([1..3]);\n'
        'constraint subcircuit(nxt);\n'
        'solve satisfy;\n',
      );
      expect(parse(out).arrays['nxt'], isNotNull);
    });
  });

  group('FlatZinc M3 — inverse', () {
    test('forward + inverse permutations are consistent', () async {
      // Forced: f = [2, 3, 1] → invf should be [3, 1, 2].
      final out = await FlatZinc.solve(
        'array[1..3] of var 1..3: f :: output_array([1..3]);\n'
        'array[1..3] of var 1..3: invf :: output_array([1..3]);\n'
        'constraint int_eq(f[1], 2);\n'
        'constraint int_eq(f[2], 3);\n'
        'constraint int_eq(f[3], 1);\n'
        'constraint inverse(f, invf);\n'
        'solve satisfy;\n',
      );
      final a = parse(out).arrays;
      expect(a['f'], [2, 3, 1]);
      expect(a['invf'], [3, 1, 2]);
    });
  });

  group('FlatZinc M3 — count / nvalue', () {
    test('count_eq with constant target and constant count', () async {
      // |{i : x[i] == 2}| == 2 in an array of length 4 over 1..3.
      final out = await FlatZinc.solve(
        'array[1..4] of var 1..3: x :: output_array([1..4]);\n'
        'constraint count_eq(x, 2, 2);\n'
        'solve satisfy;\n',
      );
      final arr = parse(out).arrays['x']!;
      expect(arr.where((v) => v == 2).length, 2);
    });

    test('nvalue with constant n', () async {
      // Exactly 2 distinct values across the array.
      final out = await FlatZinc.solve(
        'array[1..4] of var 1..3: x :: output_array([1..4]);\n'
        'constraint nvalue(2, x);\n'
        'solve satisfy;\n',
      );
      final arr = parse(out).arrays['x']!;
      expect(arr.toSet().length, 2);
    });
  });

  group('FlatZinc M3 — global_cardinality', () {
    test('fixed counts: exact occurrence requirements', () async {
      // x over 1..3 of length 4: value 1 appears 2x, value 2 appears 1x,
      // value 3 appears 1x.
      final out = await FlatZinc.solve(
        'array[1..4] of var 1..3: x :: output_array([1..4]);\n'
        'constraint global_cardinality(x, [1, 2, 3], [2, 1, 1]);\n'
        'solve satisfy;\n',
      );
      final arr = parse(out).arrays['x']!;
      expect(arr.where((v) => v == 1).length, 2);
      expect(arr.where((v) => v == 2).length, 1);
      expect(arr.where((v) => v == 3).length, 1);
    });
  });

  group('FlatZinc M3 — bin_packing_load', () {
    test('1-based bin assignments yield correct loads', () async {
      // 3 items, sizes [2, 3, 5], 2 bins. Force items 1,2 to bin 1
      // and item 3 to bin 2 → loads = [5, 5].
      final out = await FlatZinc.solve(
        'array[1..2] of var 0..10: load :: output_array([1..2]);\n'
        'array[1..3] of var 1..2: bin :: output_array([1..3]);\n'
        'constraint int_eq(bin[1], 1);\n'
        'constraint int_eq(bin[2], 1);\n'
        'constraint int_eq(bin[3], 2);\n'
        'constraint bin_packing_load(load, bin, [2, 3, 5]);\n'
        'solve satisfy;\n',
      );
      expect(parse(out).arrays['load'], [5, 5]);
    });
  });

  group('FlatZinc M3 — lex_less / lex_lesseq', () {
    test('lex_lesseq breaks symmetry between two rows', () async {
      // 2-row 1..3 matrix; lex_lesseq forces row 0 <= row 1.
      final out = await FlatZinc.solve(
        'array[1..2] of var 1..3: a :: output_array([1..2]);\n'
        'array[1..2] of var 1..3: b :: output_array([1..2]);\n'
        'constraint lex_lesseq(a, b);\n'
        'solve satisfy;\n',
      );
      final av = parse(out).arrays['a']!;
      final bv = parse(out).arrays['b']!;
      // Lex compare.
      for (var i = 0; i < av.length; i++) {
        if (av[i] < bv[i]) {
          return;
        }
        if (av[i] > bv[i]) {
          fail('lex_lesseq violated: $av > $bv at index $i');
        }
      }
    });

    test('lex_less is strict', () async {
      final out = await FlatZinc.solve(
        'array[1..2] of var 1..3: a :: output_array([1..2]);\n'
        'array[1..2] of var 1..3: b :: output_array([1..2]);\n'
        'constraint lex_less(a, b);\n'
        'solve satisfy;\n',
      );
      final av = parse(out).arrays['a']!;
      final bv = parse(out).arrays['b']!;
      expect(av.toString(), isNot(bv.toString()));
    });
  });

  group('FlatZinc M3 — value_precede_chain_int', () {
    test('value 1 must appear before value 2', () async {
      final out = await FlatZinc.solve(
        'array[1..4] of var 1..2: x :: output_array([1..4]);\n'
        'constraint value_precede_chain_int([1, 2], x);\n'
        'solve satisfy;\n',
      );
      final arr = parse(out).arrays['x']!;
      final firstOne = arr.indexOf(1);
      final firstTwo = arr.indexOf(2);
      if (firstTwo >= 0) {
        expect(firstOne >= 0 && firstOne < firstTwo, isTrue,
            reason: 'first 1 at $firstOne, first 2 at $firstTwo');
      }
    });
  });

  group('FlatZinc M3 — table_int', () {
    test('only allowed tuples are reachable', () async {
      // Allowed: (1,2), (2,3), (3,1) — a cyclic table.
      final out = await FlatZinc.solve(
        'var 1..3: a :: output_var;\n'
        'var 1..3: b :: output_var;\n'
        'constraint table_int([a, b], [1, 2, 2, 3, 3, 1]);\n'
        'constraint int_eq(a, 2);\n'
        'solve satisfy;\n',
      );
      final v = parse(out).values;
      expect((v['a'], v['b']), (2, 3));
    });
  });

  group('FlatZinc M3 — disjunctive / cumulative', () {
    test('disjunctive forces task starts apart', () async {
      // Two tasks of duration 3; with starts in 0..5 the only sols
      // are pairs with |s1 - s2| >= 3. The first sol is (0, 3).
      final out = await FlatZinc.solve(
        'array[1..2] of var 0..5: s :: output_array([1..2]);\n'
        'constraint disjunctive(s, [3, 3]);\n'
        'solve satisfy;\n',
      );
      final arr = parse(out).arrays['s']!;
      expect((arr[0] - arr[1]).abs() >= 3, isTrue);
    });

    test('cumulative caps total demand at each time', () async {
      // 3 tasks of duration 2, demand 1 each, capacity 1 → no
      // overlap. Starts in 0..5 → first sol packs them at 0, 2, 4.
      final out = await FlatZinc.solve(
        'array[1..3] of var 0..5: s :: output_array([1..3]);\n'
        'constraint cumulative(s, [2, 2, 2], [1, 1, 1], 1);\n'
        'solve satisfy;\n',
      );
      final arr = parse(out).arrays['s']!;
      // No pair should overlap with duration 2 each.
      for (var i = 0; i < arr.length; i++) {
        for (var j = i + 1; j < arr.length; j++) {
          expect((arr[i] - arr[j]).abs() >= 2, isTrue,
              reason: 'overlap: ${arr[i]} vs ${arr[j]}');
        }
      }
    });
  });

  group('FlatZinc M3 — diffn', () {
    test('two 2x2 rectangles in a 3x3 grid must not overlap', () async {
      // With starts in 0..2 and widths/heights of 2, a non-overlapping
      // placement requires |Δx| ≥ 2 OR |Δy| ≥ 2. E.g. (0,0) and (2,0).
      final out = await FlatZinc.solve(
        'array[1..2] of var 0..2: xs :: output_array([1..2]);\n'
        'array[1..2] of var 0..2: ys :: output_array([1..2]);\n'
        'constraint diffn(xs, ys, [2, 2], [2, 2]);\n'
        'solve satisfy;\n',
      );
      final xs = parse(out).arrays['xs']!;
      final ys = parse(out).arrays['ys']!;
      final dx = (xs[0] - xs[1]).abs();
      final dy = (ys[0] - ys[1]).abs();
      expect(dx >= 2 || dy >= 2, isTrue);
    });
  });

  group('FlatZinc M3 — regular', () {
    test('DFA accepts only strings ending in symbol 2', () async {
      // States: 1 = start, 2 = saw 2 (accepting), 3 = saw 1
      // Transition: from 1 with 1 → 3, with 2 → 2.
      //             from 2 with 1 → 3, with 2 → 2.
      //             from 3 with 1 → 3, with 2 → 2.
      // q0 = 1, F = {2}.
      // T flat: state 1 row [3, 2], state 2 row [3, 2], state 3 row [3, 2]
      final out = await FlatZinc.solve(
        'array[1..3] of var 1..2: x :: output_array([1..3]);\n'
        'constraint regular(x, 3, 2, [3, 2, 3, 2, 3, 2], 1, {2});\n'
        'solve satisfy;\n',
      );
      final arr = parse(out).arrays['x']!;
      expect(arr.last, 2);
    });
  });
}
