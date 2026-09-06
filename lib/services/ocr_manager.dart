import 'dart:typed_data';

import 'ocr_service.dart';

/// اختيار المستخدم لمحرك OCR (القسم ٨، ١٦، ٣٦ من مواصفة الدمج).
enum OcrEngineSelection { mistral, ocrSpace, automatic }

extension OcrEngineSelectionLabel on OcrEngineSelection {
  String get labelAr => switch (this) {
        OcrEngineSelection.mistral => 'Mistral AI',
        OcrEngineSelection.ocrSpace => 'OCR.space',
        OcrEngineSelection.automatic => 'تلقائي',
      };
}

/// يختار المحرك المناسب وينفّذ fallback تلقائي عند الحاجة (القسم ٩، ٣٧).
/// لا يخلط المفاتيح إطلاقًا — كل محرك يُبنى بمفتاحه المستقل فقط (القسم ٣٧).
/// هذه الطبقة نفسها لا تعرف تفاصيل Mistral أو OCR.space — فقط تنسّق بين
/// OcrEngine instances جاهزة (القسم ١، ٢٨: لا OCR parsing هنا).
///
/// يطبّق OcrEngine نفسها عمدًا (extractTable بنفس توقيع process تمامًا) حتى
/// يُستخدَم في كل مكان كان يتوقع محركًا واحدًا من قبل (ImportSessionProvider
/// وغيره) بلا أي تغيير في تلك التوقيعات — الاستبدال شفّاف تمامًا.
class OcrManager implements OcrEngine {
  final String? mistralApiKey;
  final String? ocrSpaceApiKey;
  final OcrEngineSelection selection;

  /// "☑ استخدام محرك بديل عند الفشل" في الإعدادات (القسم ١٦) — يُفعِّل
  /// fallback فقط في وضع "تلقائي"؛ الاختيار اليدوي لمحرك بعينه لا يتحول
  /// لمحرك آخر أبدًا (القسم ٨).
  final bool autoFallbackEnabled;

  /// حقنة اختيارية للاختبارات فقط (test/ocr_manager_test.dart) — تسمح بحقن
  /// محرك وهمي بدل بنائه فعليًا من مفتاح API حقيقي، فيصبح منطق fallback
  /// قابلًا للاختبار بلا أي نداء شبكة فعلي. الاستخدام الطبيعي في التطبيق
  /// (SettingsProvider.buildOcrManager) لا يمرّر هذين، فيبقى السلوك كما هو.
  final OcrEngine? mistralEngineOverride;
  final OcrEngine? ocrSpaceEngineOverride;

  const OcrManager({
    required this.mistralApiKey,
    required this.ocrSpaceApiKey,
    required this.selection,
    required this.autoFallbackEnabled,
    this.mistralEngineOverride,
    this.ocrSpaceEngineOverride,
  });

  bool get hasMistralKey => mistralEngineOverride != null || (mistralApiKey?.trim().isNotEmpty ?? false);
  bool get hasOcrSpaceKey => ocrSpaceEngineOverride != null || (ocrSpaceApiKey?.trim().isNotEmpty ?? false);
  bool get hasAnyEngine => hasMistralKey || hasOcrSpaceKey;

  OcrEngine? _mistral() =>
      mistralEngineOverride ?? (hasMistralKey ? MistralOcrEngine(apiKey: mistralApiKey!.trim()) : null);
  OcrEngine? _ocrSpace() =>
      ocrSpaceEngineOverride ?? (hasOcrSpaceKey ? OcrSpaceEngine(apiKey: ocrSpaceApiKey!.trim()) : null);

  /// نقطة الدخول الوحيدة (OcrManager.process — القسم ٩) التي تستخدمها بقية
  /// التطبيق. لا تعرف الشاشات ولا ImportSessionProvider أي تفاصيل عن أي
  /// محرك استُخدم فعليًا — فقط النتيجة الموحَّدة [OcrExtractionResult].
  @override
  Future<OcrExtractionResult> extractTable(
    Uint8List bytes, {
    required String mimeType,
    String? contextHint,
  }) =>
      process(bytes, mimeType: mimeType, contextHint: contextHint);

  /// الاسم الحرفي المطلوب في نص المواصفة (القسم ٩) — نفس extractTable تمامًا،
  /// موجودة كواجهة صريحة لهذا المنسّق تحديدًا بدل استدعاء عبر الواجهة العامة فقط.
  Future<OcrExtractionResult> process(
    Uint8List bytes, {
    required String mimeType,
    String? contextHint,
  }) async {
    if (!hasAnyEngine) {
      return OcrExtractionResult.failure(
        'لا يوجد محرك OCR مُفعَّل. اذهب إلى الإعدادات وأضف مفتاح Mistral أو OCR.space، '
        'أو استورد بيانات من Excel/CSV بدلًا من ذلك.',
      );
    }

    switch (selection) {
      case OcrEngineSelection.mistral:
        final engine = _mistral();
        if (engine == null) {
          return OcrExtractionResult.failure('محرك Mistral مُختار في الإعدادات لكن لا يوجد له مفتاح API محفوظ.');
        }
        return engine.extractTable(bytes, mimeType: mimeType, contextHint: contextHint);

      case OcrEngineSelection.ocrSpace:
        final engine = _ocrSpace();
        if (engine == null) {
          return OcrExtractionResult.failure('محرك OCR.space مُختار في الإعدادات لكن لا يوجد له مفتاح API محفوظ.');
        }
        return engine.extractTable(bytes, mimeType: mimeType, contextHint: contextHint);

      case OcrEngineSelection.automatic:
        return _processAutomatic(bytes, mimeType: mimeType, contextHint: contextHint);
    }
  }

  Future<OcrExtractionResult> _processAutomatic(
    Uint8List bytes, {
    required String mimeType,
    String? contextHint,
  }) async {
    // تلقائي → Mistral أولًا دائمًا (القسم ٨).
    final mistral = _mistral();
    if (mistral == null) {
      // لا مفتاح Mistral أصلًا في الوضع التلقائي — جرّب OCR.space مباشرة
      // بلا اعتبار ذلك "fallback بعد فشل"، فالمحرك الأساسي غير مُعَدّ فقط.
      final ocrSpace = _ocrSpace();
      if (ocrSpace != null) return ocrSpace.extractTable(bytes, mimeType: mimeType, contextHint: contextHint);
      return OcrExtractionResult.failure('لا يوجد أي محرك OCR بمفتاح صالح.');
    }

    final primaryResult = await mistral.extractTable(bytes, mimeType: mimeType, contextHint: contextHint);
    if (primaryResult.success) return primaryResult;

    final ocrSpace = _ocrSpace();
    // بلا مفتاح OCR.space مستقل، أو الوضع التلقائي بلا تفعيل الـ fallback:
    // لا محاولة ثانية — نُعيد فشل Mistral كما هو (بلا خلط مفاتيح — قسم ٣٧).
    if (!autoFallbackEnabled || ocrSpace == null) return primaryResult;

    final fallbackResult = await ocrSpace.extractTable(bytes, mimeType: mimeType, contextHint: contextHint);
    // إن نجح البديل: نتيجته. إن فشل الاثنان معًا: خطأ المحرك الأساسي (Mistral)
    // هو الأنسب للعرض، لأنه المحرك المُفضَّل والمتوقَّع من المستخدم.
    return fallbackResult.success ? fallbackResult : primaryResult;
  }
}
