import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/import_models.dart';
import 'mistral_api_client.dart';

/// نتيجة تحليل خام من Mistral قبل تحويلها لـ ExtractedRow — تحتفظ بمعلومات
/// إضافية (ثقة الصفحة، هل نجحت المحاولة المباشرة أم لا) يستفيد منها المتصل.
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

/// طبقة OCR / Annotation parsing المستقلة لـ Mistral (القسم ٢٧ من مواصفة
/// Mistral؛ القسم ٢٩ يسمح بالإبقاء على البنية المسطّحة الحالية لـ lib/services
/// بدل مجلد ocr/ منفصل، بنفس المبدأ). يبني الطلب (Base64 inline عبر
/// document_url/image_url — موثَّق رسميًا في docs.mistral.ai، لا حاجة لرفع
/// الملف كخطوة منفصلة) ويحوّل الاستجابة المنظَّمة إلى نماذج التطبيق الحالية
/// بلا اختراع بيانات.
class MistralOcrService {
  final MistralApiClient _client;
  const MistralOcrService({MistralApiClient client = const MistralApiClient()}) : _client = client;

  /// حد Mistral الموثَّق: Document Annotation يدعم ٨ صفحات كحد أقصى لكل طلب.
  static const maxAnnotationPages = 8;

  static const _fieldKeyToType = {
    'product_name': FieldType.productName,
    'quantity': FieldType.quantity,
    'purchase_price': FieldType.price,
    'sale_price': FieldType.salePrice,
    'sales': FieldType.sales,
    'returns': FieldType.returns,
    'production_date': FieldType.productionDate,
    'expiry_date': FieldType.expiryDate,
    'category': FieldType.category,
    // ملاحظة: "unit" لا يقابله FieldType حالي في التطبيق — يُهمَل هنا بدل
    // اختراع نوع حقل جديد يكسر شاشات أخرى (لا نغيّر النماذج إلا عند الضرورة).
  };

