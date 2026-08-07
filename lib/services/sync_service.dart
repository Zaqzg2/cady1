import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/customer.dart';
import '../models/product.dart';
import '../models/invoice.dart';
import '../models/receipt.dart';
import '../models/offer.dart';
import 'db_service.dart';
import 'settings_service.dart';
import 'share_util.dart';

/// قائمة العمليات المعلّقة (بانتظار المزامنة) حاليًا — تُستخدم في شاشة
/// "معاينة العمليات المعلقة" وفي بناء ملف التصدير
class PendingSyncPreview {
  final List<Customer> customers;
  final List<Invoice> invoices;
  final List<Receipt> receipts;

  const PendingSyncPreview({
    required this.customers,
    required this.invoices,
    required this.receipts,
  });

  int get totalCount => customers.length + invoices.length + receipts.length;
  bool get isEmpty => totalCount == 0;
}

/// نتيجة تطبيق ملف تحديث وارد من المدير
class ManagerUpdateApplyResult {
  final int productsApplied;
  final int pricesApplied;
  final int customersApplied;
  final int offersApplied;
  final bool settingsApplied;
  final int updateNumber;
  final bool isForAnotherRep;

  const ManagerUpdateApplyResult({
    required this.productsApplied,
    required this.pricesApplied,
    required this.customersApplied,
    required this.offersApplied,
    required this.settingsApplied,
    required this.updateNumber,
    required this.isForAnotherRep,
  });

  int get totalApplied =>
      productsApplied + pricesApplied + customersApplied + offersApplied;
}

/// تُدار من خلال هذه الخدمة عمليتا المزامنة لدى المندوب:
/// 1) تصدير العمليات المعلّقة (الفواتير/السندات/العملاء الجدد) كملف JSON
///    يُشارَك مع المدير (مشاركة/تنزيل مباشر من الذاكرة — بلا كتابة ملفات
///    على القرص، فتعمل بنفس الطريقة على الجوال والويب).
/// 2) استيراد ملف "تحديث" صادر من المدير (منتجات/أسعار/عملاء/عروض/إعدادات).
class SyncService {
  SyncService._();
  static final SyncService instance = SyncService._();
  static const _uuid = Uuid();
  static const _formatVersion = 1;

  static const _kLastExportAt = 'sync_last_export_at';
  static const _kLastExportJson = 'sync_last_export_json';
  static const _kLastExportFileName = 'sync_last_export_filename';
  static const _kLastImportAt = 'sync_last_import_at';

  Future<bool> isRepProfileConfigured() async {
    final s = await SettingsService.instance.load();
    return s.repCode.trim().isNotEmpty;
  }

  // ---------------- معاينة العمليات المعلّقة ----------------
  Future<PendingSyncPreview> getPendingPreview() async {
    final items = await DbService.instance.getActiveQueueItems();
    final customers = <Customer>[];
    final invoices = <Invoice>[];
    final receipts = <Receipt>[];
    for (final item in items) {
      final type = item['entityType'] as String;
      final id = item['entityId'] as String;
      switch (type) {
        case 'customer':
          final c = await DbService.instance.getCustomerById(id);
          if (c != null) customers.add(c);
          break;
        case 'invoice':
          final inv = await DbService.instance.getInvoiceById(id);
          if (inv != null) invoices.add(inv);
          break;
        case 'receipt':
          final r = await DbService.instance.getReceiptById(id);
          if (r != null) receipts.add(r);
          break;
      }
    }
    return PendingSyncPreview(
        customers: customers, invoices: invoices, receipts: receipts);
  }

  Future<int> countPending() => DbService.instance.countActiveQueueItems();

  String _exportFileName(String repCode) {
    final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final safeRepCode = repCode.trim().isEmpty ? 'مندوب' : repCode.trim();
    return 'مزامنة_${safeRepCode}_$stamp.json';
  }

  // ---------------- تصدير بيانات اليوم (العمليات المعلّقة) ----------------
  /// يجمع فقط العمليات التي حالتها ما زالت غير مؤكَّدة، ويبني محتوى JSON
  /// في الذاكرة مباشرة (بلا كتابة ملف). يُعيد null إن لم توجد عمليات معلّقة.
  Future<String?> exportPendingData() async {
    final settings = await SettingsService.instance.load();
    final queueItems = await DbService.instance.getActiveQueueItems();
    if (queueItems.isEmpty) return null;

    final preview = await getPendingPreview();
    final batchId = _uuid.v4();

    final payload = {
      'kind': 'rep_sync_data',
      'formatVersion': _formatVersion,
      'batchId': batchId,
      'repCode': settings.repCode,
      'repName': settings.repName,
      'deviceName': settings.deviceName,
      'exportedAt': DateTime.now().toIso8601String(),
      'customers': preview.customers.map((c) => c.toMap()).toList(),
      'invoices': preview.invoices.map((i) => i.toMap()).toList(),
      'receipts': preview.receipts.map((r) => r.toMap()).toList(),
    };
    final json = jsonEncode(payload);
    final fileName = _exportFileName(settings.repCode);

    final queueIds = queueItems.map((e) => e['id'] as String).toList();
    await DbService.instance.markQueueExported(queueIds, batchId);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLastExportAt, DateTime.now().toIso8601String());
    await prefs.setString(_kLastExportJson, json);
    await prefs.setString(_kLastExportFileName, fileName);

