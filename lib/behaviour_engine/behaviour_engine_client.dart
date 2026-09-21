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

  Future<Map<String, dynamic>> process(dynamic input) {
    return circuitBreaker.execute(() async {
      final url = Uri.parse(behaviourEnginePostUrl);
      final Map<String, dynamic> payload;
      if (input is Map<String, dynamic>) {
        payload = input;
      } else if (input is BehaviourEngineInput) {
        payload = input.toJson();
      } else if (input is Map) {
        payload = Map<String, dynamic>.from(input);
      } else {
        payload = {'data': input.toString()};
      }
      final body = jsonEncode(payload);
      AppLogger.log('BE_REQUEST', body);

      final response = await http.post(url, headers: {'Content-Type': 'application/json'}, body: body);
      AppLogger.log('BE_RESPONSE', '${response.statusCode} ${response.body}');

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw http.ClientException('BE /process failed: HTTP ${response.statusCode}: ${response.body}');
      }
      return jsonDecode(response.body) as Map<String, dynamic>;
    });
  }

  Future<void> postLocation({
    required dynamic userId,
    required String label,
    required double lat,
    required double lon,
    int radiusM = 100,
  }) async {
    final baseUrl = behaviourEnginePostUrl.replaceAll(RegExp(r'/process/?$'), '');
    final url = Uri.parse('$baseUrl/locations/$userId');
    final payload = jsonEncode({
      'label': label,
      'lat': lat,
      'lon': lon,
      'radius_m': radiusM,
    });
    AppLogger.log('BE_LOCATION_POST', 'POST $url -> $payload');
    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: payload,
      );
      AppLogger.log('BE_LOCATION_RESPONSE', '${response.statusCode} ${response.body}');
    } catch (e) {
      AppLogger.log('BE_LOCATION_ERROR', 'Failed to post location: $e');
    }
  }

  Future<Map<String, dynamic>?> uploadScheduleFile({
    required dynamic userId,
    required List<int> bytes,
    required String fileName,
  }) async {
    final baseUrl = behaviourEnginePostUrl.replaceAll(RegExp(r'/process/?$'), '');
    final url = Uri.parse('$baseUrl/schedule/$userId/upload');
    AppLogger.log('BE_SCHEDULE_UPLOAD', 'POST $url (file: $fileName, size: ${bytes.length} bytes)');
    try {
      final request = http.MultipartRequest('POST', url);
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: fileName,
        ),
      );
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      AppLogger.log('BE_SCHEDULE_UPLOAD_RESPONSE', '${response.statusCode} ${response.body}');
      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (response.body.isNotEmpty) {
          return jsonDecode(response.body) as Map<String, dynamic>;
        }
        return {'success': true};
      } else {
        AppLogger.log('BE_SCHEDULE_UPLOAD_ERROR', 'HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      AppLogger.log('BE_SCHEDULE_UPLOAD_ERROR', 'Failed to upload schedule file: $e');
    }
    return null;
  }

  String _normalizeUserId(dynamic userId) {
    if (userId == null) return '1';
    final str = userId.toString().trim();
    if (str.isEmpty || str == '0' || str == 'null') return '1';
    return str;
  }

  Future<List<Map<String, dynamic>>> getOwnedObjects({required dynamic userId}) async {
    final uid = _normalizeUserId(userId);
    final baseUrl = behaviourEnginePostUrl.replaceAll(RegExp(r'/process/?$'), '');
    final url = Uri.parse('$baseUrl/owned_objects/$uid');
    AppLogger.log('BE_GET_OWNED_OBJECTS', 'GET $url');
    try {
      final response = await http.get(url, headers: {'Accept': 'application/json'});
      AppLogger.log('BE_GET_OWNED_OBJECTS_RESPONSE', '${response.statusCode} ${response.body}');
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        if (decoded is List) {
          return decoded.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
        } else if (decoded is Map && decoded['owned_products'] is List) {
          return (decoded['owned_products'] as List)
              .map((p) => {'object': p.toString(), 'ownership_confidence': 1.0, 'source': 'registered'})
              .toList();
        }
      }
    } catch (e) {
      AppLogger.log('BE_GET_OWNED_OBJECTS_ERROR', 'Failed to get owned objects: $e');
    }
    return const [];
  }

  Future<Map<String, dynamic>?> addOwnedObjects({
    required dynamic userId,
    required List<String> products,
    double confidence = 0.95,
    String source = 'user_declared',
  }) async {
    if (products.isEmpty) return null;
    final uid = _normalizeUserId(userId);
    final baseUrl = behaviourEnginePostUrl.replaceAll(RegExp(r'/process/?$'), '');
    final url = Uri.parse('$baseUrl/owned_objects/$uid');

    final objectsPayload = products.map((name) => {
      'object': name,
      'ownership_confidence': confidence,
      'source': source,
    }).toList();

    final payload = jsonEncode({
      'objects': objectsPayload,
    });

    AppLogger.log('BE_ADD_OWNED_OBJECTS', 'POST $url -> $payload');
    try {
      var response = await http.post(
        url,
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: payload,
      );

      // Fallback if endpoint accepts alternative format
      if (response.statusCode == 422) {
        final fallbackPayload = jsonEncode({
          'products': products,
          'objects': products,
        });
        AppLogger.log('BE_ADD_OWNED_OBJECTS_RETRY', 'POST $url -> $fallbackPayload');
        response = await http.post(
          url,
          headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
          body: fallbackPayload,
        );
      }

      AppLogger.log('BE_ADD_OWNED_OBJECTS_RESPONSE', '${response.statusCode} ${response.body}');
      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (response.body.isNotEmpty) {
          try {
            return jsonDecode(response.body) as Map<String, dynamic>;
          } catch (_) {}
        }
        return {'success': true, 'added_count': products.length};
      } else {
        AppLogger.log('BE_ADD_OWNED_OBJECTS_ERROR', 'HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      AppLogger.log('BE_ADD_OWNED_OBJECTS_ERROR', 'Failed to add owned objects: $e');
    }
    return null;
  }

  /// Delete owned product via DELETE /api/v1/be/owned_products?user_id={uid}&product={name}
  Future<Map<String, dynamic>?> deleteOwnedObjects({
    required dynamic userId,
    required List<String> products,
  }) async {
    if (products.isEmpty) return null;
    final uid = _normalizeUserId(userId);
    final baseUrl = behaviourEnginePostUrl.replaceAll(RegExp(r'/process/?$'), '');
    int deletedCount = 0;

    for (final product in products) {
      final productsQueryUrl = Uri.parse('$baseUrl/owned_products?user_id=$uid&product=${Uri.encodeComponent(product)}');
      AppLogger.log('BE_DELETE_OWNED_PRODUCT', 'DELETE $productsQueryUrl');
      try {
        final response = await http.delete(productsQueryUrl, headers: {'Accept': 'application/json'});
        AppLogger.log('BE_DELETE_OWNED_PRODUCT_RESPONSE', '${response.statusCode} ${response.body}');
        if (response.statusCode >= 200 && response.statusCode < 300) {
          deletedCount++;
        }
      } catch (e) {
        AppLogger.log('BE_DELETE_OWNED_PRODUCT_ERROR', 'Failed to delete product: $e');
      }
    }

    return {'success': true, 'deleted_count': deletedCount};
  }

  Future<Map<String, dynamic>?> batchRemoveOwnedObjects({
    required dynamic userId,
    required List<String> products,
  }) async {
    final uid = _normalizeUserId(userId);
    String endpoint = EnvConfig.behaviourRemoveOwnedObjectsUrl;
    if (endpoint.isEmpty) {
      final baseUrl = behaviourEnginePostUrl.replaceAll(RegExp(r'/process/?$'), '');
      endpoint = '$baseUrl/owned_objects';
    }
    final url = Uri.parse(
      endpoint.contains('{user_id}')
          ? endpoint.replaceAll('{user_id}', uid)
          : '$endpoint/$uid/remove',
    );

    final payload = jsonEncode({
      'objects': products,
      'product_names': products,
      'items': products,
      'products': products,
    });
    AppLogger.log('BE_REMOVE_OWNED_OBJECTS', 'POST $url -> $payload');

    try {
      var response = await http.post(
        url,
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: payload,
      );

      // If server returns 422 Unprocessable Entity, retry with raw array
      if (response.statusCode == 422) {
        final rawListPayload = jsonEncode(products);
        AppLogger.log('BE_REMOVE_OWNED_OBJECTS_RETRY', 'POST $url -> $rawListPayload');
        response = await http.post(
          url,
          headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
          body: rawListPayload,
        );
      }

      AppLogger.log('BE_REMOVE_OWNED_OBJECTS_RESPONSE', '${response.statusCode} ${response.body}');
      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (response.body.isNotEmpty) {
          try {
            return jsonDecode(response.body) as Map<String, dynamic>;
          } catch (_) {}
        }
        return {'success': true, 'removed_count': products.length};
      } else {
        AppLogger.log('BE_REMOVE_OWNED_OBJECTS_ERROR', 'HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      AppLogger.log('BE_REMOVE_OWNED_OBJECTS_ERROR', 'Failed to remove owned objects: $e');
    }
    return null;
  }
}
