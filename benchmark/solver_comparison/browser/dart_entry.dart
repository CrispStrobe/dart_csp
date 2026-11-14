/// Browser boundary for the same IO-free adapter used by the native executable.
library;

import 'dart:convert';
import 'dart:js_interop';

import '../dart_adapter_core.dart';

@JS('comparisonBegin')
external set _comparisonBegin(JSFunction value);

@JS('comparisonStep')
external set _comparisonStep(JSFunction value);

@JS('comparisonDispose')
external set _comparisonDispose(JSFunction value);

DartComparisonRunner? _runner;

JSString _begin(JSString encoded) {
  final json = (jsonDecode(encoded.toDart) as Map).cast<String, Object?>();
  _runner = DartComparisonRunner(ComparisonRequest.fromJson(json));
  return jsonEncode({
    ..._runner!.metadata(),
    'browser_boundary': 'JSON input once; JSON output per operation',
    'stopwatch_frequency': Stopwatch().frequency,
  }).toJS;
}

JSString _step(JSNumber index) {
  final runner = _runner;
  if (runner == null) throw StateError('Call comparisonBegin first.');
  return jsonEncode(runner.step(index.toDartDouble.toInt())).toJS;
}

void _dispose() => _runner = null;

void main() {
  _comparisonBegin = _begin.toJS;
  _comparisonStep = _step.toJS;
  _comparisonDispose = _dispose.toJS;
}
