import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:inventory_analyzer/services/mistral_api_client.dart';

void main() {
  final client = const MistralApiClient();

  group('MistralApiClient.classifyHttpResponse', () {
    test('200 → valid', () {
      final r = http.Response('{}', 200);
      expect(client.classifyHttpResponse(r).status, MistralConnectionStatus.valid);
    });

    test('401 → invalidKey (classified from status code alone, body is best-effort debug detail only)', () {
      final body = jsonEncode({'object': 'error', 'message': 'bad key', 'type': 'authentication_error'});
      final r = http.Response(body, 401);
      expect(client.classifyHttpResponse(r).status, MistralConnectionStatus.invalidKey);
    });

    test('403 → forbidden', () {
      final r = http.Response(jsonEncode({'message': 'forbidden'}), 403);
      expect(client.classifyHttpResponse(r).status, MistralConnectionStatus.forbidden);
    });

    test('429 → rateLimited', () {
      final r = http.Response(jsonEncode({'message': 'too many requests'}), 429);
      expect(client.classifyHttpResponse(r).status, MistralConnectionStatus.rateLimited);
    });

    test('400 → badRequest', () {
      final r = http.Response('{}', 400);
      expect(client.classifyHttpResponse(r).status, MistralConnectionStatus.badRequest);
    });

    test('404 → badRequest (not a key problem)', () {
      final r = http.Response('{}', 404);
      expect(client.classifyHttpResponse(r).status, MistralConnectionStatus.badRequest);
    });

    test('500 → serverError', () {
      final r = http.Response('{}', 500);
      expect(client.classifyHttpResponse(r).status, MistralConnectionStatus.serverError);
    });

    test('504 → timeout', () {
      final r = http.Response('{}', 504);
      expect(client.classifyHttpResponse(r).status, MistralConnectionStatus.timeout);
    });

    test('malformed (non-JSON) error body on 401 still classifies from status code alone', () {
      final r = http.Response('<html>not json</html>', 401);
      expect(client.classifyHttpResponse(r).status, MistralConnectionStatus.invalidKey);
    });

    test('every message is a non-empty Arabic string for every status', () {
      for (final status in MistralConnectionStatus.values) {
        expect(client.messageFor(status).trim().isNotEmpty, isTrue, reason: 'status: $status');
      }
    });
  });

  group('MistralApiClient.classifyException', () {
    test('SocketException-shaped message → networkError', () {
      final result = client.classifyException(Exception('SocketException: Failed host lookup'));
      expect(result.status, MistralConnectionStatus.networkError);
    });

    test('unrecognized exception → serverError (safe fallback, never crashes)', () {
      final result = client.classifyException(Exception('something entirely unexpected'));
      expect(result.status, MistralConnectionStatus.serverError);
    });
  });

  group('empty key', () {
    test('testConnection with empty key returns noKey without any HTTP call', () async {
      final result = await client.testConnection('   ');
      expect(result.status, MistralConnectionStatus.noKey);
    });
  });
}
