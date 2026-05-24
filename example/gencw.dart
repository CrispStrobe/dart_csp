/// gencw.dart - A Command-Line Math Crossword Puzzle Generator & Solver
///
/// This script procedurally generates unique math crossword puzzles, formulates them
/// as Constraint Satisfaction Problems (CSPs), and uses a backtracking solver to find a solution.
/// The generator is robust, retrying if a generated puzzle is proven to be unsolvable
/// or too complex to solve within a given timeout.
///
/// --------------------------------------------------------------------------
/// USAGE
/// --------------------------------------------------------------------------
/// Run the script from your terminal using the Dart VM:
///
///   dart gencw.dart [OPTIONS]
///
/// --------------------------------------------------------------------------
/// OPTIONS
/// --------------------------------------------------------------------------
///
/// --range=MIN-MAX
///   Sets the inclusive range of numbers that can appear in the puzzle cells.
///   - Format: Two integers separated by a hyphen.
///   - Example: --range=2-20
///   - Default: --range=1-9
///
/// --ops=[+,-,*,/]
///   Defines the set of allowed mathematical operations for the equations.
///   - Format: A comma-separated list of symbols. Use quotes if needed.
///   - Note: Use '-', not '−'. The script will convert it internally.
///   - Example: --ops=+,-,*,/
///   - Default: --ops=+,-,*,/ (all operations)
///
/// --edges=N
///   Controls the size and complexity of the generated puzzle grid. Higher numbers
///   result in more equations and a more sprawling pattern.
///   - Format: A single positive integer.
///   - Example: --edges=10
///   - Default: --edges=8
///
/// --clues=N
///   The number of cells to pre-fill with values before solving. Clues are
///   placed intelligently to provide maximum constraint and ensure diversity.
///   - Format: A single non-negative integer.
///   - Example: --clues=5
///   - Default: --clues=0
///
/// --nodups
///   A flag that enforces a global constraint where every number in the solution
///   must be unique. This makes the puzzle significantly harder to solve.
///   - Format: Just the flag, no value.
///   - Example: --nodups
///   - Default: Duplicates are allowed.
///
/// --timeout=S
///   The maximum time in seconds to allow the CSP solver to search for a solution.
///   If a solution isn't found in this time, the puzzle is discarded and the
///   generator will try again.
///   - Format: A single positive integer.
///   - Example: --timeout=60
///   - Default: --timeout=30
///
/// --------------------------------------------------------------------------
/// EXAMPLES
/// --------------------------------------------------------------------------
///
/// 1. Generate a simple, small puzzle with default settings:
///    dart gencw.dart
///
/// 2. Generate a medium puzzle using only addition and subtraction with 3 clues:
///    dart gencw.dart --range=2-20 --ops=+,- --clues=3
///
/// 3. Generate a large, very difficult puzzle where all numbers must be unique
///    and give the solver up to 2 minutes to find a solution:
///    dart gencw.dart --range=10-99 --edges=12 --clues=5 --nodups --timeout=120
///
/// --------------------------------------------------------------------------
/// HOW IT WORKS
/// --------------------------------------------------------------------------
///
/// The script follows a four-step process, looping until a solvable puzzle is found:
///
/// 1. Pattern Generation: A random walker algorithm creates a grid pattern of
///    interlocking horizontal and vertical lines of 5 squares.
///
/// 2. Clue Placement: If clues are requested, the script identifies the most
///    mathematically constraining positions (the "Power Positions") within a
///    diverse set of equations to maximize their impact on the solver.
///
/// 3. CSP Formulation: The grid is parsed into a set of variables (the empty
///    cells) and constraints (the equations and global rules like --nodups).
///
/// 4. Solving: The formulated problem is passed to a powerful backtracking CSP
///    solver which searches for a valid assignment of numbers to cells. If it
///    fails or times out, the entire process repeats.
///
library;

import 'dart:async';
import 'dart:math';

import 'package:dart_csp/dart_csp.dart';

// --------------------------------------------------------------------------
// CONFIGURATION & ARGUMENT PARSING
// --------------------------------------------------------------------------

class PuzzleConfig {
  PuzzleConfig({
    this.minN = 1,
    this.maxN = 9,
    this.ops = const ['+', '−', '×', '÷'],
    this.targetEdges = 8,
    this.numClues = 0,
    this.noDups = false,
    this.verbose = false,
    this.timeoutSeconds = 30, // Default to 30 seconds
  });
  int minN;
  int maxN;
  List<String> ops;
  int targetEdges;
  int numClues;
  bool noDups;
  bool verbose;
  int timeoutSeconds;
}

