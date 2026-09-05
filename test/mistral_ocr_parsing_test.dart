import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:inventory_analyzer/models/import_models.dart';
import 'package:inventory_analyzer/services/mistral_ocr_service.dart';

Uint8List _bytesOf(Object json) => Uint8List.fromList(utf8.encode(jsonEncode(json)));

void main() {
  final service = const MistralOcrService();

  group('MistralOcrService.parseResponseBytes — valid responses', () {
    test('produces one ExtractedRow per annotated item, with correct field mapping', () {
      final annotation = jsonEncode({
        'document_type': 'invoice',
        'invoice_number': '123',
        'date': '2026-09-01',
        'customer': null,
        'branch': null,
        'sales_rep': null,
        'items': [
          {
            'product_name': 'منظف أرضيات',
            'quantity': '10',
            'unit': 'كرتون',
            'purchase_price': '500',
            'sale_price': '650',
            'sales': null,
            'returns': null,
            'production_date': null,
            'expiry_date': null,
            'category': null,
            'confidence': 0.92,
          },
        ],
        'subtotal': null,
        'discount': null,
        'grand_total': null,
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
      final name = row.cellOf(FieldType.productName);
      expect(name?.value, 'منظف أرضيات');
      expect(name?.confidence, closeTo(0.92, 0.0001));
      expect(row.cellOf(FieldType.quantity)?.value, '10');
      expect(row.cellOf(FieldType.price)?.value, '500');
      expect(row.cellOf(FieldType.salePrice)?.value, '650');
      // حقول null في JSON لا تُضاف كخلايا فارغة (لا اختراع بيانات — القسم ٩)
      expect(row.cellOf(FieldType.category), isNull);
    });

    test('confidence > 1 is treated as a 0-100 scale and normalized', () {
      final annotation = jsonEncode({
        'document_type': null, 'invoice_number': null, 'date': null, 'customer': null,
        'branch': null, 'sales_rep': null, 'subtotal': null, 'discount': null, 'grand_total': null,
        'items': [
          {
            'product_name': 'صنف',
            'quantity': '1',
            'unit': null, 'purchase_price': null, 'sale_price': null, 'sales': null,
            'returns': null, 'production_date': null, 'expiry_date': null, 'category': null,
            'confidence': 92, // 0-100 بدل 0-1
          },
        ],
      });
      final body = _bytesOf({'pages': [], 'document_annotation': annotation});
      final result = service.parseResponseBytes(body);
      expect(result.success, isTrue);
      expect(result.rows.first.cellOf(FieldType.productName)!.confidence, closeTo(0.92, 0.0001));
    });

    test('multiple items produce multiple rows in order', () {
      final annotation = jsonEncode({
        'document_type': null, 'invoice_number': null, 'date': null, 'customer': null,
        'branch': null, 'sales_rep': null, 'subtotal': null, 'discount': null, 'grand_total': null,
        'items': [
          {'product_name': 'أ', 'quantity': '1', 'confidence': 0.9, 'unit': null, 'purchase_price': null, 'sale_price': null, 'sales': null, 'returns': null, 'production_date': null, 'expiry_date': null, 'category': null},
          {'product_name': 'ب', 'quantity': '2', 'confidence': 0.9, 'unit': null, 'purchase_price': null, 'sale_price': null, 'sales': null, 'returns': null, 'production_date': null, 'expiry_date': null, 'category': null},
        ],
      });
      final body = _bytesOf({'pages': [], 'document_annotation': annotation});
      final result = service.parseResponseBytes(body);
      expect(result.rows.length, 2);
      expect(result.rows[0].cellOf(FieldType.productName)?.value, 'أ');
      expect(result.rows[1].cellOf(FieldType.productName)?.value, 'ب');
    });
  });

  group('MistralOcrService.parseResponseBytes — failure paths (never crashes)', () {
    test('missing document_annotation field → failure, not an exception', () {
      final body = _bytesOf({'pages': []});
      expect(() => service.parseResponseBytes(body), returnsNormally);
      expect(service.parseResponseBytes(body).success, isFalse);
    });

    test('document_annotation as null → failure', () {
      final body = _bytesOf({'pages': [], 'document_annotation': null});
      expect(service.parseResponseBytes(body).success, isFalse);
    });

    test('document_annotation is a malformed JSON string → failure, not an exception', () {
      final body = _bytesOf({'pages': [], 'document_annotation': '{not valid json!!'});
      expect(() => service.parseResponseBytes(body), returnsNormally);
      expect(service.parseResponseBytes(body).success, isFalse);
    });

    test('document_annotation JSON decodes to a non-object (bare list) → failure', () {
      final body = _bytesOf({'pages': [], 'document_annotation': jsonEncode([1, 2, 3])});
      expect(service.parseResponseBytes(body).success, isFalse);
    });

    test('items missing entirely → failure (no rows fabricated)', () {
      final annotation = jsonEncode({'document_type': 'invoice'});
      final body = _bytesOf({'pages': [], 'document_annotation': annotation});
      expect(service.parseResponseBytes(body).success, isFalse);
    });

    test('items present but empty → failure', () {
      final annotation = jsonEncode({'items': []});
      final body = _bytesOf({'pages': [], 'document_annotation': annotation});
      expect(service.parseResponseBytes(body).success, isFalse);
    });

    test('whole body is not a JSON object (bare array) → failure, not an exception', () {
      final body = _bytesOf([1, 2, 3]);
      expect(() => service.parseResponseBytes(body), returnsNormally);
      expect(service.parseResponseBytes(body).success, isFalse);
    });
  });
}
