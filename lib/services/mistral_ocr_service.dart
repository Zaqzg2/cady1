import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/import_models.dart';
import 'mistral_api_client.dart';

class MistralOcrParseResult {
  final bool success;
  final String? error;
  final List<ExtractedRow> rows;
  final double? pageConfidenceAvg;

  MistralOcrParseResult._({required this.success, this.error, this.rows = const [], this.pageConfidenceAvg});

  factory MistralOcrParseResult.success(List<ExtractedRow> rows, {double? pageConfidenceAvg}) =>
      MistralOcrParseResult._(success: true, rows: rows, pageConfidenceAvg: pageConfidenceAvg);

  factory MistralOcrParseResult.failure(String error) => MistralOcrParseResult._(success: false, error: error);
}

/// طبقة OCR / Annotation لـ Mistral. ⚠️ Schema هنا مطابق حرفيًا لـFieldType
/// الحالي في import_models.dart — **بلا أي حقل سعر** (التطبيق ألغى تتبّع
/// السعر عبر الاستيراد العام لصالح نظام Purchases المستقل). لا تُعِد إضافة
/// purchase_price/sale_price هنا إلا إذا عاد FieldType نفسه لدعمها أولًا.
class MistralOcrService {
  final MistralApiClient _client;
  const MistralOcrService({MistralApiClient client = const MistralApiClient()}) : _client = client;

  /// يُعرَّض علنًا عمدًا — استخدمه MistralOcrEngine لبناء OcrExtractionResult
  /// (اسم الطراز). ⚠️ غيابه في محاولة سابقة (راجع سجلات CI) سبّب خطأ ترجمة
  /// حقيقيًا؛ أُضيف هنا تحديدًا لإصلاح ذلك.
  MistralOcrConfig get config => _client.config;

  static const maxAnnotationPages = 8; // حد Mistral الموثَّق لـDocument Annotation

  static const _fieldKeyToType = {
    'product_name': FieldType.productName,
    'item_number': FieldType.itemNumber,
    'barcode': FieldType.barcode,
    'unit': FieldType.unit,
    'quantity': FieldType.quantity,
    'sales': FieldType.sales,
    'returns': FieldType.returns,
    'production_date': FieldType.productionDate,
    'expiry_date': FieldType.expiryDate,
    'branch': FieldType.branch,
    'category': FieldType.category,
  };

  Future<MistralOcrParseResult> extract(
    String apiKey,
    Uint8List bytes, {
    required String mimeType,
    String? contextHint,
  }) async {
    final isDocLike = mimeType == 'application/pdf' ||
        mimeType == 'application/vnd.openxmlformats-officedocument.wordprocessingml.document' ||
        mimeType == 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
    final dataUri = 'data:$mimeType;base64,${base64Encode(bytes)}';

    final body = {
      'model': config.model,
      'document': isDocLike
          ? {'type': 'document_url', 'document_url': dataUri}
          : {'type': 'image_url', 'image_url': dataUri},
      'confidence_scores_granularity': 'page',
      'document_annotation_format': {
        'type': 'json_schema',
        'json_schema': {'name': 'inventory_document', 'schema': _annotationSchema, 'strict': true},
      },
      'document_annotation_prompt': _annotationPrompt(contextHint),
      if (isDocLike) 'pages': List.generate(maxAnnotationPages, (i) => i),
    };

    http.Response response;
    try {
      response = await _client.postOcr(apiKey, body);
    } catch (e) {
      return MistralOcrParseResult.failure(_client.classifyException(e).messageAr);
    }

    final health = _client.classifyHttpResponse(response);
    if (health.status != MistralConnectionStatus.valid) {
      return MistralOcrParseResult.failure(health.messageAr);
    }

    try {
      return parseResponseBytes(response.bodyBytes);
    } catch (e) {
      debugPrint('MistralOcrService: فشل تحليل الاستجابة: $e');
      return MistralOcrParseResult.failure(
        'وصلت استجابة من Mistral لكن تعذّر فهم محتواها. جرّب مرة أخرى، أو استخدم استيراد Excel/CSV.',
      );
    }
  }

  /// عام عمدًا — قابل للاختبار مباشرة بلا نداء شبكة فعلي.
  MistralOcrParseResult parseResponseBytes(Uint8List bodyBytes) {
    final decoded = jsonDecode(utf8.decode(bodyBytes));
    if (decoded is! Map) return MistralOcrParseResult.failure('استجابة غير متوقعة من Mistral.');

    double? pageConfidenceAvg;
    final pages = decoded['pages'];
    if (pages is List && pages.isNotEmpty) {
      final scores = <double>[];
      for (final p in pages) {
        if (p is Map && p['confidence_scores'] is Map) {
          final avg = (p['confidence_scores'] as Map)['average_page_confidence_score'];
          if (avg is num) scores.add(avg.toDouble());
        }
      }
      if (scores.isNotEmpty) pageConfidenceAvg = scores.reduce((a, b) => a + b) / scores.length;
    }

    final annotationRaw = decoded['document_annotation'];
    if (annotationRaw is! String || annotationRaw.trim().isEmpty) {
      return MistralOcrParseResult.failure('لم يتمكن Mistral من التعرّف على أي بيانات واضحة في هذا المستند.');
    }

    final Map<String, dynamic> annotation;
    try {
      final parsed = jsonDecode(annotationRaw);
      if (parsed is! Map<String, dynamic>) {
        return MistralOcrParseResult.failure('لم يتمكن Mistral من التعرّف على أي بيانات واضحة في هذا المستند.');
      }
      annotation = parsed;
    } catch (_) {
      return MistralOcrParseResult.failure('لم يتمكن Mistral من التعرّف على أي بيانات واضحة في هذا المستند.');
    }

    final rows = _rowsFromAnnotation(annotation);
    if (rows.isEmpty) {
      return MistralOcrParseResult.failure('لم يتمكن Mistral من التعرّف على أي بيانات واضحة في هذا المستند.');
    }
    return MistralOcrParseResult.success(rows, pageConfidenceAvg: pageConfidenceAvg);
  }

