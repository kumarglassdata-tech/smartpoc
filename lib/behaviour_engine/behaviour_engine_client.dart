import 'dart:convert';

import 'package:http/http.dart' as http;

import '../app_logger.dart';
import '../env_config.dart';
import '../pipeline/circuit_breaker.dart';
import 'behaviour_engine_input.dart';

// Calls the behaviour engine's HTTP API. process() posts one BCP frame to
// /process; response shape varies (commerce / lifestyle / motion-suppression
// - see be_api_reference.md.pdf), so it's returned raw.
class BehaviourEngineClient {
  final String behaviourEnginePostUrl;
  final circuitBreaker = CircuitBreaker(name: 'behaviour_engine');

  BehaviourEngineClient({String? behaviourEnginePostUrl})
    : behaviourEnginePostUrl = behaviourEnginePostUrl ?? EnvConfig.behaviourEnginePostUrl;

  Future<Map<String, dynamic>> process(BehaviourEngineInput input) {
    return circuitBreaker.execute(() async {
      final url = Uri.parse(behaviourEnginePostUrl);
      final body = jsonEncode(input.toJson());
      AppLogger.log('BE_REQUEST', body);

      final response = await http.post(url, headers: {'Content-Type': 'application/json'}, body: body);
      AppLogger.log('BE_RESPONSE', '${response.statusCode} ${response.body}');

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw http.ClientException('BE /process failed: HTTP ${response.statusCode}: ${response.body}');
      }
      return jsonDecode(response.body) as Map<String, dynamic>;
    });
  }
}