    return json;
  }

  /// يبني الملف (إن وُجدت عمليات معلّقة) ثم يفتح واجهة المشاركة/التنزيل
  Future<bool> exportAndShare() async {
    final json = await exportPendingData();
    if (json == null) return false;
    final prefs = await SharedPreferences.getInstance();
    final fileName = prefs.getString(_kLastExportFileName) ?? 'مزامنة.json';
    final bytes = Uint8List.fromList(utf8.encode(json));
    await ShareUtil.shareBytes(bytes, fileName,
        mimeType: 'application/json',
        text: 'بيانات مزامنة المندوب - تطبيق كادي للمنظفات');
    return true;
  }

  /// إعادة مشاركة آخر ملف صُدِّر تمامًا كما هو (بلا إعادة استعلام أو تغيير
  /// الحالة) — تُستخدم إذا لم يصل الملف للمدير لأي سبب
  Future<bool> reExportLastFile() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_kLastExportJson);
    if (json == null) return false;
    final fileName = prefs.getString(_kLastExportFileName) ?? 'مزامنة.json';
    final bytes = Uint8List.fromList(utf8.encode(json));
    await ShareUtil.shareBytes(bytes, fileName,
        mimeType: 'application/json',
        text: 'إعادة إرسال بيانات مزامنة المندوب');
    return true;
  }

  Future<bool> hasLastExportFile() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kLastExportJson) != null;
  }

  Future<DateTime?> getLastExportAt() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kLastExportAt);
    return raw != null ? DateTime.tryParse(raw) : null;
  }

  Future<DateTime?> getLastImportAt() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kLastImportAt);
    return raw != null ? DateTime.tryParse(raw) : null;
  }

  // ---------------- استيراد تحديثات من المدير ----------------
  /// يفتح منتقي ملفات ويعيد محتوى ملف JSON كنص مباشرة (withData: true تضمن
  /// توفر البايتات على كل المنصات، بما فيها الويب حيث لا يوجد مسار ملف
  /// حقيقي أصلاً)
  Future<String?> pickUpdateContent() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );
    final bytes = result?.files.single.bytes;
    if (bytes == null) return null;
    return utf8.decode(bytes);
  }

  /// يطبّق محتوى ملف تحديث (منتجات/أسعار/عملاء/عروض/إعدادات) صادر من تطبيق
  /// المدير. يرمي [FormatException] إن كان المحتوى غير صالح.
  Future<ManagerUpdateApplyResult> importManagerUpdate(String content) async {
    final Map<String, dynamic> data =
        Map<String, dynamic>.from(jsonDecode(content));

    if (data['kind'] != 'manager_update') {
      throw const FormatException(
          'هذا الملف ليس ملف تحديث صادر من تطبيق المدير');
    }

    final settings = await SettingsService.instance.load();
    final targetRepCode = data['targetRepCode'] as String?;
    final isForAnotherRep = targetRepCode != null &&
        targetRepCode.trim().isNotEmpty &&
        settings.repCode.trim().isNotEmpty &&
        targetRepCode.trim() != settings.repCode.trim();

    final includes = Map<String, dynamic>.from(data['includes'] ?? {});
    int productsApplied = 0;
    int pricesApplied = 0;
    int customersApplied = 0;
    int offersApplied = 0;
    bool settingsApplied = false;
    bool settingsChanged = false;

    if (includes['products'] == true && data['products'] != null) {
      for (final e in (data['products'] as List)) {
        final p = Product.fromMap(Map<String, dynamic>.from(e));
        await DbService.instance.upsertProduct(p);
        productsApplied++;
      }
    }

    if (includes['prices'] == true && data['priceUpdates'] != null) {
      for (final e in (data['priceUpdates'] as List)) {
        final m = Map<String, dynamic>.from(e);
        final id = m['id'] as String?;
        final price = (m['price'] as num?)?.toDouble();
        if (id != null && price != null) {
          final ok = await DbService.instance.updateProductPrice(id, price);
          if (ok) pricesApplied++;
        }
      }
    }

    if (includes['customers'] == true && data['customers'] != null) {
      for (final e in (data['customers'] as List)) {
        final c = Customer.fromMap(Map<String, dynamic>.from(e));
        c.syncStatus = 'synced';
        await DbService.instance.upsertCustomer(c);
        customersApplied++;
      }
    }

    if (includes['offers'] == true && data['offers'] != null) {
      for (final e in (data['offers'] as List)) {
        final o = Offer.fromMap(Map<String, dynamic>.from(e));
        await DbService.instance.upsertOffer(o);
        offersApplied++;
      }
    }

    if (includes['settings'] == true && data['companySettings'] != null) {
      final incoming = Map<String, dynamic>.from(data['companySettings']);
      settings.companyName =
          incoming['companyName'] as String? ?? settings.companyName;
      settings.companyPhone =
          incoming['companyPhone'] as String? ?? settings.companyPhone;
      settings.companyAddress =
          incoming['companyAddress'] as String? ?? settings.companyAddress;
      settingsApplied = true;
      settingsChanged = true;
    }

    // تأكيد استلام الدفعات المذكورة من طرف المدير — يُغلق حلقة المزامنة
    // ويحوّل عناصر الطابور من "exported" إلى "synced"
    final acks = (data['acknowledgedBatchIds'] as List?) ?? const [];
    for (final batchId in acks) {
      await DbService.instance.markQueueSyncedByBatch(batchId as String);
    }

    final updateNumber = (data['updateNumber'] as num?)?.toInt() ?? 0;
    if (updateNumber > settings.lastImportedUpdateNumber) {
      settings.lastImportedUpdateNumber = updateNumber;
      settingsChanged = true;
    }

    if (settingsChanged) {
      await SettingsService.instance.save(settings);
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLastImportAt, DateTime.now().toIso8601String());

    return ManagerUpdateApplyResult(
      productsApplied: productsApplied,
      pricesApplied: pricesApplied,
      customersApplied: customersApplied,
      offersApplied: offersApplied,
      settingsApplied: settingsApplied,
      updateNumber: updateNumber,
      isForAnotherRep: isForAnotherRep,
    );
  }
}
