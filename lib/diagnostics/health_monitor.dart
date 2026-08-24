import 'dart:async';

import 'package:flutter/foundation.dart';

import '../behaviour_engine/behaviour_engine_client.dart';
import '../ecom_ad_handler/ecom_ad_handler_client.dart';
import '../pipeline/circuit_breaker.dart';
import '../safety_memory/safety_memory_client.dart';
import '../sources/source_manager.dart';

// Polls circuit-breaker state for the 3 HTTP engines (BE/AH/SMA) plus
// SourceManager health. CE and IE are persistent WebSocket connections, not
// request/response calls, so a breaker doesn't apply to them the same way -
// their own reconnect-on-error logic already covers that resilience need.
class HealthMonitor extends ChangeNotifier {
  final BehaviourEngineClient _behaviourEngineClient;
  final EcomAdHandlerClient _ecomAdHandlerClient;
  final SafetyMemoryClient _safetyMemoryClient;
  final SourceManager _sourceManager;

  Timer? _timer;
  bool _isRunning = false;

  HealthMonitor({
    required this._behaviourEngineClient,
    required this._ecomAdHandlerClient,
    required this._safetyMemoryClient,
    required this._sourceManager,
  }) {
    _sourceManager.addListener(_onSourceHealthUpdated);
  }

  bool get isRunning => _isRunning;

  CircuitState get behaviourState => _behaviourEngineClient.circuitBreaker.state;
  CircuitState get ecomState => _ecomAdHandlerClient.circuitBreaker.state;
  CircuitState get memoryState => _safetyMemoryClient.circuitBreaker.state;

  void start() {
    if (_isRunning) return;
    _isRunning = true;
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => notifyListeners());
    notifyListeners();
  }

  void _onSourceHealthUpdated() => notifyListeners();

  void stop() {
    _isRunning = false;
    _timer?.cancel();
    _timer = null;
    notifyListeners();
  }

  void resetAllCircuits() {
    _behaviourEngineClient.circuitBreaker.reset();
    _ecomAdHandlerClient.circuitBreaker.reset();
    _safetyMemoryClient.circuitBreaker.reset();
    notifyListeners();
  }

  @override
  void dispose() {
    stop();
    _sourceManager.removeListener(_onSourceHealthUpdated);
    super.dispose();
  }
}
