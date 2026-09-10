import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:inventory_analyzer/models/import_models.dart';
import 'package:inventory_analyzer/services/mistral_ocr_service.dart';

Uint8List _bytesOf(Object json) => Uint8List.fromList(utf8.encode(jsonEncode(json)));

Map<String, dynamic> _item(Map<String, dynamic> overrides) => {
      'product_name': null,
      'item_number': null,
      'barcode': null,
      'unit': null,
      'quantity': null,
      'sales': null,
      'returns': null,
      'production_date': null,
      'expiry_date': null,
      'branch': null,
      'category': null,
      ...overrides,
    };

void main() {
  final service = const MistralOcrService();

  group('MistralOcrService.parseResponseBytes — valid responses', () {
    test('produces one ExtractedRow per annotated item, no price fields exist', () {
      final annotation = jsonEncode({
        'document_type': 'inventory_sheet',
        'invoice_number': null,
        'date': '2026-09-01',
        'customer': null,
        'branch': null,
        'sales_rep': null,
        'items': [
          _item({
            'product_name': 'منظف أرضيات',
            'item_number': 'A-102',
            'barcode': '6291012345',
            'unit': 'كرتون',
            'quantity': '10',
            'confidence': 0.92,
          }),
        ],
      });
      final body = _bytesOf({
        'pages': [
          {'confidence_scores': {'average_page_confidence_score': 0.88}},
        ],
        'document_annotation': annotation,
        'model': 'mistral-ocr-2503-completion',
      });

      final result = service.parseResponseBytes(body);

      expect(result.success, isTrue);
      expect(result.rows.length, 1);
      expect(result.pageConfidenceAvg, closeTo(0.88, 0.0001));

      final row = result.rows.first;
      expect(row.cellOf(FieldType.productName)?.value, 'منظف أرضيات');
      expect(row.cellOf(FieldType.productName)?.confidence, closeTo(0.92, 0.0001));
      expect(row.cellOf(FieldType.itemNumber)?.value, 'A-102');
      expect(row.cellOf(FieldType.barcode)?.value, '6291012345');
      expect(row.cellOf(FieldType.unit)?.value, 'كرتون');
      expect(row.cellOf(FieldType.quantity)?.value, '10');
    });

    test('confidence > 1 is treated as a 0-100 scale and normalized', () {
      final annotation = jsonEncode({
        'items': [_item({'product_name': 'صنف', 'quantity': '1', 'confidence': 92})],
      });
      final body = _bytesOf({'pages': [], 'document_annotation': annotation});
      final result = service.parseResponseBytes(body);
      expect(result.success, isTrue);
      expect(result.rows.first.cellOf(FieldType.productName)!.confidence, closeTo(0.92, 0.0001));
    });

    test('multiple items produce multiple rows in order', () {
      final annotation = jsonEncode({
        'items': [
          _item({'product_name': 'أ', 'quantity': '1', 'confidence': 0.9}),
          _item({'product_name': 'ب', 'quantity': '2', 'confidence': 0.9}),
        ],
      });
      final body = _bytesOf({'pages': [], 'document_annotation': annotation});
      final result = service.parseResponseBytes(body);
      expect(result.rows.length, 2);
      expect(result.rows[0].cellOf(FieldType.productName)?.value, 'أ');
      expect(result.rows[1].cellOf(FieldType.productName)?.value, 'ب');
    });

    test('sales and returns map correctly and are distinct from quantity', () {
      final annotation = jsonEncode({
        'items': [_item({'product_name': 'صنف', 'quantity': '50', 'sales': '30', 'returns': '2', 'confidence': 0.9})],
      });
      final body = _bytesOf({'pages': [], 'document_annotation': annotation});
      final row = service.parseResponseBytes(body).rows.first;
      expect(row.cellOf(FieldType.quantity)?.value, '50');
      expect(row.cellOf(FieldType.sales)?.value, '30');
      expect(row.cellOf(FieldType.returns)?.value, '2');
    });
  });

  group('MistralOcrService.parseResponseBytes — failure paths (never crashes)', () {
    test('missing document_annotation field → failure, not an exception', () {
      final body = _bytesOf({'pages': []});
      expect(() => service.parseResponseBytes(body), returnsNormally);
      expect(service.parseResponseBytes(body).success, isFalse);
    });

    test('document_annotation is a malformed JSON string → failure, not an exception', () {
      final body = _bytesOf({'pages': [], 'document_annotation': '{not valid json!!'});
      expect(() => service.parseResponseBytes(body), returnsNormally);
      expect(service.parseResponseBytes(body).success, isFalse);
    });

    test('document_annotation decodes to a non-object (bare list) → failure', () {
      final body = _bytesOf({'pages': [], 'document_annotation': jsonEncode([1, 2, 3])});
      expect(service.parseResponseBytes(body).success, isFalse);
    });

    test('items missing entirely → failure (no rows fabricated)', () {
      final body = _bytesOf({'pages': [], 'document_annotation': jsonEncode({'document_type': 'invoice'})});
      expect(service.parseResponseBytes(body).success, isFalse);
    });

    test('items present but empty → failure', () {
      final body = _bytesOf({'pages': [], 'document_annotation': jsonEncode({'items': []})});
      expect(service.parseResponseBytes(body).success, isFalse);
    });

    test('whole body is not a JSON object (bare array) → failure, not an exception', () {
      final body = _bytesOf([1, 2, 3]);
      expect(() => service.parseResponseBytes(body), returnsNormally);
      expect(service.parseResponseBytes(body).success, isFalse);
    });
  });
}
