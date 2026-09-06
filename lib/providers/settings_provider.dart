import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../services/mistral_api_client.dart';
import '../services/ocr_manager.dart';
import '../services/ocr_space_api_client.dart';
import '../services/repository.dart';

/// كل إعدادات التطبيق. المفاتيح السرّية (Mistral/OCR.space) عبر
/// Keychain/Keystore، مستقلَّان تمامًا بلا خلط بينهما؛ كل الإعدادات الأخرى —
/// غير الحسّاسة — عبر Repository.
///
/// ⚠️ الاستخراج السحابي الاختياري مناسب للتجربة والاستخدام الشخصي فقط. لنشر
/// عام (خصوصًا Flutter Web) لا يمكن إخفاء مفتاح API حقيقةً — استخدم خادمًا
/// وسيطًا (Backend Proxy) بدلًا من ذلك؛ mistral_api_client.dart/ocr_space_api_client.dart
/// مصمَّمان كطبقة منفصلة تمامًا بحيث يمكن استبدالهما بنداء proxy لاحقًا بلا
/// تغيير OcrEngine أو أي شاشة.
class SettingsProvider extends ChangeNotifier {
  static const _keyMistralApiKey = 'mistral_api_key';
  static const _keyOcrSpaceApiKey = 'ocr_space_api_key';
  static const _keyEngineSelection = 'ocr_engine_selection';
  static const _keyAutoFallback = 'ocr_auto_fallback_enabled';

  // مفاتيح صندوق الإعدادات العادي (Hive) — غير سرّية
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
  final MistralApiClient _mistralClient = const MistralApiClient();
  final OcrSpaceApiClient _ocrSpaceClient = const OcrSpaceApiClient();

  String? mistralApiKey;
  String? ocrSpaceApiKey;
  OcrEngineSelection engineSelection = OcrEngineSelection.mistral;
  bool autoFallbackEnabled = true;

  MistralHealthResult? mistralHealthResult;
  OcrSpaceHealthResult? ocrSpaceHealthResult;
  bool isTestingMistral = false;
  bool isTestingOcrSpace = false;

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
    }

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

  // ---------------- OCR الاختياري (Mistral + OCR.space) ----------------

  Future<void> setMistralApiKey(String value) async {
    mistralApiKey = value.trim();
    mistralHealthResult = null;
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

  Future<void> testMistralConnection() async {
    if (!hasMistralKey) return;
    isTestingMistral = true;
    notifyListeners();
    mistralHealthResult = await _mistralClient.testConnection(mistralApiKey!);
    isTestingMistral = false;
    notifyListeners();
  }

  Future<void> testOcrSpaceConnection() async {
    if (!hasOcrSpaceKey) return;
    isTestingOcrSpace = true;
    notifyListeners();
    ocrSpaceHealthResult = await _ocrSpaceClient.testConnection(ocrSpaceApiKey!);
    isTestingOcrSpace = false;
    notifyListeners();
  }

  /// نقطة الدخول الوحيدة لبناء منسّق OCR — التطبيق يستمر Offline بالكامل
  /// (Excel/Dashboard/بحث/تقارير/إدخال يدوي) بلا أي مفتاح على الإطلاق؛ هذا
  /// يُستخدَم فقط عند استيراد صورة أو PDF.
  OcrManager buildOcrManager() => OcrManager(
        mistralApiKey: mistralApiKey,
        ocrSpaceApiKey: ocrSpaceApiKey,
        selection: engineSelection,
        autoFallbackEnabled: autoFallbackEnabled,
      );

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