PuzzleConfig parseArgs(List<String> args) {
  final config = PuzzleConfig();

  for (final arg in args) {
    if (arg == 'verbose') {
      config.verbose = true;
      continue;
    }
    if (arg == '--nodups') {
      config.noDups = true;
      continue;
    }
    if (arg.startsWith('--')) {
      final parts = arg.substring(2).split('=');
      if (parts.length != 2) continue;
      final key = parts[0];
      final value = parts[1];

      switch (key) {
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
        case 'edges':
          final edges = int.tryParse(value);
          if (edges != null && edges > 0) {
            config.targetEdges = edges;
          }
          break;
        case 'clues':
          final clues = int.tryParse(value);
          if (clues != null && clues >= 0) {
            config.numClues = clues;
          }
          break;
        case 'timeout':
          final timeout = int.tryParse(value);
          if (timeout != null && timeout > 0) {
            config.timeoutSeconds = timeout;
          }
          break;
      }
    }
  }
  return config;
}

// --------------------------------------------------------------------------
// STEP 1: PATTERN GENERATION
// --------------------------------------------------------------------------

class GridPatternGenerator {
  GridPatternGenerator({
    required this.targetEdges,
    this.width = 30,
    this.height = 25,
  }) {
    initializeGrid();
    mazeStart = Point(width ~/ 2, height ~/ 2);
    firstDirection = random.nextInt(4);
    if (isValidPosition(mazeStart.x, mazeStart.y)) {
      grid[mazeStart.y][mazeStart.x] = '█';
    }
  }
  final int width;
  final int height;
  final int targetEdges;
  late List<List<String>> grid;
  final Random random = Random();
  int edgeCount = 0;
  late Point<int> mazeStart;
  late int firstDirection;
  final List<Point<int>> directions = [
    const Point(0, -1),
    const Point(1, 0),
    const Point(0, 1),
    const Point(-1, 0)
  ];

  void initializeGrid() {
    grid = List.generate(height, (_) => List.generate(width, (_) => ' '));
  }

  bool isValidPosition(int x, int y) =>
      x >= 2 && x < width - 2 && y >= 2 && y < height - 2;

  int countSquaresBehind(Point<int> pos, int direction) {
    final oppositeDir = directions[(direction + 2) % 4];
    var count = 0;
    for (var step = 1; step <= 4; step++) {
      final x = pos.x + (oppositeDir.x * step);
      final y = pos.y + (oppositeDir.y * step);
      if (!isValidPosition(x, y) || grid[y][x] != '█') break;
      count++;
    }
    return count;
  }

  bool canWalk4Steps(Point<int> pos, int direction) {
    if (countSquaresBehind(pos, direction) >= 4) return false;
    final dir = directions[direction];
    for (var step = 1; step <= 4; step++) {
      final x = pos.x + (dir.x * step);
      final y = pos.y + (dir.y * step);
      if (!isValidPosition(x, y)) return false;
      if (step < 4 && grid[y][x] == '█') return false;
    }
    return true;
  }

  Point<int> walk4Steps(Point<int> pos, int direction) {
    final dir = directions[direction];
    for (var step = 1; step <= 4; step++) {
      final x = pos.x + (dir.x * step);
      final y = pos.y + (dir.y * step);
      if (isValidPosition(x, y)) grid[y][x] = '█';
    }
    edgeCount++;
    return Point(pos.x + (dir.x * 4), pos.y + (dir.y * 4));
  }

  void runMazeWalker() {
    var currentPos = mazeStart;
    var currentDirection = firstDirection;

    for (var moves = 0; moves < 15 && edgeCount < targetEdges; moves++) {
      if (canWalk4Steps(currentPos, currentDirection)) {
        currentPos = walk4Steps(currentPos, currentDirection);
        final decision = random.nextInt(100);
        final turnOptions = <int>[
          (currentDirection + 1) % 4,
          (currentDirection + 3) % 4
        ]..shuffle(random);

        if (decision < 40) {
          final dir = directions[currentDirection];
          final backPos = Point<int>(
              currentPos.x - (dir.x * 2), currentPos.y - (dir.y * 2));
          var foundTurn = false;
          for (final newDir in turnOptions) {
            if (canWalk4Steps(backPos, newDir)) {
              currentPos = backPos;
              currentDirection = newDir;
              foundTurn = true;
              break;
            }
          }
          if (!foundTurn) break;
        } else {
          var foundTurn = false;
          for (final newDir in turnOptions) {
            if (canWalk4Steps(currentPos, newDir)) {
              currentDirection = newDir;
              foundTurn = true;
              break;
            }
          }
          if (!foundTurn) break;
        }
      } else {
        final turnOptions = <int>[
          (currentDirection + 1) % 4,
          (currentDirection + 3) % 4
        ]..shuffle(random);
        var foundTurn = false;
        for (final newDir in turnOptions) {
          if (canWalk4Steps(currentPos, newDir)) {
            currentDirection = newDir;
            foundTurn = true;
            break;
          }
        }
        if (!foundTurn) break;
      }
    }
  }

