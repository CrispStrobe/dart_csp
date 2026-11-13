/// Cooperative polling during long matching and residual-graph operations.
part of 'solver.dart';

class _PropagationInterrupted implements Exception {
  const _PropagationInterrupted();
}

class _PropagationBudget {
  _PropagationBudget(this.shouldStop);
  final bool Function() shouldStop;
  var _remaining = 0;

  void tick() {
    if (--_remaining > 0) return;
    _remaining = 256;
    if (shouldStop()) throw const _PropagationInterrupted();
  }
}
