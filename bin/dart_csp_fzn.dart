/// FlatZinc command-line frontend for dart_csp.
///
/// Reads FlatZinc source from a file path argument or from stdin and
/// prints the standard FlatZinc output format to stdout. Designed to
/// be invokable as a MiniZinc solver configuration: a `.msc` pointing
/// at this binary makes the full `mzn2fzn` → solver pipeline work
/// without further glue.
///
/// Usage:
///   dart run dart_csp:dart_csp_fzn [options] [model.fzn]
///   cat model.fzn | dart run dart_csp:dart_csp_fzn [options]
///
/// Options:
///   -a            Print every solution (FlatZinc convention for
///                 satisfaction problems; for optimization the final
///                 solution is always printed regardless).
///   -s            Print a short stats block after the solution stream
///                 ends. Stats are dart_csp's `lastStats` rendered as
///                 a `%%%mzn-stat` comment block.
///   -h, --help    Print this help text and exit.
///
/// Search annotations on `solve` (e.g. `:: int_search(...)`) are parsed
/// but not yet applied; the default solver heuristic is used.
library;

import 'dart:io';

import 'package:dart_csp/dart_csp.dart';

const _help = '''
dart_csp_fzn — FlatZinc frontend for dart_csp.

Usage:
  dart run dart_csp:dart_csp_fzn [options] [model.fzn]
  cat model.fzn | dart run dart_csp:dart_csp_fzn [options]

Options:
  -a            Print every solution (satisfaction problems only).
  -s            Print stats as `%%%mzn-stat` comments after solving.
  -h, --help    Print this help and exit.
''';

Future<void> main(List<String> args) async {
  exitCode = await _run(args);
}

Future<int> _run(List<String> args) async {
  var allSolutions = false;
  var showStats = false;
  String? sourcePath;

  for (final a in args) {
    switch (a) {
      case '-a':
      case '--all-solutions':
        allSolutions = true;
      case '-s':
      case '--statistics':
        showStats = true;
      case '-h':
      case '--help':
        stdout.write(_help);
        return 0;
      default:
        if (a.startsWith('-')) {
          stderr.writeln('dart_csp_fzn: unknown option \'$a\'');
          stderr.write(_help);
          return 64; // EX_USAGE
        }
        if (sourcePath != null) {
          stderr.writeln('dart_csp_fzn: only one source file path is allowed.');
          return 64;
        }
        sourcePath = a;
    }
  }

  final String source;
  if (sourcePath == null) {
    // Read stdin until EOF.
    final buf = StringBuffer();
    await for (final chunk in stdin) {
      buf.write(String.fromCharCodes(chunk));
    }
    source = buf.toString();
  } else {
    final file = File(sourcePath);
    if (!await file.exists()) {
      stderr.writeln('dart_csp_fzn: file not found: $sourcePath');
      return 66; // EX_NOINPUT
    }
    source = await file.readAsString();
  }

  try {
    final output = await FlatZinc.solve(source, all: allSolutions);
    stdout.write(output);

    if (showStats) {
      final stats = CSP.lastStats;
      if (stats != null) {
        stdout.writeln('%%%mzn-stat: decisions=${stats.decisions}');
        stdout.writeln('%%%mzn-stat: backtracks=${stats.backtracks}');
        stdout.writeln('%%%mzn-stat: solveTime='
            '${stats.elapsedMicros / 1e6}');
        stdout.writeln('%%%mzn-stat-end');
      }
    }
    return 0;
  } on FormatException catch (e) {
    stderr.writeln('dart_csp_fzn: parse error: ${e.message}');
    return 65; // EX_DATAERR
    // CLI top-level error translation: convert error subclasses to
    // exit codes rather than letting them surface as a stack trace.
    // ignore: avoid_catching_errors
  } on UnimplementedError catch (e) {
    stderr.writeln('dart_csp_fzn: ${e.message}');
    return 78; // EX_CONFIG
    // ignore: avoid_catching_errors
  } on ArgumentError catch (e) {
    stderr.writeln('dart_csp_fzn: ${e.message}');
    return 65;
  }
}
