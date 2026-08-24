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
  final String ecomHubLifebalanceUrl;
  final String ecomHubAnalyzeUrl;
  // Stricter than the other engines' default (4 failures / 30s) - one
  // pipeline tick fans out to 5 HTTP calls here, so failures accumulate faster.
  final circuitBreaker = CircuitBreaker(name: 'ecom_ad_handler', failureThreshold: 4, recoveryTimeout: const Duration(seconds: 30));

  EcomAdHandlerClient({
    String? ecomHubBaseUrl,
    String? ecomHubBuyUrl,
    String? ecomHubRecommendUrl,
    String? ecomHubLifebalanceUrl,
    String? ecomHubAnalyzeUrl,
  }) : ecomHubBaseUrl = ecomHubBaseUrl ?? EnvConfig.ecomHubBaseUrl,
       ecomHubBuyUrl = ecomHubBuyUrl ?? EnvConfig.ecomHubBuyUrl,
       ecomHubRecommendUrl = ecomHubRecommendUrl ?? EnvConfig.ecomHubRecommendUrl,
       ecomHubLifebalanceUrl = ecomHubLifebalanceUrl ?? EnvConfig.ecomHubLifebalanceUrl,
       ecomHubAnalyzeUrl = ecomHubAnalyzeUrl ?? EnvConfig.ecomHubAnalyzeUrl;

  Future<dynamic> postInput(EcomHubInput input) => _post(ecomHubBaseUrl, input);
  Future<dynamic> postRecommend(EcomHubInput input) => _post(ecomHubRecommendUrl, input);
  // /buy needs the same body /inp gets - a bodyless GET here came back with
  // empty organic_feed/sponsored_feed even right after a matching /inp call;
  // sending the same EcomHubInput JSON on the GET is what a manual Postman
  // test confirmed actually returns matched product links.
  Future<dynamic> getBuy(EcomHubInput input) => _getWithBody(ecomHubBuyUrl, input);
  Future<dynamic> getRecommend() => _get(ecomHubRecommendUrl);
  Future<dynamic> getAnalyze() => _get(ecomHubAnalyzeUrl);
  Future<dynamic> getLifebalance() => _get(ecomHubLifebalanceUrl);

  Future<dynamic> _get(String url) {
    return circuitBreaker.execute(() async {
      final uri = Uri.parse(url);
      AppLogger.log('AH_REQUEST', 'GET $uri');
      final response = await http.get(uri);
      AppLogger.log('AH_RESPONSE', '${response.statusCode} ${response.body}');
      return _decode(response);
    });
  }

  Future<dynamic> _getWithBody(String url, EcomHubInput input) {
    return circuitBreaker.execute(() async {
      final uri = Uri.parse(url);
      final encodedBody = jsonEncode(input.toJson());
      AppLogger.log('AH_REQUEST', 'GET $uri $encodedBody');
      final request = http.Request('GET', uri)
        ..headers['Content-Type'] = 'application/json'
        ..body = encodedBody;
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      AppLogger.log('AH_RESPONSE', '${response.statusCode} ${response.body}');
      return _decode(response);
    });
  }

  Future<dynamic> _post(String url, EcomHubInput input) {
    return circuitBreaker.execute(() async {
      final uri = Uri.parse(url);
      final encodedBody = jsonEncode(input.toJson());
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
