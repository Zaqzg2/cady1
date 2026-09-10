import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:inventory_analyzer/services/ocr_space_api_client.dart';

void main() {
  final client = const OcrSpaceApiClient();

  group('OcrSpaceApiClient.classifyResponse — HTTP status path', () {
    test('real HTTP 401 from a proxy/gateway → invalidKey', () {
      final r = http.Response('{}', 401);
      expect(client.classifyResponse(r).status, OcrSpaceConnectionStatus.invalidKey);
    });

    test('real HTTP 429 → rateLimited', () {
      final r = http.Response('{}', 429);
      expect(client.classifyResponse(r).status, OcrSpaceConnectionStatus.rateLimited);
    });

    test('real HTTP 500 → serverError', () {
      final r = http.Response('{}', 500);
      expect(client.classifyResponse(r).status, OcrSpaceConnectionStatus.serverError);
    });
  });

  group('OcrSpaceApiClient.classifyResponse — the always-200 body-error path (verified real API behavior)', () {
    test('HTTP 200 + IsErroredOnProcessing=false → valid', () {
      final body = jsonEncode({'IsErroredOnProcessing': false, 'ParsedResults': []});
      final r = http.Response(body, 200);
      expect(client.classifyResponse(r).status, OcrSpaceConnectionStatus.valid);
    });

    test('HTTP 200 + invalid API key error message in body → invalidKey (not "valid")', () {
      // مطابق فعليًا لصيغة خطأ حقيقية موثَّقة: "E550: Invalid free api key"
      final body = jsonEncode({
        'IsErroredOnProcessing': true,
        'ErrorMessage': ['E550: Invalid free api key'],
        'OCRExitCode': 4,
      });
      final r = http.Response(body, 200);
      expect(client.classifyResponse(r).status, OcrSpaceConnectionStatus.invalidKey);
    });

    test('HTTP 200 + rate limit message in body → rateLimited', () {
      final body = jsonEncode({
        'IsErroredOnProcessing': true,
        'ErrorMessage': 'You have exceeded the request limit for your account',
        'OCRExitCode': 4,
      });
      final r = http.Response(body, 200);
      expect(client.classifyResponse(r).status, OcrSpaceConnectionStatus.rateLimited);
    });

    test('HTTP 200 + unrecognized processing error → badRequest (not silently "valid")', () {
      final body = jsonEncode({
        'IsErroredOnProcessing': true,
        'ErrorMessage': ['Cannot process this file'],
        'OCRExitCode': 3,
      });
      final r = http.Response(body, 200);
      expect(client.classifyResponse(r).status, OcrSpaceConnectionStatus.badRequest);
    });

    test('HTTP 200 with malformed (non-JSON) body → serverError, never crashes', () {
      final r = http.Response('not json at all {{{', 200);
      expect(() => client.classifyResponse(r), returnsNormally);
      expect(client.classifyResponse(r).status, OcrSpaceConnectionStatus.serverError);
    });

    test('ErrorMessage as a bare string (not a list) is handled safely', () {
      final body = jsonEncode({'IsErroredOnProcessing': true, 'ErrorMessage': 'some error', 'OCRExitCode': 3});
      final r = http.Response(body, 200);
      expect(() => client.classifyResponse(r), returnsNormally);
    });
  });

  group('OcrSpaceApiClient messages', () {
    test('every status has a non-empty Arabic message', () {
      for (final status in OcrSpaceConnectionStatus.values) {
        expect(client.messageFor(status).trim().isNotEmpty, isTrue, reason: 'status: $status');
      }
    });
  });

  group('empty key', () {
    test('testConnection with empty key returns noKey without any HTTP call', () async {
      final result = await client.testConnection('');
      expect(result.status, OcrSpaceConnectionStatus.noKey);
    });
  });
}
