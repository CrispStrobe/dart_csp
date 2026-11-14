/// Native JSONL host; the adapter core remains usable by a browser host.
library;

import 'dart:convert';
import 'dart:io';

import 'dart_adapter_core.dart';

Future<void> main(List<String> arguments) async {
  try {
    if (arguments.length != 1) {
      throw ArgumentError('usage: dart-adapter REQUEST.json');
    }
    final decoded = jsonDecode(await File(arguments.single).readAsString());
    if (decoded is! JsonObject) {
      throw ArgumentError('Request must be an object.');
    }
    for (final record in evaluateDartComparisonRequest(decoded)) {
      stdout.writeln(jsonEncode(record));
      await stdout.flush();
    }
  } catch (error) {
    stderr.writeln('dart-adapter: $error');
    exitCode = 2;
  }
}
