enum CircuitState { closed, open, halfOpen }

// Opens after failureThreshold consecutive failures and blocks further calls
// until recoveryTimeout elapses, then allows one probe call (halfOpen) -
// success closes it again, failure re-opens it.
class CircuitBreaker {
  final String name;
  final int failureThreshold;
  final Duration recoveryTimeout;

  CircuitState _state = CircuitState.closed;
  int _failureCount = 0;
  DateTime? _lastStateChange;

  CircuitBreaker({required this.name, this.failureThreshold = 10, this.recoveryTimeout = const Duration(seconds: 15)});

  CircuitState get state {
    _checkRecovery();
    return _state;
  }

  bool get isAvailable {
    final s = state;
    return s == CircuitState.closed || s == CircuitState.halfOpen;
  }

  void _checkRecovery() {
    if (_state == CircuitState.open && _lastStateChange != null) {
      if (DateTime.now().difference(_lastStateChange!) >= recoveryTimeout) {
        _state = CircuitState.halfOpen;
        _lastStateChange = DateTime.now();
      }
    }
  }

  Future<T> execute<T>(Future<T> Function() request) async {
    if (!isAvailable) {
      throw CircuitBreakerException('Circuit breaker for $name is OPEN. Call blocked.');
    }
    try {
      final result = await request();
      _onSuccess();
      return result;
    } catch (error) {
      _onFailure();
      rethrow;
    }
  }

  void _onSuccess() {
    if (_state != CircuitState.closed) {
      _state = CircuitState.closed;
      _failureCount = 0;
      _lastStateChange = DateTime.now();
    }
  }

  void _onFailure() {
    _failureCount++;
    if (_failureCount >= failureThreshold) {
      _state = CircuitState.open;
      _lastStateChange = DateTime.now();
    }
  }

  void reset() {
    _state = CircuitState.closed;
    _failureCount = 0;
    _lastStateChange = DateTime.now();
  }
}

class CircuitBreakerException implements Exception {
  final String message;
  CircuitBreakerException(this.message);

  @override
  String toString() => 'CircuitBreakerException: $message';
}
