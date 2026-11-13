/// Shared bounded sampling for the matching/GCC before-and-after workloads.
library;

import 'package:dart_csp/dart_csp.dart';

class BenchmarkSampling {
  const BenchmarkSampling({this.samples = 7, this.warmups = 2});

  factory BenchmarkSampling.parse(List<String> arguments) {
    var samples = 7;
    var warmups = 2;
    for (final argument in arguments) {
      final parts = argument.split('=');
      if (parts.length != 2 ||
          (parts.first != '--samples' && parts.first != '--warmups')) {
        throw ArgumentError('Use --samples=N and/or --warmups=N.');
      }
      final count = int.tryParse(parts.last);
      if (count == null || count < (parts.first == '--samples' ? 1 : 0)) {
        throw ArgumentError('Invalid count: $argument');
      }
      if (parts.first == '--samples') {
        samples = count;
      } else {
        warmups = count;
      }
    }
    return BenchmarkSampling(samples: samples, warmups: warmups);
  }

  final int samples;
  final int warmups;

  Future<String> measure(Future<int> Function() run) async {
    for (var i = 0; i < warmups; i++) {
      await run();
    }
    final timings = [for (var i = 0; i < samples; i++) await run()]..sort();
    final middle = timings.length ~/ 2;
    final median = timings.length.isOdd
        ? timings[middle]
        : (timings[middle - 1] + timings[middle]) / 2;
    // Nearest rank. With seven samples p95 is the maximum; >= 20 samples
    // separate the two and make a tail comparison more informative.
    final p95 = timings[(timings.length * 95 + 99) ~/ 100 - 1];
    return 'median=${median}us p95=${p95}us max=${timings.last}us; '
        'samples=$samples warmups=$warmups';
  }
}

/// Extract by map key so this same harness can run at older comparison commits
/// that predate the additional work counters. Missing counters stay absent.
void collectMatchingWork(SolverStats stats, Map<String, int> totals) {
  final values = stats.toMap();
  for (final name in const [
    'decisions',
    'naryRevises',
    'gccPropagations',
    'gccAugmentations',
    'matchingSccPasses',
    'matchingWorkspaceGrowths',
    'matchingFixedPointSkips',
  ]) {
    final value = values[name];
    if (value is int) {
      totals.update(name, (previous) => previous + value,
          ifAbsent: () => value);
    }
  }
}
