import 'package:flutter/foundation.dart';

class DiagnosticLog {
  final DateTime timestamp;
  final String source;
  final String message;
  final bool isError;
  DiagnosticLog({required this.timestamp, required this.source, required this.message, this.isError = false});
}

// FPS/frame counters, per-engine latency, and a capped rolling diagnostic
// log - populated by SessionProvider's runtime loop, consumed by debug UI.
class TelemetryService extends ChangeNotifier {
  final Map<String, int> _latencies = {};
  final List<DiagnosticLog> _logs = [];
  int _droppedFrames = 0;
  int _capturedFrames = 0;

  Map<String, int> get latencies => _latencies;
  List<DiagnosticLog> get logs => _logs;
  int get droppedFrames => _droppedFrames;
  int get capturedFrames => _capturedFrames;

  void addLog(String source, String message, {bool isError = false}) {
    _logs.insert(0, DiagnosticLog(timestamp: DateTime.now(), source: source, message: message, isError: isError));
    if (_logs.length > 100) _logs.removeLast();
    notifyListeners();
  }

  void recordLatency(String engineName, int latencyMs) {
    _latencies[engineName] = latencyMs;
    notifyListeners();
  }

  void incrementDroppedFrames() {
    _droppedFrames++;
    notifyListeners();
  }

  void incrementCapturedFrames() {
    _capturedFrames++;
    notifyListeners();
  }

  void clearMetrics() {
    _latencies.clear();
    _droppedFrames = 0;
    _capturedFrames = 0;
    notifyListeners();
  }
}
