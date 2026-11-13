/// Portable exact-integer arithmetic envelope for cumulative scheduling.
///
/// Dart's native ints wrap at 64 bits; JavaScript-backed ints round beyond
/// 2^53. Scheduling bounds and energy proofs must not silently use either.
library;

const int _safeInteger = 9007199254740991;
final BigInt _bigSafeInteger = BigInt.from(_safeInteger);

Never _unsupported(String quantity) => throw UnsupportedError(
    'Cumulative $quantity exceeds the portable exact-integer arithmetic '
    'range [-9007199254740991, 9007199254740991]. '
    'Rescale time/resource units or use a smaller scheduling horizon.');

void checkCumulativeInteger(int value, String quantity,
    {bool nonnegative = false}) {
  if (!value.isFinite ||
      value < -_safeInteger ||
      value > _safeInteger ||
      (nonnegative && value < 0)) {
    _unsupported(quantity);
  }
}

int _add(int a, int b, String quantity) {
  if ((b > 0 && a > _safeInteger - b) || (b < 0 && a < -_safeInteger - b)) {
    _unsupported(quantity);
  }
  return a + b;
}

int _multiply(int a, int b, String quantity) {
  // Ordinary scheduling units stay on machine ints. A deliberately loose
  // fast bound is sufficient; only products near/beyond the exact envelope
  // need BigInt, and no inner propagation loop uses arbitrary precision.
  if (a.toDouble() * b.toDouble() < 4503599627370496.0) return a * b;
  final product = BigInt.from(a) * BigInt.from(b);
  if (product > _bigSafeInteger) _unsupported(quantity);
  return product.toInt();
}

/// Check all bounds required by a propagation call before arithmetic runs.
/// Returns the total active demand; if it is at most capacity, the resource
/// constraint cannot overload and needs no profile or energetic reasoning.
int validateCumulativeArithmetic(List<int> earliest, List<int> latest,
    List<int> durations, List<int> demands, int capacity,
    {required bool energetic, void Function()? tick}) {
  checkCumulativeInteger(capacity, 'capacity', nonnegative: true);
  var totalDemand = 0;
  int? firstStart, lastEnd;
  var largestDuration = 0;
  for (var i = 0; i < durations.length; i++) {
    tick?.call();
    if (durations[i] == 0 || demands[i] == 0) continue;
    checkCumulativeInteger(durations[i], 'duration', nonnegative: true);
    checkCumulativeInteger(demands[i], 'demand', nonnegative: true);
    checkCumulativeInteger(earliest[i], 'start');
    checkCumulativeInteger(latest[i], 'start');
    final end = _add(latest[i], durations[i], 'task endpoint');
    if (firstStart == null || earliest[i] < firstStart) {
      firstStart = earliest[i];
    }
    if (lastEnd == null || end > lastEnd) lastEnd = end;
    if (durations[i] > largestDuration) largestDuration = durations[i];
    totalDemand = _add(totalDemand, demands[i], 'aggregate demand');
  }
  if (firstStart == null || totalDemand <= capacity) return totalDemand;

  // These bounds cover every segment.start-duration+1, endpoint subtraction,
  // and relevant-window length used by the swept/energetic algorithms.
  _add(_add(firstStart, -largestDuration, 'forbidden start'), 1,
      'forbidden start');
  final horizon = _add(lastEnd!, -firstStart, 'horizon difference');
  if (energetic) {
    _multiply(capacity, horizon, 'capacity-window energy');
    var totalEnergy = 0;
    for (var i = 0; i < durations.length; i++) {
      tick?.call();
      if (durations[i] == 0 || demands[i] == 0) continue;
      totalEnergy = _add(
          totalEnergy,
          _multiply(durations[i], demands[i], 'task energy'),
          'aggregate energy');
    }
  }
  return totalDemand;
}

/// Independent complete-assignment check shared by the builder and compiled
/// validator. Half-open interval endpoints are swept without visiting ticks.
bool satisfiesCumulativePoint(List<dynamic> starts, List<int> durations,
    List<int> demands, int capacity) {
  final integerStarts = List<int>.filled(starts.length, 0);
  for (var i = 0; i < starts.length; i++) {
    if (durations[i] == 0 || demands[i] == 0) continue;
    final value = starts[i];
    if (value is num && !value.isFinite) _unsupported('start');
    if (value is! int) return false;
    integerStarts[i] = value;
  }
  final totalDemand = validateCumulativeArithmetic(
      integerStarts, integerStarts, durations, demands, capacity,
      energetic: false);
  if (totalDemand <= capacity) return true;
  final events = <int, int>{};
  for (var i = 0; i < starts.length; i++) {
    final duration = durations[i], demand = demands[i];
    if (duration == 0 || demand == 0) continue;
    final start = integerStarts[i], end = start + duration;
    events[start] = (events[start] ?? 0) + demand;
    events[end] = (events[end] ?? 0) - demand;
  }
  var load = 0;
  final times = events.keys.toList()..sort();
  for (final time in times) {
    load += events[time]!;
    if (load > capacity) return false;
  }
  return true;
}
