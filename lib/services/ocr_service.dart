import 'dart:typed_data';

import '../models/import_models.dart';
import 'mistral_ocr_service.dart';
import 'ocr_space_service.dart';

class OcrExtractionResult {
  final bool success;
  final String? error;
  final List<ExtractedRow> rows;

  /// معلومات مصدر إضافية (مؤشر المصدر في شاشة المراجعة) — اختيارية بقيمة
  /// افتراضية معقولة، فلا تكسر أي كود قديم.
  final String provider; // 'mistral' | 'ocr_space' | 'none'
  final String? model;
  final Duration processingTime;

  OcrExtractionResult._({
    required this.success,
    this.error,
    this.rows = const [],
    this.provider = 'none',
    this.model,
    this.processingTime = Duration.zero,
  });

  factory OcrExtractionResult.success(
    List<ExtractedRow> rows, {
    String provider = 'none',
    String? model,
    Duration processingTime = Duration.zero,
  }) =>
      OcrExtractionResult._(success: true, rows: rows, provider: provider, model: model, processingTime: processingTime);

  factory OcrExtractionResult.failure(
    String error, {
    String provider = 'none',
    String? model,
    Duration processingTime = Duration.zero,
  }) =>
      OcrExtractionResult._(success: false, error: error, provider: provider, model: model, processingTime: processingTime);
}

/// واجهة محرك استخراج جدول من صورة أو مستند. [mimeType] مطلوب صراحة —
/// ضروري لأن Mistral يقرأ PDF مباشرة بلا تحويله لصور أولًا.
abstract class OcrEngine {
  Future<OcrExtractionResult> extractTable(
    Uint8List bytes, {
    required String mimeType,
    String? contextHint,
  });
}

/// المحرك الأساسي (PRIMARY): يفوّض لـmistral_ocr_service.dart (طلب/تحليل)
/// وmistral_api_client.dart (HTTP/مصادقة/أخطاء).
class MistralOcrEngine implements OcrEngine {
  final String apiKey;
  final MistralOcrService _service;

  MistralOcrEngine({required this.apiKey, MistralOcrService service = const MistralOcrService()}) : _service = service;

  @override
  Future<OcrExtractionResult> extractTable(Uint8List bytes, {required String mimeType, String? contextHint}) async {
    final stopwatch = Stopwatch()..start();
    final result = await _service.extract(apiKey, bytes, mimeType: mimeType, contextHint: contextHint);
    stopwatch.stop();

    if (!result.success) {
      return OcrExtractionResult.failure(
        result.error ?? 'تعذّر استخراج البيانات عبر Mistral.',
        provider: 'mistral',
        model: _service.config.model,
        processingTime: stopwatch.elapsed,
      );
    }
    return OcrExtractionResult.success(result.rows, provider: 'mistral', model: _service.config.model, processingTime: stopwatch.elapsed);
  }
}

/// المحرك الثانوي (SECONDARY): يفوّض لـocr_space_service.dart. بلا Document
/// Annotation ولا ثقة حقيقية لكل حقل — يُعرَّف بوضوح بلا تقليد سلوك Mistral.
class OcrSpaceEngine implements OcrEngine {
  final String apiKey;
  final OcrSpaceService _service;

  OcrSpaceEngine({required this.apiKey, OcrSpaceService service = const OcrSpaceService()}) : _service = service;

  @override
  Future<OcrExtractionResult> extractTable(Uint8List bytes, {required String mimeType, String? contextHint}) async {
    final stopwatch = Stopwatch()..start();
    final result = await _service.extract(apiKey, bytes, mimeType: mimeType);
    stopwatch.stop();

    if (!result.success) {
      return OcrExtractionResult.failure(result.error ?? 'تعذّر استخراج البيانات عبر OCR.space.', provider: 'ocr_space', processingTime: stopwatch.elapsed);
    }
    return OcrExtractionResult.success(result.rows, provider: 'ocr_space', processingTime: stopwatch.elapsed);
  }
}

/// محرك احتياطي عند غياب أي مفتاح API على الإطلاق.
class UnavailableOcrEngine implements OcrEngine {
  @override
  Future<OcrExtractionResult> extractTable(Uint8List bytes, {required String mimeType, String? contextHint}) async {
    return OcrExtractionResult.failure(
      'لا يوجد محرك OCR مُفعَّل. اذهب إلى الإعدادات وأضف مفتاح Mistral أو OCR.space، '
      'أو استورد بيانات من Excel/CSV بدلًا من ذلك.',
    );
  }
}
