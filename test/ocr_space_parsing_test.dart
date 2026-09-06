import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:inventory_analyzer/models/import_models.dart';
import 'package:inventory_analyzer/services/ocr_space_service.dart';

Uint8List _bytesOf(Object json) => Uint8List.fromList(utf8.encode(jsonEncode(json)));

void main() {
  final service = const OcrSpaceService();

  group('OcrSpaceService.parseResponseBytes — valid responses', () {
    test('one line with product name + a number → productName/quantity cells', () {
      final body = _bytesOf({
        'IsErroredOnProcessing': false,
        'ParsedResults': [
          {'ParsedText': 'صابون سائل 10'},
        ],
      });
      final result = service.parseResponseBytes(body);
      expect(result.success, isTrue);
      expect(result.rows.length, 1);
      final row = result.rows.first;
      expect(row.cellOf(FieldType.productName)?.value, 'صابون سائل');
      expect(row.cellOf(FieldType.quantity)?.value, '10');
    });

    test('every cell from OCR.space is honestly marked confidenceSource=unavailable', () {
      final body = _bytesOf({
        'IsErroredOnProcessing': false,
        'ParsedResults': [
          {'ParsedText': 'منظف زجاج 3'},
        ],
      });
      final result = service.parseResponseBytes(body);
      for (final cell in result.rows.first.cells) {
        expect(cell.confidenceSource, 'unavailable');
      }
      expect(result.rows.first.confidenceUnavailable, isTrue);
    });

    test('multiple lines → multiple rows, blank and number-only lines skipped', () {
      final body = _bytesOf({
        'IsErroredOnProcessing': false,
        'ParsedResults': [
          {'ParsedText': 'صابون سائل 10\n\n123\nشامبو أطفال 5'},
        ],
      });
      final result = service.parseResponseBytes(body);
      expect(result.rows.length, 2);
      expect(result.rows[0].cellOf(FieldType.productName)?.value, 'صابون سائل');
      expect(result.rows[1].cellOf(FieldType.productName)?.value, 'شامبو أطفال');
    });

    test('a line with no numbers still yields a productName-only row', () {
      final body = _bytesOf({
        'ParsedResults': [
          {'ParsedText': 'صنف بلا كمية مكتوبة'},
        ],
      });
      final row = service.parseResponseBytes(body).rows.first;
      expect(row.cellOf(FieldType.productName)?.value, 'صنف بلا كمية مكتوبة');
      expect(row.cellOf(FieldType.quantity), isNull);
    });

    test('multi-page result tags each row with the correct pageNumber', () {
      final body = _bytesOf({
        'ParsedResults': [
          {'ParsedText': 'صنف الصفحة الأولى 1'},
          {'ParsedText': 'صنف الصفحة الثانية 2'},
        ],
      });
      final result = service.parseResponseBytes(body);
      expect(result.rows.length, 2);
      expect(result.rows[0].cellOf(FieldType.productName)?.pageNumber, 1);
      expect(result.rows[1].cellOf(FieldType.productName)?.pageNumber, 2);
    });
  });

  group('OcrSpaceService.parseResponseBytes — failure paths (never crashes)', () {
    test('ParsedResults missing entirely → failure, not an exception', () {
      final body = _bytesOf({'IsErroredOnProcessing': false});
      expect(() => service.parseResponseBytes(body), returnsNormally);
      expect(service.parseResponseBytes(body).success, isFalse);
    });

    test('ParsedResults is an empty list → failure', () {
      final body = _bytesOf({'ParsedResults': []});
      expect(service.parseResponseBytes(body).success, isFalse);
    });

    test('ParsedText is empty/whitespace-only → failure (no fabricated rows)', () {
      final body = _bytesOf({
        'ParsedResults': [
          {'ParsedText': '   '},
        ],
      });
      expect(service.parseResponseBytes(body).success, isFalse);
    });

    test('a page entry that is not a Map is skipped safely rather than crashing', () {
      final body = _bytesOf({'ParsedResults': ['not a map', 3, null]});
      expect(() => service.parseResponseBytes(body), returnsNormally);
      expect(service.parseResponseBytes(body).success, isFalse);
    });

    test('body is not a JSON object at all → failure, not an exception', () {
      final body = _bytesOf('just a string');
      expect(() => service.parseResponseBytes(body), returnsNormally);
      expect(service.parseResponseBytes(body).success, isFalse);
    });
  });
}