  List<List<String>> generatePattern() {
    for (var walker = 0; walker < 4 && edgeCount < targetEdges; walker++) {
      final oldEdgeCount = edgeCount;
      runMazeWalker();
      if (edgeCount == oldEdgeCount) break;
    }
    return grid;
  }
}

// --------------------------------------------------------------------------
// STEP 2: PUZZLE ANALYSIS & VALIDATION
// --------------------------------------------------------------------------

class Equation {
  Equation(this.numberCells, this.operatorCell, this.operator);
  final List<Point<int>> numberCells;
  final Point<int> operatorCell;
  final String operator;
  List<String> get variableNames =>
      numberCells.map((p) => 'C_${p.y}_${p.x}').toList();
  Set<Point<int>> get allCells {
    final op = operatorCell;
    final n1 = numberCells[0];
    final n2 = numberCells[1];
    final n3 = numberCells[2];
    return {
      n1,
      op,
      Point((op.x + n2.x) ~/ 2, (op.y + n2.y) ~/ 2),
      n2,
      Point((n2.x + n3.x) ~/ 2, (n2.y + n3.y) ~/ 2),
      n3
    };
  }

  @override
  String toString() =>
      '${variableNames[0]} $operator ${variableNames[1]} == ${variableNames[2]}';
}

class PuzzleParser {
  PuzzleParser(this.grid, this.config) {
    _findEquations();
  }
  final List<List<String>> grid;
  final PuzzleConfig config;
  final Random random = Random();
  final List<Equation> equations = [];
  final Set<Point<int>> numberCellLocations = {};

  void _findEquations() {
    final height = grid.length;
    final width = grid[0].length;
    for (var r = 0; r < height; r++) {
      for (var c = 0; c < width - 4; c++) {
        if (List.generate(5, (i) => grid[r][c + i])
            .every((cell) => cell == '█')) {
          final numberCells = [Point(c, r), Point(c + 2, r), Point(c + 4, r)];
          final operatorCell = Point(c + 1, r);
          final eq = Equation(numberCells, operatorCell,
              config.ops[random.nextInt(config.ops.length)]);
          equations.add(eq);
          numberCellLocations.addAll(numberCells);
        }
      }
    }
    for (var r = 0; r < height - 4; r++) {
      for (var c = 0; c < width; c++) {
        if (List.generate(5, (i) => grid[r + i][c])
            .every((cell) => cell == '█')) {
          final numberCells = [Point(c, r), Point(c, r + 2), Point(c, r + 4)];
          final operatorCell = Point(c, r + 1);
          final eq = Equation(numberCells, operatorCell,
              config.ops[random.nextInt(config.ops.length)]);
          equations.add(eq);
          numberCellLocations.addAll(numberCells);
        }
      }
    }
  }

  bool isPatternValid() {
    if (equations.isEmpty) return false;
    var totalBlockCells = 0;
    for (final row in grid) {
      for (final cell in row) {
        if (cell == '█') totalBlockCells++;
      }
    }
    final cellsInEquations = <Point<int>>{};
    for (final eq in equations) {
      cellsInEquations.addAll(eq.allCells);
    }
    return totalBlockCells == cellsInEquations.length;
  }
}

// --------------------------------------------------------------------------
// STEP 3 & 6: ASCII RENDERING
// --------------------------------------------------------------------------

class AsciiRenderer {
  AsciiRenderer(this.puzzle, this.config, {this.solution}) {
    cellWidth = config.maxN.toString().length + 2;
  }
  final PuzzleParser puzzle;
  final PuzzleConfig config;
  final Map<String, dynamic>? solution;
  late final int cellWidth;

