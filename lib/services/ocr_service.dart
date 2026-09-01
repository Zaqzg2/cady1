import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/import_models.dart';

class OcrExtractionResult {
  final bool success;
  final String? error;
  final List<ExtractedRow> rows;

  OcrExtractionResult._({required this.success, this.error, this.rows = const []});

  factory OcrExtractionResult.success(List<ExtractedRow> rows) =>
      OcrExtractionResult._(success: true, rows: rows);

  factory OcrExtractionResult.failure(String error) =>
      OcrExtractionResult._(success: false, error: error);
}

/// واجهة محرك استخراج جدول من صورة — أي محرك (سحابي بالذكاء الاصطناعي أو
/// محلي offline مستقبلًا) يطبّق هذه الواجهة فقط، دون أن تعرف الشاشات نوعه.
abstract class OcrEngine {
  Future<OcrExtractionResult> extractTable(
    Uint8List imageBytes, {
    String? contextHint,
  });
}

/// محرك يعتمد على نموذج ذكاء اصطناعي متعدد الوسائط (Vision LLM) لقراءة الصورة
/// مباشرة وإخراج جدول منظّم مع درجة ثقة لكل حقل — هذا هو المسار الموصى به هنا
/// لأن محركات OCR التقليدية على الجهاز (مثل Google ML Kit) لا تدعم النص
/// العربي أصلاً، وضعيفة جدًا في الكتابة اليدوية العربية تحديدًا.
///
/// ⚠️ هذا المحرك يحتاج اتصال إنترنت (فقط أثناء الاستيراد) ومفتاح API. راجع
/// قسم "الأمان" في README قبل نشر التطبيق للعامة — لا يجوز تضمين المفتاح
/// مباشرة داخل تطبيق موزَّع دون طبقة وسيطة (Backend Proxy) في الإنتاج.
class AiVisionOcrEngine implements OcrEngine {
  final String apiKey;
  final String apiBaseUrl;
  final String model;

  AiVisionOcrEngine({
    required this.apiKey,
    this.apiBaseUrl = 'https://api.anthropic.com/v1/messages',
    // ملاحظة: تحقق من نموذج الرؤية الحالي في وثائق مزوّدك قبل الاستخدام،
    // فأسماء النماذج تتغيّر بمرور الوقت.
    this.model = 'claude-sonnet-5',
  });

  @override
  Future<OcrExtractionResult> extractTable(
    Uint8List imageBytes, {
    String? contextHint,
  }) async {
    if (apiKey.trim().isEmpty) {
      return OcrExtractionResult.failure(
        'لم يتم ضبط مفتاح خدمة الاستخراج الذكي بعد. أضفه من الإعدادات، أو استخدم استيراد Excel/CSV الذي يعمل بلا إنترنت.',
      );
    }

    try {
      final base64Image = base64Encode(imageBytes);
      final response = await http
          .post(
            Uri.parse(apiBaseUrl),
            headers: {
              'Content-Type': 'application/json',
              'x-api-key': apiKey,
              'anthropic-version': '2023-06-01',
            },
            body: jsonEncode({
              'model': model,
              'max_tokens': 4096,
              'messages': [
                {
                  'role': 'user',
                  'content': [
                    {
                      'type': 'image',
                      'source': {
                        'type': 'base64',
                        'media_type': 'image/jpeg',
                        'data': base64Image,
                      },
                    },
                    {'type': 'text', 'text': _buildPrompt(contextHint)},
                  ],
                },
              ],
            }),
          )
          .timeout(const Duration(seconds: 90));

      if (response.statusCode != 200) {
        return OcrExtractionResult.failure(
          'فشل الاتصال بخدمة الاستخراج (رمز ${response.statusCode}). تحقّق من مفتاح API وحصتك المتاحة.',
        );
      }

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      final contentBlocks = (decoded['content'] as List?) ?? [];
      final buffer = StringBuffer();
      for (final block in contentBlocks) {
        if (block is Map && block['type'] == 'text') {
          buffer.write(block['text']);
        }
      }

      final jsonText = _extractJson(buffer.toString());
      final parsed = jsonDecode(jsonText) as Map<String, dynamic>;
      final rows = _parseRows(parsed);

      if (rows.isEmpty) {
        return OcrExtractionResult.failure(
          'لم يتمكن النموذج من التعرّف على أي بيانات واضحة في هذه الصورة.',
        );
      }
      return OcrExtractionResult.success(rows);
    } on TimeoutException {
      return OcrExtractionResult.failure('انتهت مهلة الاتصال. تحقق من الإنترنت وأعد المحاولة.');
    } catch (e) {
      // أي فشل هنا (شبكة/تحليل JSON/غيره) يُعاد كنتيجة فشل واضحة بدل أن يختفي
      // بصمت — بنفس روح الدرس السابع في دليل الأعطال (لا Exceptions غير ممسوكة).
      return OcrExtractionResult.failure('تعذّر استخراج البيانات من الصورة: $e');
    }
  }

