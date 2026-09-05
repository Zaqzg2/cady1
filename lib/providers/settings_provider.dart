import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../services/mistral_api_client.dart';
import '../services/ocr_manager.dart';
import '../services/ocr_space_api_client.dart';

/// إعدادات محركَي OCR (Mistral وOCR.space) — مستقلّان تمامًا: مفتاحان
/// منفصلان في التخزين الآمن، نتيجتا اختبار منفصلتان، بلا أي خلط بينهما
/// (قسم ٣٧ من مواصفة الدمج).
///
/// ⚠️ هذا مناسب للتجربة والاستخدام الشخصي. لنشر عام (وتحديدًا على Flutter
/// Web) لا يمكن إخفاء مفتاح API حقيقةً عن المستخدم النهائي — أي طلب يذهب
/// مباشرة من المتصفح لـ api.mistral.ai أو api.ocr.space يمكن لأي شخص رؤية
/// مفتاحه من Network tab. البنية هنا (MistralApiClient/OcrSpaceApiClient
/// كطبقة منفصلة عن الشاشات) مصمَّمة عمدًا بحيث يمكن لاحقًا استبدال هذين
/// العميلين بنداء لخادم وسيط (Backend Proxy) بلا تغيير OcrEngine أو أي شاشة
/// (قسم ١٨-١٩ من مواصفة Mistral الأولى، قسم ١٨ من مواصفة الدمج).
class SettingsProvider extends ChangeNotifier {
  static const _keyMistralApiKey = 'mistral_api_key';
  static const _keyOcrSpaceApiKey = 'ocr_space_api_key';
  static const _keyEngineSelection = 'ocr_engine_selection';
  static const _keyAutoFallback = 'ocr_auto_fallback_enabled';

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final MistralApiClient _mistralClient = const MistralApiClient();
  final OcrSpaceApiClient _ocrSpaceClient = const OcrSpaceApiClient();

  String? mistralApiKey;
  String? ocrSpaceApiKey;
  OcrEngineSelection engineSelection = OcrEngineSelection.mistral; // Default: Mistral AI (قسم ٣٦)
  bool autoFallbackEnabled = true;
  bool isLoaded = false;

  /// نتائج آخر اختبار فعلي لكل محرك في هذه الجلسة. null = لم يُختبر بعد.
  MistralHealthResult? mistralHealthResult;
  OcrSpaceHealthResult? ocrSpaceHealthResult;
  bool isTestingMistral = false;
  bool isTestingOcrSpace = false;

  bool get hasMistralKey => mistralApiKey != null && mistralApiKey!.trim().isNotEmpty;
  bool get hasOcrSpaceKey => ocrSpaceApiKey != null && ocrSpaceApiKey!.trim().isNotEmpty;
  bool get hasAnyOcrKey => hasMistralKey || hasOcrSpaceKey;

  Future<void> load() async {
    try {
      mistralApiKey = await _secureStorage.read(key: _keyMistralApiKey);
      ocrSpaceApiKey = await _secureStorage.read(key: _keyOcrSpaceApiKey);
      final storedSelection = await _secureStorage.read(key: _keyEngineSelection);
      engineSelection = OcrEngineSelection.values.firstWhere(
        (e) => e.name == storedSelection,
        orElse: () => OcrEngineSelection.mistral,
      );
      final storedFallback = await _secureStorage.read(key: _keyAutoFallback);
      autoFallbackEnabled = storedFallback == null ? true : storedFallback == 'true';
    } catch (_) {
      // بعض المنصات قد لا تدعم التخزين الآمن بالكامل بعد — لا نُسقط التطبيق بسبب ذلك
    } finally {
      isLoaded = true;
      notifyListeners();
    }
  }

  Future<void> setMistralApiKey(String value) async {
    mistralApiKey = value.trim();
    mistralHealthResult = null; // نتيجة الاختبار السابقة خاصة بمفتاح مختلف الآن
    notifyListeners();
    try {
      await _secureStorage.write(key: _keyMistralApiKey, value: mistralApiKey);
    } catch (_) {}
  }

  Future<void> clearMistralApiKey() async {
    mistralApiKey = null;
    mistralHealthResult = null;
    notifyListeners();
    try {
      await _secureStorage.delete(key: _keyMistralApiKey);
    } catch (_) {}
  }

  Future<void> setOcrSpaceApiKey(String value) async {
    ocrSpaceApiKey = value.trim();
    ocrSpaceHealthResult = null;
    notifyListeners();
    try {
      await _secureStorage.write(key: _keyOcrSpaceApiKey, value: ocrSpaceApiKey);
    } catch (_) {}
  }

  Future<void> clearOcrSpaceApiKey() async {
    ocrSpaceApiKey = null;
    ocrSpaceHealthResult = null;
    notifyListeners();
    try {
      await _secureStorage.delete(key: _keyOcrSpaceApiKey);
    } catch (_) {}
  }

  Future<void> setEngineSelection(OcrEngineSelection value) async {
    engineSelection = value;
    notifyListeners();
    try {
      await _secureStorage.write(key: _keyEngineSelection, value: value.name);
    } catch (_) {}
  }

  Future<void> setAutoFallbackEnabled(bool value) async {
    autoFallbackEnabled = value;
    notifyListeners();
    try {
      await _secureStorage.write(key: _keyAutoFallback, value: '$value');
    } catch (_) {}
  }

  /// اختبار Mistral فعلي (زر [اختبار Mistral] — قسم ١٦، ١٩). GET /v1/models
  /// خفيف بلا أي تكلفة OCR فعلية.
  Future<void> testMistralConnection() async {
    if (!hasMistralKey) return;
    isTestingMistral = true;
    notifyListeners();
    mistralHealthResult = await _mistralClient.testConnection(mistralApiKey!);
    isTestingMistral = false;
    notifyListeners();
  }

  /// اختبار OCR.space فعلي (زر [اختبار OCR.space]) — طلب OCR حقيقي وخفيف
  /// (صورة 1×1) لأن OCR.space لا يوفّر endpoint تعريف/نماذج منفصل مثل Mistral.
  Future<void> testOcrSpaceConnection() async {
    if (!hasOcrSpaceKey) return;
    isTestingOcrSpace = true;
    notifyListeners();
    ocrSpaceHealthResult = await _ocrSpaceClient.testConnection(ocrSpaceApiKey!);
    isTestingOcrSpace = false;
    notifyListeners();
  }

  /// نقطة الدخول الوحيدة لبناء منسّق OCR — لا تعرف أي شاشة أو Provider آخر
  /// أي تفاصيل عن المحركين أنفسهما (قسم ١، ٢٨).
  OcrManager buildOcrManager() => OcrManager(
        mistralApiKey: mistralApiKey,
        ocrSpaceApiKey: ocrSpaceApiKey,
        selection: engineSelection,
        autoFallbackEnabled: autoFallbackEnabled,
      );
}
