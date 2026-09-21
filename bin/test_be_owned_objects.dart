// ignore_for_file: avoid_print
import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  final userId = '1';
  final baseUrl = 'https://myna.glassdata.ai/api/v1/be/owned_objects';

  print('=== 1. TEST GET /owned_objects/$userId ===');
  var getRes = await http.get(Uri.parse('$baseUrl/$userId'));
  print('GET status: ${getRes.statusCode}');
  print('GET body: ${getRes.body}');

  print('\n=== 2. TEST POST /owned_objects/$userId ===');
  final postPayload = jsonEncode({
    'objects': [
      {
        'object': 'Bingo potato chips',
        'ownership_confidence': 0.95,
        'source': 'user_declared',
      },
      {
        'object': 'cadburry',
        'ownership_confidence': 0.95,
        'source': 'user_declared',
      }
    ]
  });
  var postRes = await http.post(
    Uri.parse('$baseUrl/$userId'),
    headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
    body: postPayload,
  );
  print('POST status: ${postRes.statusCode}');
  print('POST body: ${postRes.body}');

  print('\n=== 3. TEST GET AFTER POST ===');
  getRes = await http.get(Uri.parse('$baseUrl/$userId'));
  print('GET status: ${getRes.statusCode}');
  print('GET body: ${getRes.body}');

  print('\n=== 4. TEST DELETE /owned_objects/$userId (by query param & body) ===');
  final deleteUrl = Uri.parse('$baseUrl/$userId?product=${Uri.encodeComponent('Bingo potato chips')}');
  var delRes = await http.delete(
    deleteUrl,
    headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
    body: jsonEncode({'product': 'Bingo potato chips'}),
  );
  print('DELETE query/body status: ${delRes.statusCode}');
  print('DELETE body: ${delRes.body}');

  print('\n=== 5. TEST DELETE /owned_objects/$userId/{id_or_name} ===');
  final delPathUrl = Uri.parse('$baseUrl/$userId/${Uri.encodeComponent('cadburry')}');
  var delPathRes = await http.delete(
    delPathUrl,
    headers: {'Accept': 'application/json'},
  );
  print('DELETE path status: ${delPathRes.statusCode}');
  print('DELETE path body: ${delPathRes.body}');

  print('\n=== 6. TEST GET FINAL ===');
  getRes = await http.get(Uri.parse('$baseUrl/$userId'));
  print('GET final status: ${getRes.statusCode}');
  print('GET final body: ${getRes.body}');
}
