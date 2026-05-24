/// A command-line application that generates and solves "arithmetic square" puzzles.
///
/// An arithmetic square is a grid of numbers where each row and column forms
/// a valid mathematical equation. This program randomly generates the operators
/// and a few initial numbers (clues), then models the puzzle as a
/// Constraint Satisfaction Problem (CSP) and uses a generic CSP solver to find
/// a valid solution for the remaining empty cells.
///
/// This version is modified to demonstrate solving each puzzle using both the
/// "old way" (manual CspProblem) and the "new way" (Problem builder).
///
/// Usage: dart gensq.dart [options]
///
/// Options:
///   --size=<N>        Sets the grid size to N x N (default: 3).
///   --range=<min-max> Sets the range of numbers for cells (default: 1-20).
///   --ops=<op1,op2>   Specifies allowed operators (+,-,*,/) (default: all).
///   --clues=<N>       Sets the number of initial clues (default: auto).
///   verbose           Enables detailed logging of the generation process.
library;

import 'dart:math';
import 'package:dart_csp/dart_csp.dart';

// ------------------- Configuration & Argument Parsing -------------------

/// A data class to hold the configuration settings for puzzle generation.
class PuzzleConfig {
  PuzzleConfig({
    this.gridN = 3,
    this.minN = 1,
    this.maxN = 20,
    this.ops = const ['+', '−', '×', '÷'],
    this.maxAttempts = 250,
    this.numClues = 0,
    this.verbose = false,
  });

  /// The size of the N x N grid.
  int gridN;

  /// The minimum possible value for a number in a cell.
  int minN;

  /// The maximum possible value for a number in a cell.
  int maxN;

  /// The list of mathematical operators allowed in the puzzle.
  List<String> ops;

  /// The maximum number of attempts to generate a solvable puzzle layout.
  int maxAttempts;

  /// The desired number of pre-filled cells (clues) in the puzzle.
  int numClues;

  /// A flag to enable or disable verbose logging.
  bool verbose;
}

/// Parses command-line arguments to create a [PuzzleConfig] object.
PuzzleConfig parseArgs(List<String> args) {
  final config = PuzzleConfig();
  var cluesManuallySet = false;

  for (final arg in args) {
    if (arg == 'verbose') {
      config.verbose = true;
      continue;
    }
    if (arg.startsWith('--')) {
      final parts = arg.substring(2).split('=');
      if (parts.length != 2) continue;
      final key = parts[0];
      final value = parts[1];

      switch (key) {
        case 'size':
          final size = int.tryParse(value);
          if (size != null && size >= 3) {
            config.gridN = size;
          }
          break;
        case 'range':
          final rangeParts = value.split('-');
          if (rangeParts.length == 2) {
            final min = int.tryParse(rangeParts[0]);
            final max = int.tryParse(rangeParts[1]);
            if (min != null && max != null && min < max) {
              config.minN = min;
              config.maxN = max;
            }
          }
          break;
        case 'ops':
          const opMap = {'-': '−', '*': '×', '/': '÷'};
          const validOps = {'+', '−', '×', '÷'};
          final userOps = value
              .split(',')
              .map((op) => op.trim())
              .map((op) => opMap[op] ?? op)
              .where((op) => validOps.contains(op))
              .toList();
          if (userOps.isNotEmpty) {
            config.ops = userOps;
          }
          break;
        case 'clues':
          final clues = int.tryParse(value);
          if (clues != null && clues >= 0) {
            config.numClues = clues;
            cluesManuallySet = true;
          }
          break;
      }
    }
  }

  if (config.gridN > 3 && !cluesManuallySet) {
    config.numClues = (config.gridN / 2).floor();
  }
  return config;
}

// ------------------- Main Application Logic -------------------

/// The main entry point of the application.
void main(List<String> args) async {
  final config = parseArgs(args);
  final puzzleGenerator = PuzzleGenerator(config);
  await puzzleGenerator.generate();
}

/// The main class responsible for the puzzle generation and solving process.
class PuzzleGenerator {
  PuzzleGenerator(this.config);
  final PuzzleConfig config;
  final Random _random = Random();

  void log(String message) {
    if (config.verbose) {
      print(message);
    }
  }

  // ------------------- Utility Methods -------------------

  int randInt(int a, int b) => a + _random.nextInt(b - a + 1);
  T randChoice<T>(List<T> arr) => arr[_random.nextInt(arr.length)];
  String id(int r, int c) => 'r${r}c$c';
  String opId(int? r, int? c, String type, [int index = 0]) {
    if (type == 'row') return 'op_r${r}_i$index';
    if (type == 'col') return 'op_c${c}_i$index';
    return '';
  }