  String render() {
    if (puzzle.numberCellLocations.isEmpty) return 'No valid equations found.';
    final equationCells = <Point<int>, String>{};
    for (final eq in puzzle.equations) {
      final mid1 = Point((eq.operatorCell.x + eq.numberCells[1].x) ~/ 2,
          (eq.operatorCell.y + eq.numberCells[1].y) ~/ 2);
      final mid2 = Point((eq.numberCells[1].x + eq.numberCells[2].x) ~/ 2,
          (eq.numberCells[1].y + eq.numberCells[2].y) ~/ 2);
      equationCells[mid1] = eq.operator;
      equationCells[mid2] = '=';
    }
    final allDrawableCells = {
      ...puzzle.numberCellLocations,
      ...equationCells.keys
    };
    final minX = allDrawableCells.map((p) => p.x).reduce(min);
    final maxX = allDrawableCells.map((p) => p.x).reduce(max);
    final minY = allDrawableCells.map((p) => p.y).reduce(min);
    final maxY = allDrawableCells.map((p) => p.y).reduce(max);
    final canvasWidth = (maxX - minX + 1) * (cellWidth + 1) + 1;
    final canvasHeight = (maxY - minY + 1) * 2 + 1;
    final canvas =
        List.generate(canvasHeight, (_) => List.filled(canvasWidth, ' '));

    for (final point in allDrawableCells) {
      _drawBox(canvas, point.x - minX, point.y - minY);
    }
    for (final point in allDrawableCells) {
      var content = '';
      if (equationCells.containsKey(point)) {
        content = equationCells[point]!;
      } else if (puzzle.numberCellLocations.contains(point)) {
        final varName = 'C_${point.y}_${point.x}';
        content = solution?[varName]?.toString() ?? '';
      }
      _fillText(canvas, point.x - minX, point.y - minY, content);
    }
    return canvas.map((row) => row.join()).join('\n');
  }

  void _drawBox(List<List<String>> canvas, int x, int y) {
    final cx = x * (cellWidth + 1);
    final cy = y * 2;
    canvas[cy][cx] = '+';
    canvas[cy][cx + cellWidth] = '+';
    canvas[cy + 2][cx] = '+';
    canvas[cy + 2][cx + cellWidth] = '+';
    for (var i = 1; i < cellWidth; i++) {
      canvas[cy][cx + i] = '-';
      canvas[cy + 2][cx + i] = '-';
    }
    canvas[cy + 1][cx] = '|';
    canvas[cy + 1][cx + cellWidth] = '|';
  }

  void _fillText(List<List<String>> canvas, int x, int y, String text) {
    final cx = x * (cellWidth + 1) + (cellWidth ~/ 2) - (text.length - 1) ~/ 2;
    final cy = y * 2 + 1;
    for (var i = 0; i < text.length; i++) {
      if (cx + i < canvas[cy].length) {
        canvas[cy][cx + i] = text[i];
      }
    }
  }
}

