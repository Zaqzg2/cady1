import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../services/api_health_service.dart';
import '../services/ocr_service.dart';

/// إعدادات محرك الاستخراج الذكي. المفتاح يُخزَّن عبر Keychain/Keystore
/// (وليس Hive) تحديدًا لأنه سرّي.
///
/// ⚠️ هذا مناسب للتجربة والاستخدام الشخصي. لنشر عام، لا تضع مفتاح API مباشرة
/// في تطبيق موزَّع — استخدم خادمًا وسيطًا (Backend Proxy) يحمل المفتاح بدلًا
/// من ذلك، لأن أي APK يمكن فك حزمه واستخراج المفاتيح المضمَّنة فيه.
class SettingsProvider extends ChangeNotifier {
  static const _keyApiKey = 'ai_vision_api_key';
  static const _keyApiBaseUrl = 'ai_vision_base_url';
  static const _keyModel = 'ai_vision_model';

  static const _defaultBaseUrl = 'https://api.anthropic.com/v1/messages';
  static const _defaultModel = 'claude-sonnet-5';

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final ApiHealthService _apiHealth = const ApiHealthService();

  String? apiKey;
  String apiBaseUrl = _defaultBaseUrl;
  String model = _defaultModel;
  bool isLoaded = false;

  /// نتيجة آخر اختبار فعلي للمفتاح في هذه الجلسة (قسم ١ — لا نفترض صحة
  /// المفتاح من شكله، بل من استجابة حقيقية من المزوّد). null يعني "لم
  /// يُختبر بعد في هذه الجلسة" — فرّق هذه الحالة عن "لا يوجد مفتاح" عبر
  /// [hasApiKey] في الواجهة، فالمعنيان مختلفان (قسم ١١: ⚪ مقابل 🟠).
  ApiHealthResult? lastHealthResult;
  bool isTestingKey = false;

  bool get hasApiKey => apiKey != null && apiKey!.trim().isNotEmpty;

  Future<void> load() async {
    try {
      apiKey = await _secureStorage.read(key: _keyApiKey);
      apiBaseUrl = await _secureStorage.read(key: _keyApiBaseUrl) ?? _defaultBaseUrl;
      model = await _secureStorage.read(key: _keyModel) ?? _defaultModel;
    } catch (_) {
      // بعض المنصات قد لا تدعم التخزين الآمن بالكامل بعد — لا نُسقط التطبيق بسبب ذلك
    } finally {
      isLoaded = true;
      notifyListeners();
    }
  }

  Future<void> setApiKey(String value) async {
    apiKey = value.trim();
    lastHealthResult = null; // نتيجة الاختبار السابقة (إن وُجدت) خاصة بمفتاح مختلف الآن
    notifyListeners();
    try {
      await _secureStorage.write(key: _keyApiKey, value: apiKey);
    } catch (_) {
      // يبقى المفتاح صالحًا لهذه الجلسة حتى لو تعذّر حفظه بشكل دائم
    }
  }

  Future<void> clearApiKey() async {
    apiKey = null;
    lastHealthResult = null;
    notifyListeners();
    try {
      await _secureStorage.delete(key: _keyApiKey);
    } catch (_) {}
  }

  Future<void> setModel(String value) async {
    model = value.trim().isEmpty ? _defaultModel : value.trim();
    notifyListeners();
    try {
      await _secureStorage.write(key: _keyModel, value: model);
    } catch (_) {}
  }

  /// اختبار فعلي للمفتاح الحالي مقابل المزوّد (زر [اختبار المفتاح] — قسم ١١).
  /// لا يفعل شيئًا إن لم يوجد مفتاح أصلًا (الحالة ⚪ محسوبة مباشرة من
  /// [hasApiKey] في الواجهة، بلا حاجة لنداء شبكة).
  Future<void> testKey() async {
    if (!hasApiKey) return;
    isTestingKey = true;
    notifyListeners();
    final result = await _apiHealth.testApiKey(apiKey!, messagesEndpointUrl: apiBaseUrl);
    lastHealthResult = result;
    isTestingKey = false;
    notifyListeners();
  }

  OcrEngine buildOcrEngine() {
    if (!hasApiKey) return UnavailableOcrEngine();
    return AiVisionOcrEngine(apiKey: apiKey!, apiBaseUrl: apiBaseUrl, model: model, apiHealthService: _apiHealth);
  }
}