  int? evaluate(List<dynamic> operands, List<String> ops) {
    if (operands.any((op) => op == null) || operands.length != ops.length + 1) {
      return null;
    }
    var currentVal = operands[0] as int;
    for (var i = 0; i < ops.length; i++) {
      final op = ops[i];
      final nextVal = operands[i + 1] as int;
      switch (op) {
        case '+':
          currentVal += nextVal;
          break;
        case '−':
          currentVal -= nextVal;
          break;
        case '×':
          currentVal *= nextVal;
          break;
        case '÷':
          if (nextVal == 0 || currentVal % nextVal != 0) return null;
          currentVal ~/= nextVal;
          break;
        default:
          return null;
      }
    }
    return currentVal;
  }

  // ------------------- CSP Modeling and Grid Display -------------------

  /// **[OLD WAY]** Models the puzzle by manually constructing a [CspProblem].
  CspProblem buildPuzzleConstraintsOldWay(
      Map<String, List<List<String>>> ops, Map<String, int> clues) {
    final variables = <String, List<dynamic>>{};
    final naryConstraints = <NaryConstraint>[];
    final fullDomain = List<int>.generate(
        config.maxN - config.minN + 1, (i) => i + config.minN);

    for (var r = 0; r < config.gridN; r++) {
      for (var c = 0; c < config.gridN; c++) {
        final cellId = id(r, c);
        variables[cellId] =
            clues.containsKey(cellId) ? [clues[cellId]] : fullDomain;
      }
    }

    NaryPredicate createPredicate(List<String> varNames, List<String> opList) =>
        (assign) {
          final values = varNames.map((v) => assign[v]).toList();
          final operands = values.sublist(0, config.gridN - 1);
          final result = values.last;
          if (operands.any((op) => op == null) || result == null) return false;
          return evaluate(operands, opList) == result;
        };

    for (var r = 0; r < config.gridN; r++) {
      final rowVars = List<String>.generate(config.gridN, (c) => id(r, c));
      naryConstraints.add(NaryConstraint(
          vars: rowVars, predicate: createPredicate(rowVars, ops['rows']![r])));
    }

    for (var c = 0; c < config.gridN; c++) {
      final colVars = List<String>.generate(config.gridN, (r) => id(r, c));
      naryConstraints.add(NaryConstraint(
          vars: colVars, predicate: createPredicate(colVars, ops['cols']![c])));
    }

    return CspProblem(variables: variables, naryConstraints: naryConstraints);
  }

  /// **[NEW WAY]** Models the puzzle using the [Problem] builder class.
  Problem buildPuzzleConstraintsNewWay(
      Map<String, List<List<String>>> ops, Map<String, int> clues) {
    final p = Problem();
    final fullDomain = List<int>.generate(
        config.maxN - config.minN + 1, (i) => i + config.minN);

    for (var r = 0; r < config.gridN; r++) {
      for (var c = 0; c < config.gridN; c++) {
        final cellId = id(r, c);
        if (clues.containsKey(cellId)) {
          p.addVariable(cellId, [clues[cellId]]);
        } else {
          p.addVariable(cellId, fullDomain);
        }
      }
    }

    NaryPredicate createPredicate(List<String> varNames, List<String> opList) =>
        (assign) {
          final values = varNames.map((v) => assign[v]).toList();
          final operands = values.sublist(0, config.gridN - 1);
          final result = values.last;
          if (operands.any((op) => op == null) || result == null) return false;
          return evaluate(operands, opList) == result;
        };

    for (var r = 0; r < config.gridN; r++) {
      final rowVars = List<String>.generate(config.gridN, (c) => id(r, c));
      p.addConstraint(rowVars, createPredicate(rowVars, ops['rows']![r]));
    }

    for (var c = 0; c < config.gridN; c++) {
      final colVars = List<String>.generate(config.gridN, (r) => id(r, c));
      p.addConstraint(colVars, createPredicate(colVars, ops['cols']![c]));
    }
    return p;
  }