  List<ExtractedRow> _rowsFromAnnotation(Map<String, dynamic> annotation) {
    final itemsRaw = annotation['items'];
    if (itemsRaw is! List) return [];

    final rows = <ExtractedRow>[];
    for (var r = 0; r < itemsRaw.length; r++) {
      final itemMap = itemsRaw[r];
      if (itemMap is! Map) continue;
      final cells = <ExtractedCell>[];
      final selfReportedConfidence = _asClampedConfidence(itemMap['confidence']);

      for (final entry in _fieldKeyToType.entries) {
        final value = itemMap[entry.key];
        if (value == null) continue;
        final valueStr = value.toString().trim();
        if (valueStr.isEmpty || valueStr.toLowerCase() == 'null') continue;
        cells.add(ExtractedCell(fieldType: entry.value, value: valueStr, confidence: selfReportedConfidence, rowNumber: r + 1));
      }

      if (cells.isNotEmpty) rows.add(ExtractedRow(cells: cells));
    }
    return rows;
  }

  double _asClampedConfidence(Object? raw) {
    num? n;
    if (raw is num) n = raw;
    if (raw is String) n = num.tryParse(raw);
    if (n == null) return 0.70;
    final v = n > 1 ? n / 100 : n;
    return v.clamp(0.0, 1.0).toDouble();
  }

  String _annotationPrompt(String? contextHint) {
    return '''
You are extracting structured inventory data (quantities only — NEVER prices) from an Arabic document (printed and/or handwritten). ${contextHint ?? ''}

Arabic instructions / تعليمات بالعربية:
- اقرأ النص العربي كما هو، بلا ترجمة أسماء المنتجات.
- حوّل كل الأرقام إلى Western digits (0-9).
- هذا التطبيق لا يتتبّع الأسعار إطلاقًا — لا تحاول استخراج أي سعر أو تكلفة، فقط الكمية ورقم الصنف/الباركود إن وُجدا.
- ميّز بدقة بين الكمية (quantity) والصرف/المبيعات الكمية (sales) والمرتجع (returns) — لا تخلط بينها.
- التزم بالتاريخ كما يظهر، ثم طبّعه إلى YYYY-MM-DD إن كان واضحًا فقط.
- استخدم null لأي قيمة غير ظاهرة بوضوح. لا تخترع أو تخمّن.
- عامل الكتابة اليدوية بحذر إضافي — إن لم تكن واثقًا، اجعل confidence أقل من 0.60 بدل التخمين.

English instructions:
- Preserve Arabic product names exactly as written; never translate them.
- Do NOT extract or invent any price/cost value — this app intentionally tracks quantities only.
- Distinguish quantity vs. sales vs. returns precisely.
- Never invent or guess a missing value — use null instead.
- Set "confidence" (0.0-1.0) honestly per item; lower it substantially for handwriting or ambiguity.
''';
  }

  static const Map<String, dynamic> _annotationSchema = {
    'type': 'object',
    'properties': {
      'document_type': {'type': ['string', 'null']},
      'date': {'type': ['string', 'null']},
      'branch_name': {'type': ['string', 'null']},
      'items': {
        'type': 'array',
        'items': {
          'type': 'object',
          'properties': {
            'product_name': {'type': ['string', 'null']},
            'item_number': {'type': ['string', 'null']},
            'barcode': {'type': ['string', 'null']},
            'unit': {'type': ['string', 'null']},
            'quantity': {'type': ['string', 'null']},
            'sales': {'type': ['string', 'null']},
            'returns': {'type': ['string', 'null']},
            'production_date': {'type': ['string', 'null']},
            'expiry_date': {'type': ['string', 'null']},
            'branch': {'type': ['string', 'null']},
            'category': {'type': ['string', 'null']},
            'confidence': {'type': ['number', 'null']},
          },
          'required': [
            'product_name', 'item_number', 'barcode', 'unit', 'quantity', 'sales',
            'returns', 'production_date', 'expiry_date', 'branch', 'category', 'confidence',
          ],
          'additionalProperties': false,
        },
      },
    },
    'required': ['document_type', 'date', 'branch_name', 'items'],
    'additionalProperties': false,
  };
}
