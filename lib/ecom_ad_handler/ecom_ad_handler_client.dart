import 'dart:convert';

import 'package:http/http.dart' as http;

import '../app_logger.dart';
import '../env_config.dart';
import '../pipeline/circuit_breaker.dart';
import 'ecom_ad_handler_input.dart';

// Calls the real deployed ecom hub endpoints (myna.glassdata.ai/api/v1/ah/*).
// /inp and /recommend take the EcomHubInput POST body; the GET endpoints
// take no parameters at all - the server already has context from /inp.
// Verified against a known working reference implementation.
class EcomAdHandlerClient {
  final String ecomHubBaseUrl;
  final String ecomHubBuyUrl;
  final String ecomHubRecommendUrl;
  final String ecomHubRecommendationsUrl;
  // Circuit breaker protecting AH network calls
  final circuitBreaker = CircuitBreaker(name: 'ecom_ad_handler', failureThreshold: 4, recoveryTimeout: const Duration(seconds: 30));

  EcomAdHandlerClient({
    String? ecomHubBaseUrl,
    String? ecomHubBuyUrl,
    String? ecomHubRecommendUrl,
    String? ecomHubRecommendationsUrl,
    String? ecomHubLifebalanceUrl,
    String? ecomHubAnalyzeUrl,
  }) : ecomHubBaseUrl = ecomHubBaseUrl ?? (EnvConfig.ecomHubBaseUrl.isNotEmpty ? EnvConfig.ecomHubBaseUrl : 'https://myna.glassdata.ai/api/v1/ah/inp'),
       ecomHubBuyUrl = ecomHubBuyUrl ?? (EnvConfig.ecomHubBuyUrl.isNotEmpty ? EnvConfig.ecomHubBuyUrl : 'https://myna.glassdata.ai/api/v1/ah/buy'),
       ecomHubRecommendUrl = ecomHubRecommendUrl ?? (EnvConfig.ecomHubRecommendUrl.isNotEmpty ? EnvConfig.ecomHubRecommendUrl : 'https://myna.glassdata.ai/api/v1/ah/recommend'),
       ecomHubRecommendationsUrl = ecomHubRecommendationsUrl ?? (EnvConfig.ecomHubRecommendationsUrl.isNotEmpty ? EnvConfig.ecomHubRecommendationsUrl : 'https://myna.glassdata.ai/api/v1/ah/recommendations');

  /// Ingests multimodal/behavioral telemetry context to prime the middleware.
  Future<dynamic> postInput(EcomHubInput input) => _postJson(ecomHubBaseUrl, input.toJson());

  /// Instant live product recommendations with link, image, price, rating and delivery.
  Future<dynamic> getInstantRecommendations({
    required String product,
    double relevanceScore = 0.95,
    String? userId,
    int limit = 6,
    String locationType = 'Urban',
  }) {
    final body = {
      'product': product,
      'relevance_score': relevanceScore,
      'user_id': userId ?? 'u_live',
      'limit': limit,
      'location_type': locationType,
    };
    return _postJson(ecomHubRecommendationsUrl, body);
  }

  /// Polls organic feed for the visual gaze / detected target.
  Future<dynamic> getBuy({String? userId, String? className, EcomHubInput? legacyInput}) {
    final targetClass = className ?? (legacyInput?.topSalientObjects.isNotEmpty == true ? legacyInput!.topSalientObjects.first.className : null);
    final targetUser = userId ?? legacyInput?.userId?.toString() ?? 'u_live';
    final queryParams = <String, String>{
      'user_id': targetUser,
      if (targetClass != null && targetClass.isNotEmpty) 'class_name': targetClass,
    };
    final uri = Uri.parse(ecomHubBuyUrl).replace(queryParameters: queryParams);
    return _get(uri.toString());
  }

  /// Polls sponsored feed for the user.
  Future<dynamic> getRecommend({String? userId}) {
    final queryParams = <String, String>{
      'user_id': userId ?? 'u_live',
    };
    final uri = Uri.parse(ecomHubRecommendUrl).replace(queryParameters: queryParams);
    return _get(uri.toString());
  }

  // Deprecated/no-op fallbacks to preserve backward compatibility if called
  Future<dynamic> getAnalyze() async => null;
  Future<dynamic> getLifebalance() async => null;
  Future<dynamic> postRecommend(EcomHubInput input) async => null;

  Future<dynamic> _get(String url) {
    return circuitBreaker.execute(() async {
      final uri = Uri.parse(url);
      AppLogger.log('AH_REQUEST', 'GET $uri');
      final response = await http.get(uri);
      AppLogger.log('AH_RESPONSE', '${response.statusCode} ${response.body}');
      return _decode(response);
    });
  }

  Future<dynamic> _postJson(String url, Map<String, dynamic> body) {
    return circuitBreaker.execute(() async {
      final uri = Uri.parse(url);
      final encodedBody = jsonEncode(body);
      AppLogger.log('AH_REQUEST', 'POST $uri $encodedBody');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: encodedBody,
      );
      AppLogger.log('AH_RESPONSE', '${response.statusCode} ${response.body}');
      return _decode(response);
    });
  }

  dynamic _decode(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw http.ClientException('AH request failed: HTTP ${response.statusCode}: ${response.body}');
    }
    return jsonDecode(response.body);
  }
}
