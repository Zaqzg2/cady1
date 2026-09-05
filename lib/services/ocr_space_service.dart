import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/import_models.dart';
import 'ocr_space_api_client.dart';

class OcrSpaceParseResult {
  final bool success;
  final String? error;
  final List<ExtractedRow> rows;

  OcrSpaceParseResult._({required this.success, this.error, this.rows = const []});

  factory OcrSpaceParseResult.success(List<ExtractedRow> rows) => OcrSpaceParseResult._(success: true, rows: rows);
  factory OcrSpaceParseResult.failure(String error) => OcrSpaceParseResult._(success: false, error: error);
}

/// طبقة طلب/تحليل OCR.space (يقابل mistral_ocr_service.dart لكن لمحرك بلا
/// أي قدرة Annotation منظَّمة — القسم ١٥ من مواصفة الدمج: OCR.space يمر عبر
/// Raw Text → Parser محلي، ولا نحاول تقليد مخرجات Mistral المنظَّمة).
class OcrSpaceService {
  final OcrSpaceApiClient _client;
  const OcrSpaceService({OcrSpaceApiClient client = const OcrSpaceApiClient()}) : _client = client;

  static const _numberPattern = r'[\d٠-٩]+(?:[.,][\d٠-٩]+)?';

  Future<OcrSpaceParseResult> extract(
    String apiKey,
    Uint8List bytes, {
    required String mimeType,
  }) async {
    final base64 = base64Encode(bytes);
    final fileType = _fileTypeOf(mimeType);
    final fields = {
      'apikey': apiKey.trim(),
      'base64Image': 'data:$mimeType;base64,$base64',
      'language': _client.config.language,
      'OCREngine': '${_client.config.engine}',
      'isTable': '${_client.config.isTable}',
      'detectOrientation': '${_client.config.detectOrientation}',
      'isOverlayRequired': 'false',
      if (fileType != null) 'filetype': fileType,
    };

    http.Response response;
    try {
      response = await _client.parseImage(apiKey, fields);
    } catch (e) {
      return OcrSpaceParseResult.failure(_client.classifyException(e).messageAr);
    }

    // OCR.space يعيد HTTP 200 حتى عند فشل فعلي — فحص الجسم إلزامي هنا، ليس
    // رمز الحالة فقط (خلاف Mistral؛ راجع تعليق OcrSpaceApiClient).
    final health = _client.classifyResponse(response);
    if (health.status != OcrSpaceConnectionStatus.valid) {
      return OcrSpaceParseResult.failure(health.messageAr);
    }

    try {
      return parseResponseBytes(response.bodyBytes);
    } catch (e) {
      debugPrint('OcrSpaceService: فشل تحليل الاستجابة: $e');
      return OcrSpaceParseResult.failure(
        'وصلت استجابة من OCR.space لكن تعذّر فهم محتواها. جرّب مرة أخرى، أو استخدم استيراد Excel/CSV.',
      );
    }
  }

  String? _fileTypeOf(String mimeType) => switch (mimeType) {
        'application/pdf' => 'PDF',
        'image/png' => 'PNG',
        'image/jpeg' => 'JPG',
        'image/gif' => 'GIF',
        'image/bmp' => 'BMP',
        _ => null, // نترك الاكتشاف التلقائي لـ OCR.space بدل افتراض JPEG دائمًا (القسم ٢٥ من مواصفة Mistral، ينطبق هنا بنفس الروح)
      };

  /// عام عمدًا — قابل للاختبار مباشرة (test/ocr_space_parsing_test.dart)
  OcrSpaceParseResult parseResponseBytes(Uint8List bodyBytes) {
    final decoded = jsonDecode(utf8.decode(bodyBytes));
    if (decoded is! Map) return OcrSpaceParseResult.failure('استجابة غير متوقعة من OCR.space.');

    // بأمان تام — بلا أي "as Map<String,dynamic>" مباشر بلا تحقق (قسم ١١):
    final parsedResults = decoded['ParsedResults'];
    if (parsedResults is! List || parsedResults.isEmpty) {
      return OcrSpaceParseResult.failure('لم يتمكن OCR.space من التعرّف على أي نص في هذا الملف.');
    }

    final allRows = <ExtractedRow>[];
    for (var pageIndex = 0; pageIndex < parsedResults.length; pageIndex++) {
      final page = parsedResults[pageIndex];
      if (page is! Map) continue;
      final text = page['ParsedText'];
      if (text is! String || text.trim().isEmpty) continue;
      final rows = _parseLinesHeuristically(text, pageNumber: pageIndex + 1);
      allRows.addAll(rows);
    }

    if (allRows.isEmpty) {
      return OcrSpaceParseResult.failure('لم يتمكن OCR.space من التعرّف على أي بيانات واضحة في هذا الملف.');
    }
    return OcrSpaceParseResult.success(allRows);
  }

  /// تحليل نصي محلي بسيط (سطر = صف عند isTable=true) — لا مقارنة بمستوى
  /// الفهم البنيوي لـ Mistral Annotation، فالثقة هنا 'unavailable' دائمًا
  /// (قسم ١٢: لا نخترع نسبة ثقة لا تعنيها OCR.space فعليًا).
  List<ExtractedRow> _parseLinesHeuristically(String parsedText, {required int pageNumber}) {
    final numberPattern = RegExp(_numberPattern);
    final lines = parsedText
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    final rows = <ExtractedRow>[];
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final numbers = numberPattern.allMatches(line).map((m) => m.group(0)!).toList();
      final nameOnly = line.replaceAll(numberPattern, ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

      // سطر بلا نص صنف حقيقي (فاصل/عنوان جدول فقط) — يُتجاهل بدل إدخاله كصف وهمي
      if (nameOnly.length < 2) continue;

      const conf = 0.60; // عتبة "مراجعة موصى بها" الافتراضية — ليست ادّعاء ثقة حقيقي
      const src = 'unavailable';
      final cells = <ExtractedCell>[
        ExtractedCell(
          fieldType: FieldType.productName,
          value: nameOnly,
          confidence: conf,
          confidenceSource: src,
          pageNumber: pageNumber,
          rowNumber: i + 1,
        ),
      ];
      if (numbers.isNotEmpty) {
        cells.add(ExtractedCell(
          fieldType: FieldType.quantity,
          value: numbers[0],
          confidence: conf,
          confidenceSource: src,
          pageNumber: pageNumber,
          rowNumber: i + 1,
        ));
      }
      if (numbers.length >= 2) {
        cells.add(ExtractedCell(
          fieldType: FieldType.price,
          value: numbers[1],
          confidence: conf,
          confidenceSource: src,
          pageNumber: pageNumber,
          rowNumber: i + 1,
        ));
      }
      if (numbers.length >= 3) {
        cells.add(ExtractedCell(
          fieldType: FieldType.salePrice,
          value: numbers[2],
          confidence: conf,
          confidenceSource: src,
          pageNumber: pageNumber,
          rowNumber: i + 1,
        ));
      }
      rows.add(ExtractedRow(cells: cells));
    }
    return rows;
  }
}