  /// [mimeType] يحدد شكل الطلب: مستند (PDF/DOCX) يذهب عبر document_url،
  /// وصورة عبر image_url — كلاهما بنفس data-URI Base64 (موثَّق: يعمل
  /// للاثنين معًا رغم الاسم).
  Future<MistralOcrParseResult> extract(
    String apiKey,
    Uint8List bytes, {
    required String mimeType,
    String? contextHint,
  }) async {
    final isPdfLike = mimeType == 'application/pdf' ||
        mimeType == 'application/vnd.openxmlformats-officedocument.wordprocessingml.document' ||
        mimeType == 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
    final base64Data = base64Encode(bytes);
    final dataUri = 'data:$mimeType;base64,$base64Data';

    final body = {
      'model': _client.config.model,
      'document': isPdfLike
          ? {'type': 'document_url', 'document_url': dataUri}
          : {'type': 'image_url', 'image_url': dataUri},
      // نطلب ثقة على مستوى الصفحة (إشارة جودة عامة نضيفها لاحقًا كتحذير —
      // بلا محاولة دمجها حقلًا-بحقل مع Annotation؛ راجع التعليق أسفل _parse).
      'confidence_scores_granularity': 'page',
      'document_annotation_format': {
        'type': 'json_schema',
        'json_schema': {
          'name': 'inventory_document',
          'schema': _annotationSchema,
          'strict': true,
        },
      },
      'document_annotation_prompt': _annotationPrompt(contextHint),
      if (isPdfLike) 'pages': List.generate(maxAnnotationPages, (i) => i),
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

  /// عام (وليس خاص) عمدًا — قابل للاختبار مباشرة بلا نداء شبكة فعلي (test/mistral_ocr_parsing_test.dart)
  MistralOcrParseResult parseResponseBytes(Uint8List bodyBytes) {
    final decoded = jsonDecode(utf8.decode(bodyBytes));
    if (decoded is! Map) return MistralOcrParseResult.failure('استجابة غير متوقعة من Mistral.');

    // page-level confidence: إشارة جودة عامة فقط (تحذير مستوى المستند) —
    // لا نحاول ربطها بحقل بعينه لأن Mistral لا يربط كلمات OCR بحقول
    // Annotation المنظَّمة تلقائيًا؛ محاولة دمج يدوي هنا كانت ستكون تخمينًا،
    // وهو ما تمنعه المواصفة صراحة (لا تخترع بيانات/ثقة وهمية).
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

    // document_annotation يصل كسلسلة JSON نصية (موثَّق: "string|null...json str")
    // وليس Map جاهزًا — نحتاج فك ترميز إضافي هنا تحديدًا.
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

      // ثقة ذاتية التقييم من النموذج نفسها (مضبوطة بتعليمات صارمة في
      // الـ prompt) — وليست درجة إحصائية خام من OCR. صادقون بهذا في التعليق
      // هنا وفي الرسالة المعروضة، تمامًا كما تطلب المواصفة (لا يقين مزيّف).
      final selfReportedConfidence = _asClampedConfidence(itemMap['confidence']);

      for (final entry in _fieldKeyToType.entries) {
        final value = itemMap[entry.key];
        if (value == null) continue;
        final valueStr = value.toString().trim();
        if (valueStr.isEmpty || valueStr.toLowerCase() == 'null') continue;

        cells.add(ExtractedCell(
          fieldType: entry.value,
          value: valueStr,
          confidence: selfReportedConfidence,
          rowNumber: r + 1,
        ));
      }

      if (cells.isNotEmpty) rows.add(ExtractedRow(cells: cells));
    }
    return rows;
  }

  /// دفاعي: قد يصل الرقم كنص، أو خارج مدى 0..1 (مثلًا 0..100) رغم تعليمات
  /// الـ Schema — نطبّعه بدل تركه يكسر منطق الألوان في شاشة المراجعة.
  double _asClampedConfidence(Object? raw) {
    num? n;
    if (raw is num) n = raw;
    if (raw is String) n = num.tryParse(raw);
    if (n == null) return 0.70; // غياب تقييم ذاتي ≠ يقين ولا انعدام ثقة — قيمة محايدة معتدلة
    final v = n > 1 ? n / 100 : n;
    return v.clamp(0.0, 1.0).toDouble();
  }

  String _annotationPrompt(String? contextHint) {
    return '''
You are extracting structured inventory/sales data from an Arabic document (printed and/or handwritten). ${contextHint ?? ''}

Arabic instructions / تعليمات بالعربية:
- اقرأ النص العربي كما هو، بلا ترجمة أسماء المنتجات.
- حوّل كل الأرقام إلى Western digits (0-9)، أبدًا Arabic-Indic.
- ميّز بدقة بين الكمية (quantity) وسعر الشراء (purchase_price) وسعر البيع (sale_price) والإجمالي (grand_total) والإجمالي الفرعي (subtotal) والمبيعات (sales) والمرتجع (returns) — لا تخلط بينها.
- الجداول العربية تُقرأ من اليمين إلى اليسار غالبًا؛ اربط كل سعر/كمية بالصنف الصحيح في نفس الصف.
- التزم بالتاريخ كما يظهر، ثم طبّعه إلى YYYY-MM-DD إن كان واضحًا فقط.
- استخدم null لأي قيمة غير ظاهرة بوضوح. لا تخترع أو تخمّن أي رقم أو تاريخ أو اسم.
- عامل الكتابة اليدوية بحذر إضافي — إن لم تكن واثقًا من قراءتها، اجعل confidence منخفضة (أقل من 0.60) بدل تخمين حرف/رقم.

English instructions:
- Preserve Arabic product names exactly as written; never translate them.
- Distinguish quantity vs. purchase_price vs. sale_price vs. sales vs. returns vs. subtotal vs. grand_total precisely — these are different fields, do not conflate them.
- Never invent or guess a missing value — use null instead.
- For each item, set "confidence" (0.0-1.0) to your honest certainty about that row's values as a whole. Handwriting, blur, or ambiguity should lower it substantially (below 0.60 if you are genuinely guessing). Do not default to a high confidence out of habit.
- Normalize dates to YYYY-MM-DD only when the original is unambiguous; otherwise keep null.
''';
  }

  static const Map<String, dynamic> _annotationSchema = {
    'type': 'object',
    'properties': {
      'document_type': {'type': ['string', 'null']},
      'invoice_number': {'type': ['string', 'null']},
      'date': {'type': ['string', 'null']},
      'customer': {'type': ['string', 'null']},
      'branch': {'type': ['string', 'null']},
      'sales_rep': {'type': ['string', 'null']},
      'items': {
        'type': 'array',
        'items': {
          'type': 'object',
          'properties': {
            'product_name': {'type': ['string', 'null']},
            'quantity': {'type': ['string', 'null']},
            'unit': {'type': ['string', 'null']},
            'purchase_price': {'type': ['string', 'null']},
            'sale_price': {'type': ['string', 'null']},
            'sales': {'type': ['string', 'null']},
            'returns': {'type': ['string', 'null']},
            'production_date': {'type': ['string', 'null']},
            'expiry_date': {'type': ['string', 'null']},
            'category': {'type': ['string', 'null']},
            'confidence': {'type': ['number', 'null']},
          },
          'required': [
            'product_name', 'quantity', 'unit', 'purchase_price', 'sale_price',
            'sales', 'returns', 'production_date', 'expiry_date', 'category', 'confidence',
          ],
          'additionalProperties': false,
        },
      },
      'subtotal': {'type': ['string', 'null']},
      'discount': {'type': ['string', 'null']},
      'grand_total': {'type': ['string', 'null']},
    },
    'required': [
      'document_type', 'invoice_number', 'date', 'customer', 'branch', 'sales_rep',
      'items', 'subtotal', 'discount', 'grand_total',
    ],
    'additionalProperties': false,
  };
}
