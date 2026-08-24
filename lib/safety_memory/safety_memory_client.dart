import 'dart:convert';

import 'package:http/http.dart' as http;

import '../app_logger.dart';
import '../env_config.dart';
import '../pipeline/circuit_breaker.dart';
import 'safety_memory_input.dart';

// Calls the Memory Safety Agent (MSEAPI.pdf v3): myna.glassdata.ai/api/v1/sma/.
// /ws/camera and /release from earlier versions are gone - not implemented.
class SafetyMemoryClient {
  final String safetyMemoryUrl;
  final circuitBreaker = CircuitBreaker(name: 'safety_memory');

  SafetyMemoryClient({String? safetyMemoryUrl})
    : safetyMemoryUrl = safetyMemoryUrl ?? EnvConfig.safetyMemoryUrl;

  Future<dynamic> postAllergy(AllergyRequest request) => _post('allergy', request.toJson());
  Future<dynamic> postInp(SafetyMemoryInput input) => _post('inp', input.toJson());
  Future<dynamic> getHealth() => _get('health');

  Future<dynamic> getMemoryQuery({dynamic userId}) =>
      _get('memory/query', queryParameters: userId != null ? {'user_id': '$userId'} : null);

  Uri _resolve(String endpointPath, [Map<String, String>? queryParameters]) {
    final base = safetyMemoryUrl.endsWith('/') ? safetyMemoryUrl : '$safetyMemoryUrl/';
    return Uri.parse('$base$endpointPath').replace(queryParameters: queryParameters);
  }

  Future<dynamic> _get(String endpointPath, {Map<String, String>? queryParameters}) {
    return circuitBreaker.execute(() async {
      final uri = _resolve(endpointPath, queryParameters);
      AppLogger.log('SMA_REQUEST', 'GET $uri');
      final response = await http.get(uri);
      AppLogger.log('SMA_RESPONSE', '${response.statusCode} ${response.body}');
      return _decode(response);
    });
  }

  Future<dynamic> _post(String endpointPath, Map<String, dynamic> body) {
    return circuitBreaker.execute(() async {
      final uri = _resolve(endpointPath);
      final encodedBody = jsonEncode(body);
      AppLogger.log('SMA_REQUEST', 'POST $uri $encodedBody');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: encodedBody,
      );
      AppLogger.log('SMA_RESPONSE', '${response.statusCode} ${response.body}');
      return _decode(response);
    });
  }

  dynamic _decode(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw http.ClientException('SMA request failed: HTTP ${response.statusCode}: ${response.body}');
    }
    return jsonDecode(response.body);
  }
}