// --------------------------------------------------------------------------
// MAIN ORCHESTRATOR
// --------------------------------------------------------------------------
void main(List<String> args) async {
  final config = parseArgs(args);
  print('--- MATH CROSSWORD PUZZLE GENERATOR & SOLVER ---');
  print(
      'Config: Range=${config.minN}-${config.maxN}, Ops=${config.ops}, Edges=${config.targetEdges}, Clues=${config.numClues}, NoDups=${config.noDups}, Timeout=${config.timeoutSeconds}s');

  dynamic solution;
  PuzzleParser? successfulPuzzle;
  const maxAttempts = 100;

  for (var attempt = 1; attempt <= maxAttempts; attempt++) {
    print('\n${'-' * 60}');
    print('--- ATTEMPT $attempt/$maxAttempts ---');

    // STEP 1: Generate a valid pattern
    print('[1] Generating pattern...');
    PuzzleParser puzzle;
    var patternAttempt = 0;
    do {
      patternAttempt++;
      final generator = GridPatternGenerator(targetEdges: config.targetEdges);
      final rawGrid = generator.generatePattern();
      puzzle = PuzzleParser(rawGrid, config);
    } while (!puzzle.isPatternValid() && patternAttempt < 100);

    if (!puzzle.isPatternValid()) {
      print('  -> FAILED to generate a valid puzzle pattern. Retrying...');
      continue; // Restart the main loop
    }

    final allVarNames =
        puzzle.numberCellLocations.map((p) => 'C_${p.y}_${p.x}').toList();
    print(
        '  -> Pattern found with ${puzzle.equations.length} equations and ${allVarNames.length} cells.');

    // STEP 2: Generate intelligent clues
    print("[2] Generating ${config.numClues} 'Power Position' clues...");
    final clues = <String, int>{};
    final domain = List<int>.generate(
        config.maxN - config.minN + 1, (i) => i + config.minN);

    final variableCounts = <String, int>{};
    for (final varName in allVarNames) {
      variableCounts[varName] = 0;
    }
    for (final eq in puzzle.equations) {
      for (final varName in eq.variableNames) {
        variableCounts[varName] = (variableCounts[varName] ?? 0) + 1;
      }
    }

    final candidates = <String>[...allVarNames];
    final clueVars = <String>[];
    final disqualifiedEquations = <Equation>{};

    for (var i = 0; i < config.numClues && candidates.isNotEmpty; i++) {
      candidates
          .sort((a, b) => variableCounts[b]!.compareTo(variableCounts[a]!));
      if (candidates.isEmpty) break;
      final bestCandidate = candidates.first;

      final chosenEquation = puzzle.equations.firstWhere(
        (eq) =>
            eq.variableNames.contains(bestCandidate) &&
            !disqualifiedEquations.contains(eq),
        orElse: () => puzzle.equations.first,
      );

      String clueVariable;
      switch (chosenEquation.operator) {
        case '+':
        case '×':
          clueVariable = chosenEquation.variableNames[2];
          break;
        case '−':
        case '÷':
          clueVariable = chosenEquation.variableNames[0];
          break;
        default:
          clueVariable = bestCandidate;
      }
      clueVars.add(clueVariable);
      disqualifiedEquations.add(chosenEquation);
      candidates.removeWhere((v) => chosenEquation.variableNames.contains(v));
    }

    final usedClueValues = <int>{};
    for (final clueVar in clueVars.toSet()) {
      int clueValue;
      do {
        clueValue = domain[Random().nextInt(domain.length)];
      } while (config.noDups && usedClueValues.contains(clueValue));
      clues[clueVar] = clueValue;
      if (config.noDups) usedClueValues.add(clueValue);
    }
    print('  -> Clues placed: $clues');

    // STEP 3: Formulate and solve the CSP with a timeout
    print('[3] Solving puzzle (timeout in ${config.timeoutSeconds}s)...');
    final p = Problem();
    final fullDomain = List<int>.generate(
        config.maxN - config.minN + 1, (i) => i + config.minN);
    if (config.noDups) {
      fullDomain.removeWhere((val) => clues.values.contains(val));
    }
    for (final varName in allVarNames) {
      if (clues.containsKey(varName)) {
        p.addVariable(varName, [clues[varName]]);
      } else {
        p.addVariable(varName, fullDomain);
      }
    }
    for (final eq in puzzle.equations) {
      p.addConstraint(eq.variableNames, (Map<String, dynamic> assignment) {
        final a = assignment[eq.variableNames[0]];
        final b = assignment[eq.variableNames[1]];
        final c = assignment[eq.variableNames[2]];
        if (a == null || b == null || c == null) return false;
        switch (eq.operator) {
          case '+':
            return a + b == c;
          case '−':
            return a - b == c;
          case '×':
            return a * b == c;
          case '÷':
            return b != 0 && a % b == 0 && a ~/ b == c;
          default:
            return false;
        }
      });
    }
    if (config.noDups) {
      p.addAllDifferent(allVarNames);
    }

    final stopwatch = Stopwatch()..start();
    try {
      final potentialSolution = await p
          .getSolution()
          .timeout(Duration(seconds: config.timeoutSeconds));
      stopwatch.stop();

      if (potentialSolution != 'FAILURE') {
        print(
            '  -> SUCCESS! Solution found in ${stopwatch.elapsedMilliseconds}ms.');
        solution = potentialSolution;
        successfulPuzzle = puzzle;
        print('\n[4] Puzzle to be solved:');
        final emptyRenderer = AsciiRenderer(puzzle, config, solution: clues);
        print(emptyRenderer.render());
        break;
      } else {
        print(
            '  -> UNSOLVABLE. The generated clues create a contradiction. Retrying...');
      }
    } on TimeoutException {
      stopwatch.stop();
      print(
          '  -> TIMEOUT. The puzzle is too complex to solve in ${stopwatch.elapsedMilliseconds}ms. Retrying...');
    }
  }

  print('\n${'=' * 60}');
  // STEP 4: Display the final result
  if (solution != null && solution != 'FAILURE' && successfulPuzzle != null) {
    print('--- FINAL SOLUTION ---');
    final solvedRenderer = AsciiRenderer(successfulPuzzle, config,
        solution: solution as Map<String, dynamic>?);
    print(solvedRenderer.render());
  } else {
    print(
        '--- FAILED to generate a solvable puzzle after $maxAttempts attempts. ---');
    print(
        'Consider increasing the timeout (--timeout), reducing the number range (--range), or allowing duplicates.');
  }
}
