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

/// طلب/تحليل OCR.space — بلا Annotation منظَّمة (خلاف Mistral)، فنص خام →
/// محلل سطري محلي. ⚠️ مبسَّط عمدًا لـ(اسم الصنف + كمية) فقط: بلا مفهوم سعر
/// في هذا التطبيق، لا توجد قاعدة موثوقة لتخمين معنى أي رقم إضافي على السطر
/// (صرف؟ مرتجع؟) — تخمين ذلك كان أخطر من عدم استخراجه إطلاقًا.
class OcrSpaceService {
  final OcrSpaceApiClient _client;
  const OcrSpaceService({OcrSpaceApiClient client = const OcrSpaceApiClient()}) : _client = client;

  OcrSpaceConfig get config => _client.config;

  static const _numberPattern = r'[\d٠-٩]+(?:[.,][\d٠-٩]+)?';

  Future<OcrSpaceParseResult> extract(String apiKey, Uint8List bytes, {required String mimeType}) async {
    final fields = {
      'apikey': apiKey.trim(),
      'base64Image': 'data:$mimeType;base64,${base64Encode(bytes)}',
      'language': config.language,
      'OCREngine': '${config.engine}',
      'isTable': '${config.isTable}',
      'detectOrientation': '${config.detectOrientation}',
      'isOverlayRequired': 'false',
      if (_fileTypeOf(mimeType) != null) 'filetype': _fileTypeOf(mimeType)!,
    };

    http.Response response;
    try {
      response = await _client.parseImage(apiKey, fields);
    } catch (e) {
      return OcrSpaceParseResult.failure(_client.classifyException(e).messageAr);
    }

    final health = _client.classifyResponse(response);
    if (health.status != OcrSpaceConnectionStatus.valid) {
      return OcrSpaceParseResult.failure(health.messageAr);
    }

    try {
      return parseResponseBytes(response.bodyBytes);
    } catch (e) {
      debugPrint('OcrSpaceService: فشل تحليل الاستجابة: $e');
      return OcrSpaceParseResult.failure('وصلت استجابة من OCR.space لكن تعذّر فهم محتواها. جرّب مرة أخرى، أو استخدم استيراد Excel/CSV.');
    }
  }

  String? _fileTypeOf(String mimeType) => switch (mimeType) {
        'application/pdf' => 'PDF',
        'image/png' => 'PNG',
        'image/jpeg' => 'JPG',
        'image/gif' => 'GIF',
        'image/bmp' => 'BMP',
        _ => null,
      };

  /// عام عمدًا — قابل للاختبار مباشرة.
  OcrSpaceParseResult parseResponseBytes(Uint8List bodyBytes) {
    final decoded = jsonDecode(utf8.decode(bodyBytes));
    if (decoded is! Map) return OcrSpaceParseResult.failure('استجابة غير متوقعة من OCR.space.');

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
      allRows.addAll(_parseLinesHeuristically(text, pageNumber: pageIndex + 1));
    }

    if (allRows.isEmpty) {
      return OcrSpaceParseResult.failure('لم يتمكن OCR.space من التعرّف على أي بيانات واضحة في هذا الملف.');
    }
    return OcrSpaceParseResult.success(allRows);
  }

  List<ExtractedRow> _parseLinesHeuristically(String parsedText, {required int pageNumber}) {
    final numberPattern = RegExp(_numberPattern);
    final lines = parsedText.split(RegExp(r'\r?\n')).map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

    final rows = <ExtractedRow>[];
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final numbers = numberPattern.allMatches(line).map((m) => m.group(0)!).toList();
      final nameOnly = line.replaceAll(numberPattern, ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
      if (nameOnly.length < 2) continue; // سطر عناوين/فاصل، وليس صنفًا حقيقيًا

      const conf = 0.60;
      const src = 'unavailable';
      final cells = <ExtractedCell>[
        ExtractedCell(fieldType: FieldType.productName, value: nameOnly, confidence: conf, confidenceSource: src, pageNumber: pageNumber, rowNumber: i + 1),
      ];
      if (numbers.isNotEmpty) {
        cells.add(ExtractedCell(fieldType: FieldType.quantity, value: numbers[0], confidence: conf, confidenceSource: src, pageNumber: pageNumber, rowNumber: i + 1));
      }
      rows.add(ExtractedRow(cells: cells));
    }
    return rows;
  }
}
