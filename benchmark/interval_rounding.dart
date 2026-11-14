/// Batched portable next-representable-double guard. The ByteData oracle and
/// every result check run outside timing; output writes remain inside each
/// measured batch so the optimizer cannot discard the rounding operations.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_csp/dart_csp.dart' show IntervalRounding;

Float64List _inputs() {
  final values = <double>[
    0.0,
    -0.0,
    double.minPositive,
    -double.minPositive,
    _fromWords(0x000fffff, 0xffffffff),
    _fromWords(0x800fffff, 0xffffffff),
    _fromWords(0x00100000, 0),
    _fromWords(0x80100000, 0),
    1.0,
    -1.0,
    double.maxFinite,
    -double.maxFinite,
    double.infinity,
    double.negativeInfinity,
    double.nan,
    -double.nan,
  ];
  for (final exponent in [2, 512, 1022, 1023, 1024, 1534, 2045, 2046]) {
    for (final low in [0, 1, 0xffffffff]) {
      final high = (exponent << 20) | 0x000fffff;
      values.add(_fromWords(high, low));
      values.add(_fromWords(high | 0x80000000, low));
    }
  }
  if (values.length != 64) throw StateError('Expected 64 input patterns.');
  return Float64List.fromList(values);
}

double _fromWords(int high, int low) {
  final bytes = ByteData(8);
  bytes.setUint32(0, high);
  bytes.setUint32(4, low);
  return bytes.getFloat64(0);
}

// An independent explicit-endian bit oracle, without native typed-data views.
// The nonfinite/zero rules are handled before stepping the unsigned words.
double _referenceUp(double value) {
  if (value.isNaN || value == double.infinity) return value;
  if (value == 0) return double.minPositive;
  final bytes = ByteData(8)..setFloat64(0, value);
  var high = bytes.getUint32(0), low = bytes.getUint32(4);
  if (value > 0) {
    if (low == 0xffffffff) {
      low = 0;
      high++;
    } else {
      low++;
    }
  } else if (low == 0) {
    low = 0xffffffff;
    high--;
  } else {
    low--;
  }
  bytes.setUint32(0, high);
  bytes.setUint32(4, low);
  return bytes.getFloat64(0);
}

List<int> _words(double value) {
  // IEEE permits different NaN payloads; require NaN and use one checksum token.
  if (value.isNaN) return [0x7ff80000, 0];
  final bytes = ByteData(8)..setFloat64(0, value);
  return [bytes.getUint32(0), bytes.getUint32(4)];
}

int _verify(Float64List output, List<List<int>> expected) {
  final bytes = ByteData(8);
  var checksum = 0;
  for (var i = 0; i < output.length; i++) {
    final value = output[i];
    // Serialize through explicit big-endian ByteData; the oracle does not
    // reuse the production method's native-word layout or endian selection.
    bytes.setFloat64(0, value);
    final actualHigh = value.isNaN ? 0x7ff80000 : bytes.getUint32(0);
    final actualLow = value.isNaN ? 0 : bytes.getUint32(4);
    final wanted = expected[i & 63];
    if (actualHigh != wanted[0] || actualLow != wanted[1]) {
      throw StateError('Rounding mismatch at operation $i: '
          '[$actualHigh, $actualLow] != $wanted');
    }
    checksum = (checksum + actualHigh + actualLow) % 4294967296;
  }
  return checksum;
}

int _percentile(List<int> samples, int percent) {
  final sorted = [...samples]..sort();
  return sorted[(sorted.length * percent + 99) ~/ 100 - 1];
}

Map<String, Object> _measure(String name, Float64List inputs,
    {required bool down,
    required int batch,
    required int warmups,
    required int samples,
    required bool checkOnly}) {
  final output = Float64List(batch);
  final expected = [
    for (final value in inputs)
      _words(down ? -_referenceUp(-value) : _referenceUp(value)),
  ];
  var expectedChecksum = 0;
  for (var i = 0; i < batch; i++) {
    final words = expected[i & 63];
    expectedChecksum = (expectedChecksum + words[0] + words[1]) % 4294967296;
  }
  final times = <int>[];
  final checksums = <int>[];
  for (var sample = -warmups; sample < samples; sample++) {
    final watch = checkOnly ? null : (Stopwatch()..start());
    if (down) {
      for (var i = 0; i < output.length; i++) {
        output[i] = IntervalRounding.nextDown(inputs[i & 63]);
      }
    } else {
      for (var i = 0; i < output.length; i++) {
        output[i] = IntervalRounding.nextUp(inputs[i & 63]);
      }
    }
    watch?.stop();
    final checksum = _verify(output, expected);
    if (checksum != expectedChecksum) throw StateError('Checksum mismatch.');
    if (sample >= 0) {
      if (watch != null) times.add(watch.elapsedMicroseconds);
      checksums.add(checksum);
    }
  }
  return {
    'name': name,
    'operations_per_batch': batch,
    'expected_checksum': expectedChecksum,
    'checksums': checksums,
    'samples_us': times,
    if (!checkOnly) ...{
      'p50': _percentile(times, 50),
      'p95': _percentile(times, 95),
    },
  };
}

void main(List<String> arguments) {
  var samples = 50, warmups = 20, batch = 16384;
  final checkOnly = arguments.contains('--check-only');
  for (final argument in arguments) {
    if (argument == '--check-only') continue;
    final pair = argument.split('=');
    if (pair.length != 2 ||
        !['--samples', '--warmups', '--batch'].contains(pair.first)) {
      throw ArgumentError('Use --samples=N, --warmups=N, --batch=N '
          'or --check-only.');
    }
    final value = int.tryParse(pair.last);
    final minimum =
        pair.first == '--warmups' ? 0 : (pair.first == '--batch' ? 64 : 1);
    if (value == null || value < minimum) {
      throw ArgumentError('Invalid count: $argument');
    }
    if (pair.first == '--samples') samples = value;
    if (pair.first == '--warmups') warmups = value;
    if (pair.first == '--batch') batch = value;
  }
  if (checkOnly) {
    samples = 1;
    warmups = 0;
    batch = 64;
  }
  final inputs = _inputs();
  print(jsonEncode({
    'schema': 'interval_rounding_v1',
    'check_only': checkOnly,
    'samples': samples,
    'warmups': warmups,
    'input_bits': [for (final value in inputs) _words(value)],
    'method': 'Fresh-process batched throughput guard. Each timed batch includes '
        'input reads, nextUp/nextDown calls and writes to preallocated output. '
        'An independent ByteData oracle verifies every result after timing. '
        'Raw samples retain acquisition order. p50/p95 use nearest rank. '
        'This is a primitive throughput guard, not complete CAD latency.',
    'results': [
      for (final down in [false, true])
        _measure(down ? 'next_down' : 'next_up', inputs,
            down: down,
            batch: batch,
            warmups: warmups,
            samples: samples,
            checkOnly: checkOnly),
    ],
  }));
}
