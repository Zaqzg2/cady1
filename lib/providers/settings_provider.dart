import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../services/ocr_service.dart';
import '../services/repository.dart';

/// كل إعدادات التطبيق (القسم 34). المفتاح السرّي فقط (API Key) يُخزَّن عبر
/// Keychain/Keystore (وليس Hive)؛ كل الإعدادات الأخرى — غير الحسّاسة — تُخزَّن
/// في صندوق الإعدادات العادي عبر Repository لتبقى سريعة ومتّسقة مع باقي البيانات.
///
/// ⚠️ الاستخراج السحابي الاختياري مناسب للتجربة والاستخدام الشخصي فقط. لنشر
/// عام، لا تضع مفتاح API مباشرة في تطبيق موزَّع — استخدم خادمًا وسيطًا
/// (Backend Proxy) بدلًا من ذلك، لأن أي APK يمكن فك حزمه واستخراج المفاتيح.
class SettingsProvider extends ChangeNotifier {
  static const _keyApiKey = 'ai_vision_api_key';
  static const _keyApiBaseUrl = 'ai_vision_base_url';
  static const _keyModel = 'ai_vision_model';

  static const _defaultBaseUrl = 'https://api.anthropic.com/v1/messages';
  static const _defaultModel = 'claude-sonnet-5';

  // مفاتيح صندوق الإعدادات العادي (Hive) — غير سرّية
  static const _kUseCloudOcr = 'use_cloud_ocr';
  static const _kCurrency = 'currency_code';
  static const _kMonthStartDay = 'month_start_day';
  static const _kDefaultReorderPoint = 'default_reorder_point';
  static const _kNearExpiry1 = 'near_expiry_days_1';
  static const _kNearExpiry2 = 'near_expiry_days_2';
  static const _kReportFormat = 'default_report_format';
  static const _kDefaultBranchId = 'default_branch_id';
  static const _kDefaultCategoryId = 'default_category_id';
  static const _kLastBackupAt = 'last_backup_at';

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final Repository _repo = Repository();

  String? apiKey;
  String apiBaseUrl = _defaultBaseUrl;
  String model = _defaultModel;
  bool useCloudOcr = false;

  String currencyCode = 'SAR';
  int monthStartDay = 1;
  double defaultReorderPoint = 5;
  int nearExpiryDays1 = 30;
  int nearExpiryDays2 = 60;
  String defaultReportFormat = 'pdf';
  String? defaultBranchId;
  String? defaultCategoryId;
  DateTime? lastBackupAt;

  bool isLoaded = false;

  bool get hasApiKey => apiKey != null && apiKey!.trim().isNotEmpty;

  Future<void> load() async {
    try {
      apiKey = await _secureStorage.read(key: _keyApiKey);
      apiBaseUrl = await _secureStorage.read(key: _keyApiBaseUrl) ?? _defaultBaseUrl;
      model = await _secureStorage.read(key: _keyModel) ?? _defaultModel;
    } catch (_) {
      // بعض المنصات قد لا تدعم التخزين الآمن بالكامل بعد — لا نُسقط التطبيق بسبب ذلك
    }

    useCloudOcr = _repo.getSetting<bool>(_kUseCloudOcr, false) ?? false;
    currencyCode = _repo.getSetting<String>(_kCurrency, 'SAR') ?? 'SAR';
    monthStartDay = _repo.getSetting<int>(_kMonthStartDay, 1) ?? 1;
    defaultReorderPoint = (_repo.getSetting<num>(_kDefaultReorderPoint, 5) ?? 5).toDouble();
    nearExpiryDays1 = _repo.getSetting<int>(_kNearExpiry1, 30) ?? 30;
    nearExpiryDays2 = _repo.getSetting<int>(_kNearExpiry2, 60) ?? 60;
    defaultReportFormat = _repo.getSetting<String>(_kReportFormat, 'pdf') ?? 'pdf';
    defaultBranchId = _repo.getSetting<String>(_kDefaultBranchId);
    defaultCategoryId = _repo.getSetting<String>(_kDefaultCategoryId);
    final lastBackupIso = _repo.getSetting<String>(_kLastBackupAt);
    lastBackupAt = lastBackupIso != null ? DateTime.tryParse(lastBackupIso) : null;

    isLoaded = true;
    notifyListeners();
  }

