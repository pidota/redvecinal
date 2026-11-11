typedef SessionInvalidatedCallback = Future<void> Function();

/// Evita múltiples cierres de sesión concurrentes ante varios 401.
class SessionInvalidationCoordinator {
  SessionInvalidationCoordinator(this._onInvalidated);

  final SessionInvalidatedCallback _onInvalidated;
  Future<void>? _inFlight;
  DateTime? _lastCompletedAt;

  Future<void> handleUnauthorized() {
    final inFlight = _inFlight;
    if (inFlight != null) {
      return inFlight;
    }

    final last = _lastCompletedAt;
    if (last != null &&
        DateTime.now().difference(last) < const Duration(milliseconds: 300)) {
      return Future<void>.value();
    }

    final run = _onInvalidated();
    _inFlight = run;
    return run.whenComplete(() {
      _lastCompletedAt = DateTime.now();
      if (identical(_inFlight, run)) {
        _inFlight = null;
      }
    });
  }
}