  String _buildPrompt(String? contextHint) {
    return '''
You are analyzing a photo or scanned page of an Arabic inventory/stock sheet (may include printed and/or handwritten Arabic text, tables, or free-form lists). ${contextHint ?? ''}

Extract every product/line row you can find and return STRICT JSON ONLY (no markdown fences, no commentary) matching exactly this schema:

{
  "rows": [
    {
      "product_name": {"value": "string in Arabic as written", "confidence": 0-100},
      "quantity": {"value": "number as plain string, Western digits", "confidence": 0-100},
      "unit": {"value": "string or null", "confidence": 0-100},
      "purchase_price": {"value": "number as plain string or null", "confidence": 0-100},
      "sale_price": {"value": "number as plain string or null", "confidence": 0-100},
      "sales": {"value": "number as plain string or null", "confidence": 0-100},
      "returns": {"value": "number as plain string or null", "confidence": 0-100},
      "production_date": {"value": "YYYY-MM-DD or null", "confidence": 0-100},
      "expiry_date": {"value": "YYYY-MM-DD or null", "confidence": 0-100},
      "branch": {"value": "string or null", "confidence": 0-100},
      "category": {"value": "string or null", "confidence": 0-100}
    }
  ]
}

Rules:
- Omit any field key entirely if that value truly does not appear for that row (do not invent data).
- confidence must honestly reflect how legible/certain you are — handwriting, blur, or ambiguity should lower it a lot (below 60 if you are genuinely guessing).
- Always use Western digits (0-9) in values, never Arabic-Indic digits.
- Keep Arabic product names exactly as written (do not translate).
- Return ONLY the JSON object, nothing else.
''';
  }

  String _extractJson(String raw) {
    final text = raw.trim();
    final fenceMatch = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(text);
    if (fenceMatch != null) return fenceMatch.group(1)!.trim();
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start != -1 && end != -1 && end > start) {
      return text.substring(start, end + 1);
    }
    return text;
  }

  static const _fieldKeyToType = {
    'product_name': FieldType.productName,
    'quantity': FieldType.quantity,
    'purchase_price': FieldType.price,
    'sale_price': FieldType.salePrice,
    'sales': FieldType.sales,
    'returns': FieldType.returns,
    'production_date': FieldType.productionDate,
    'expiry_date': FieldType.expiryDate,
    'branch': FieldType.branch,
    'category': FieldType.category,
  };

  List<ExtractedRow> _parseRows(Map<String, dynamic> parsed) {
    final rawRows = (parsed['rows'] as List?) ?? [];
    final rows = <ExtractedRow>[];

    for (var r = 0; r < rawRows.length; r++) {
      final rowMap = rawRows[r];
      if (rowMap is! Map) continue;
      final cells = <ExtractedCell>[];

      for (final entry in _fieldKeyToType.entries) {
        final fieldJson = rowMap[entry.key];
        if (fieldJson is! Map) continue;
        final value = fieldJson['value'];
        if (value == null) continue;
        final valueStr = value.toString().trim();
        if (valueStr.isEmpty || valueStr.toLowerCase() == 'null') continue;

        final confidenceRaw = fieldJson['confidence'];
        final confidence = ((confidenceRaw is num ? confidenceRaw.toDouble() : 70) / 100)
            .clamp(0.0, 1.0);

        cells.add(ExtractedCell(
          fieldType: entry.value,
          value: valueStr,
          confidence: confidence,
          rowNumber: r + 1,
        ));
      }

      if (cells.isNotEmpty) rows.add(ExtractedRow(cells: cells));
    }
    return rows;
  }
}

/// محرك احتياطي يُستخدم عندما لا يوجد مفتاح API مضبوط، ليعطي رسالة واضحة
/// بدل رمي استثناء أو تعليق الواجهة على شاشة تحميل بلا تفسير.
class UnavailableOcrEngine implements OcrEngine {
  @override
  Future<OcrExtractionResult> extractTable(Uint8List imageBytes, {String? contextHint}) async {
    return OcrExtractionResult.failure(
      'محرك الاستخراج الذكي غير مُفعَّل. اذهب إلى الإعدادات وأضف مفتاح API، أو استورد بيانات من Excel/CSV بدلًا من ذلك.',
    );
  }
}