  // ---------------- OCR الاختياري ----------------

  Future<void> setApiKey(String value) async {
    apiKey = value.trim();
    notifyListeners();
    try {
      await _secureStorage.write(key: _keyApiKey, value: apiKey);
    } catch (_) {
      // يبقى المفتاح صالحًا لهذه الجلسة حتى لو تعذّر حفظه بشكل دائم
    }
  }

  Future<void> clearApiKey() async {
    apiKey = null;
    useCloudOcr = false;
    notifyListeners();
    try {
      await _secureStorage.delete(key: _keyApiKey);
    } catch (_) {}
    await _repo.setSetting(_kUseCloudOcr, false);
  }

  Future<void> setModel(String value) async {
    model = value.trim().isEmpty ? _defaultModel : value.trim();
    notifyListeners();
    try {
      await _secureStorage.write(key: _keyModel, value: model);
    } catch (_) {}
  }

  Future<void> setUseCloudOcr(bool value) async {
    useCloudOcr = value;
    await _repo.setSetting(_kUseCloudOcr, value);
    notifyListeners();
  }

  /// اختيار محرك OCR الفعلي بحسب تفضيل المستخدم — افتراضيًا محلي (القسم 23:
  /// اختياري بالكامل، ليس Dependency). لا يتحوّل لسحابي إلا بتفعيل صريح
  /// [useCloudOcr] مع وجود مفتاح فعليًا.
  OcrEngine buildOcrEngine() {
    if (useCloudOcr && hasApiKey) {
      return OptionalCloudOcrEngine(apiKey: apiKey!, apiBaseUrl: apiBaseUrl, model: model);
    }
    return LocalOcrEngine();
  }

  // ---------------- إعدادات عامة (القسم 34) ----------------

  Future<void> setCurrencyCode(String value) async {
    currencyCode = value.trim().isEmpty ? 'SAR' : value.trim();
    await _repo.setSetting(_kCurrency, currencyCode);
    notifyListeners();
  }

  Future<void> setMonthStartDay(int value) async {
    monthStartDay = value.clamp(1, 28);
    await _repo.setSetting(_kMonthStartDay, monthStartDay);
    notifyListeners();
  }

  Future<void> setDefaultReorderPoint(double value) async {
    defaultReorderPoint = value < 0 ? 0 : value;
    await _repo.setSetting(_kDefaultReorderPoint, defaultReorderPoint);
    notifyListeners();
  }

  Future<void> setNearExpiryDays({int? days1, int? days2}) async {
    if (days1 != null) nearExpiryDays1 = days1 < 0 ? 0 : days1;
    if (days2 != null) nearExpiryDays2 = days2 < 0 ? 0 : days2;
    if (nearExpiryDays2 < nearExpiryDays1) nearExpiryDays2 = nearExpiryDays1;
    await _repo.setSetting(_kNearExpiry1, nearExpiryDays1);
    await _repo.setSetting(_kNearExpiry2, nearExpiryDays2);
    notifyListeners();
  }

  Future<void> setDefaultReportFormat(String value) async {
    defaultReportFormat = value;
    await _repo.setSetting(_kReportFormat, value);
    notifyListeners();
  }

  Future<void> setDefaultBranchId(String? value) async {
    defaultBranchId = value;
    await _repo.setSetting(_kDefaultBranchId, value);
    notifyListeners();
  }

  Future<void> setDefaultCategoryId(String? value) async {
    defaultCategoryId = value;
    await _repo.setSetting(_kDefaultCategoryId, value);
    notifyListeners();
  }

  Future<void> markBackupNow() async {
    lastBackupAt = DateTime.now();
    await _repo.setSetting(_kLastBackupAt, lastBackupAt!.toIso8601String());
    notifyListeners();
  }
}