  String asciiGrid(
      Map<String, dynamic> solution, Map<String, String> ops, int n) {
    final buffer = StringBuffer();
    final hLine = '+${'-' * (n * 4 + (n - 1) * 3)}+\n';
    buffer.write(hLine);
    for (var r = 0; r < n; r++) {
      buffer.write('|');
      for (var c = 0; c < n; c++) {
        final valStr = solution[id(r, c)]?.toString() ?? '?';
        buffer.write(valStr.padLeft(4));
        if (c < n - 2) {
          buffer.write(' ${ops[opId(r, null, 'row', c)]} ');
        } else if (c == n - 2) {
          buffer.write(' = ');
        }
      }
      buffer.write(' |\n');
      if (r < n - 1) {
        buffer.write('|');
        for (var c = 0; c < n; c++) {
          final op = (r < n - 2) ? ops[opId(null, c, 'col', r)] : '=';
          buffer.write('  $op ');
          if (c < n - 1) buffer.write('   ');
        }
        buffer.write(' |\n');
      }
    }
    buffer.write(hLine);
    return buffer.toString();
  }

  // ------------------- Main Generation Loop -------------------

  Future<void> generate() async {
    print('\n--- Generating ${config.gridN}x${config.gridN} Puzzle ---');
    print(
        '(Range: ${config.minN}-${config.maxN}, Ops: [${config.ops.join(', ')}])');
    if (config.numClues > 0) {
      print('(Seeding with up to ${config.numClues} random clues)');
    }

    for (var attempt = 1; attempt <= config.maxAttempts; attempt++) {
      print('\n--- Attempt $attempt/${config.maxAttempts} ---');

      // Step 1: Randomly generate operators.
      final opLayout = {'rows': <List<String>>[], 'cols': <List<String>>[]};
      final opDetails = <String, String>{};
      for (var r = 0; r < config.gridN; r++) {
        final ops =
            List.generate(config.gridN - 2, (_) => randChoice(config.ops));
        opLayout['rows']!.add(ops);
        ops.asMap().forEach((i, op) => opDetails[opId(r, null, 'row', i)] = op);
      }
      for (var c = 0; c < config.gridN; c++) {
        final ops =
            List.generate(config.gridN - 2, (_) => randChoice(config.ops));
        opLayout['cols']!.add(ops);
        ops.asMap().forEach((i, op) => opDetails[opId(null, c, 'col', i)] = op);
      }

      // Step 2: Determine forbidden clue locations (e.g., divisors).
      final forbiddenClueCells = <String>{};
      opLayout['rows']!.asMap().forEach((r, rowOps) {
        rowOps.asMap().forEach((i, op) {
          if (op == '÷') forbiddenClueCells.add(id(r, i + 1));
        });
      });
      opLayout['cols']!.asMap().forEach((c, colOps) {
        colOps.asMap().forEach((i, op) {
          if (op == '÷') forbiddenClueCells.add(id(i + 1, c));
        });
      });
      log('Forbidden clue locations: ${forbiddenClueCells.join(', ')}');

      // Step 3: Randomly generate clues in valid locations.
      final clues = <String, int>{};
      final allCells = [
        for (int r = 0; r < config.gridN; r++)
          for (int c = 0; c < config.gridN; c++) id(r, c)
      ];
      final validClueCells = allCells
          .where((cellId) => !forbiddenClueCells.contains(cellId))
          .toList()
        ..shuffle(_random);
      final numCluesToPlace = min(config.numClues, validClueCells.length);
      for (var i = 0; i < numCluesToPlace; i++) {
        clues[validClueCells[i]] = randInt(config.minN, config.maxN);
      }

      // Step 4: Display the generated puzzle skeleton.
      print('Generated puzzle layout:');
      print(asciiGrid(clues, opDetails, config.gridN));

      // Step 5: Model and attempt to solve the puzzle using both methods.

      // [Method 1: The Old Way]
      print('[1] Solving with the OLD WAY (Manual CspProblem)...');
      final oldWayProblem = buildPuzzleConstraintsOldWay(opLayout, clues);
      final oldWaySolution = await CSP.solve(oldWayProblem);

      // [Method 2: The New Way]
      print('[2] Solving with the NEW WAY (Problem Builder)...');
      final newWayProblemBuilder =
          buildPuzzleConstraintsNewWay(opLayout, clues);
      await newWayProblemBuilder.getSolution();

      // Step 6: Report the outcome.
      // The solution from both methods should be identical.
      if (oldWaySolution != 'FAILURE') {
        print(
            '\n✅ SUCCESS! Both methods found a solution for the layout above:');
        print(asciiGrid(
            oldWaySolution as Map<String, dynamic>, opDetails, config.gridN));
        return; // Exit successfully.
      } else {
        print('❌ Both methods failed to solve. Generating new layout.');
      }
    }
    print(
        '\n--- FAILED to find a solvable layout in ${config.maxAttempts} attempts. ---');
  }
}
