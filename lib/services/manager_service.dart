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
import '../models/representative.dart';
import '../models/sync_log_entry.dart';
import '../models/company_settings.dart';
import 'db_service.dart';
import 'settings_service.dart';
import 'share_util.dart';

/// نتيجة معاينة ملف مندوب قبل اعتماده (شاشة الاستيراد)
class RepImportPreview {
  final String logId; // معرف سجل المزامنة المرحلي لهذه العملية
  final String? repCode;
  final String? repName;
  final bool isNewRep;
  final int invoicesCount;
  final int receiptsCount;
  final int newCustomersCount;
  final int duplicatesCount;
  final int errorsCount;
  final List<String> errorMessages;

  const RepImportPreview({
    required this.logId,
    required this.repCode,
    required this.repName,
    required this.isNewRep,
    required this.invoicesCount,
    required this.receiptsCount,
    required this.newCustomersCount,
    required this.duplicatesCount,
    required this.errorsCount,
    required this.errorMessages,
  });
}

/// نتيجة اعتماد (أو إعادة) استيراد ملف مندوب
class RepImportResult {
  final int invoicesImported;
  final int receiptsImported;
  final int customersImported;

  const RepImportResult({
    required this.invoicesImported,
    required this.receiptsImported,
    required this.customersImported,
  });
}

/// صف واحد في جدول "آخر مزامنة لكل مندوب" بلوحة التحكم
class RepSyncSummary {
  final Representative representative;
  final DateTime? lastSyncAt;
  final int lastOperationsCount;

  const RepSyncSummary({
    required this.representative,
    required this.lastSyncAt,
    required this.lastOperationsCount,
  });
}

/// إحصائيات لوحة تحكم المدير
class ManagerDashboardStats {
  final int repsCount;
  final int receivedOperationsCount;
  final int unimportedOperationsCount;
  final List<RepSyncSummary> repSummaries;

  const ManagerDashboardStats({
    required this.repsCount,
    required this.receivedOperationsCount,
    required this.unimportedOperationsCount,
    required this.repSummaries,
  });
}

/// كل منطق وضع المدير: إدارة المندوبين، استيراد ملفاتهم (معاينة ثم اعتماد
/// أو إلغاء)، إنشاء ملفات التحديث الصادرة إليهم، وإحصائيات لوحة التحكم.
/// كل مشاركة/استيراد ملفات يعمل بالبايتات مباشرة من الذاكرة (بلا كتابة على
/// القرص) فيعمل بنفس الطريقة على الجوال والويب.
class ManagerService {
  ManagerService._();
  static final ManagerService instance = ManagerService._();
  static const _uuid = Uuid();
  static const _formatVersion = 1;
  static const _kNextUpdateNumber = 'manager_next_update_number';

  // ==================== المندوبون ====================
  Future<List<Representative>> getRepresentatives() =>
      DbService.instance.getRepresentatives();

  Future<void> saveRepresentative(Representative r) =>
      DbService.instance.upsertRepresentative(r);

  Future<void> deleteRepresentative(String id) =>
      DbService.instance.deleteRepresentative(id);

  Future<void> setActive(Representative r, bool active) async {
    r.isActive = active;
    await DbService.instance.upsertRepresentative(r);
  }

  Future<void> resetLastSync(Representative r) async {
    r.lastSyncAt = null;
    await DbService.instance.upsertRepresentative(r);
  }

  /// يتحقق من عدم تكرار رمز المندوب (باستثناء المندوب الحالي عند التعديل)
  Future<bool> isRepCodeTaken(String repCode, {String? excludingId}) async {
    final existing =
        await DbService.instance.getRepresentativeByCode(repCode.trim());
    if (existing == null) return false;
    if (excludingId != null && existing.id == excludingId) return false;
    return true;
  }

  // ==================== الاستيراد من مندوب ====================
  /// يفتح منتقي ملفات ويعيد محتوى ملف JSON واسمه الأصلي معًا (withData:
  /// true تضمن توفر البايتات على كل المنصات، بما فيها الويب)
  Future<(String content, String fileName)?> pickRepFileContent() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );
    final file = result?.files.single;
    final bytes = file?.bytes;
    if (bytes == null || file == null) return null;
    return (utf8.decode(bytes), file.name);
  }

  /// يحسب إحصائيات المعاينة من محتوى ملف مندوب، ويسجّل عملية "معلّقة" في
  /// سجل المزامنة (مع حفظ المحتوى الخام لدعم إعادة الاستيراد لاحقًا) دون
  /// كتابة أي بيانات فعلية بعد — الكتابة تتم فقط عند "اعتماد".
  Future<RepImportPreview> stageImport(String content,
      {String fileName = 'ملف مزامنة'}) async {
    final Map<String, dynamic> data =
        Map<String, dynamic>.from(jsonDecode(content));

    if (data['kind'] != 'rep_sync_data') {
      throw const FormatException('هذا الملف ليس ملف بيانات مندوب صالحًا');
    }

    final repCode = data['repCode'] as String?;
    final repName = data['repName'] as String?;
    Representative? rep;
    if (repCode != null && repCode.trim().isNotEmpty) {
      rep = await DbService.instance.getRepresentativeByCode(repCode.trim());
    }
    final isNewRep = rep == null;

    int newCustomersCount = 0;
    int duplicatesCount = 0;
    int errorsCount = 0;
    final errorMessages = <String>[];
    void addError(String msg) {
      errorsCount++;
      if (errorMessages.length < 20) errorMessages.add(msg);
    }

    final rawCustomers = (data['customers'] as List?) ?? const [];
    for (final e in rawCustomers) {
      try {
        final c = Customer.fromMap(Map<String, dynamic>.from(e));
        final exists = await DbService.instance.getCustomerById(c.id);
        if (exists == null) {
          newCustomersCount++;
        } else {
          duplicatesCount++;
        }
      } catch (_) {
        addError('سجل عميل غير صالح');
      }
    }

    int invoicesCount = 0;
    final rawInvoices = (data['invoices'] as List?) ?? const [];
    for (final e in rawInvoices) {
      try {
        final inv = Invoice.fromMap(Map<String, dynamic>.from(e));
        invoicesCount++;
        final exists = await DbService.instance.getInvoiceById(inv.id);
        if (exists != null) duplicatesCount++;
      } catch (_) {
        addError('فاتورة غير صالحة');
      }
    }

    int receiptsCount = 0;
    final rawReceipts = (data['receipts'] as List?) ?? const [];
    for (final e in rawReceipts) {
      try {
        final r = Receipt.fromMap(Map<String, dynamic>.from(e));
        receiptsCount++;
        final exists = await DbService.instance.getReceiptById(r.id);
        if (exists != null) duplicatesCount++;
      } catch (_) {
        addError('سند غير صالح');
      }
    }

    final logId = _uuid.v4();
    final logEntry = SyncLogEntry(
      id: logId,
      type: 'import',
      fileName: fileName,
      repId: rep?.id,
      repCode: repCode,
      repName: repName,
      status: 'pending',
      recordCount: invoicesCount + receiptsCount + rawCustomers.length,
      details: {
        'invoicesCount': invoicesCount,
        'receiptsCount': receiptsCount,
        'newCustomersCount': newCustomersCount,
        'duplicatesCount': duplicatesCount,
        'errorsCount': errorsCount,
        'isNewRep': isNewRep,
      },
      payload: content,
    );
    await DbService.instance.insertSyncLog(logEntry);

    return RepImportPreview(
      logId: logId,
      repCode: repCode,
      repName: repName,
      isNewRep: isNewRep,
      invoicesCount: invoicesCount,
      receiptsCount: receiptsCount,
      newCustomersCount: newCustomersCount,
      duplicatesCount: duplicatesCount,
      errorsCount: errorsCount,
      errorMessages: errorMessages,
    );
  }

  /// يعتمد عملية استيراد مرحلية: يكتب كل السجلات الصالحة في قاعدة بيانات
  /// المدير، ويحدّث بيانات المندوب (آخر مزامنة)
  Future<RepImportResult> approveImport(String logId) async {
    final log = await DbService.instance.getSyncLogById(logId);
    if (log == null || log.payload == null) {
      throw const FormatException('تعذر العثور على بيانات هذا الاستيراد');
    }
    final result = await _commitPayload(log);
    await DbService.instance.updateSyncLogStatus(logId, 'approved');
    return result;
  }

  Future<void> cancelImport(String logId) async {
    await DbService.instance.updateSyncLogStatus(logId, 'cancelled');
  }

  /// إعادة تطبيق استيراد سابق من سجل المزامنة (حتى لو لم يعد الملف الأصلي
  /// موجودًا) اعتمادًا على النسخة المحفوظة من محتوى الملف
  Future<RepImportResult> reImport(String logId) async {
    final log = await DbService.instance.getSyncLogById(logId);
    if (log == null || log.payload == null) {
      throw const FormatException('تعذر العثور على بيانات هذا الاستيراد');
    }
    final result = await _commitPayload(log);
    await DbService.instance.updateSyncLogStatus(logId, 'approved');
    return result;
  }

  Future<RepImportResult> _commitPayload(SyncLogEntry log) async {
    final Map<String, dynamic> data =
        Map<String, dynamic>.from(jsonDecode(log.payload!));

    final repCode = data['repCode'] as String?;
    final repName = data['repName'] as String?;
    Representative? rep;
    if (repCode != null && repCode.trim().isNotEmpty) {
      rep = await DbService.instance.getRepresentativeByCode(repCode.trim());
      rep ??= Representative(
        id: _uuid.v4(),
        repCode: repCode.trim(),
        repName: (repName == null || repName.trim().isEmpty)
            ? repCode.trim()
            : repName.trim(),
      );
    }

    int customersImported = 0;
    final rawCustomers = (data['customers'] as List?) ?? const [];
    for (final e in rawCustomers) {
      try {
        final c = Customer.fromMap(Map<String, dynamic>.from(e));
        c.syncStatus = 'synced';
        c.sourceRepCode = repCode;
        await DbService.instance.upsertCustomer(c);
        customersImported++;
      } catch (_) {
        // الأخطاء احتُسبت أثناء المعاينة، يُتجاوز السجل غير الصالح هنا فقط
      }
    }

    int invoicesImported = 0;
    final rawInvoices = (data['invoices'] as List?) ?? const [];
    for (final e in rawInvoices) {
      try {
        final inv = Invoice.fromMap(Map<String, dynamic>.from(e));
        inv.syncStatus = 'synced';
        inv.sourceRepCode = repCode;
        await DbService.instance.upsertInvoice(inv);
        invoicesImported++;
      } catch (_) {}
    }

    int receiptsImported = 0;
    final rawReceipts = (data['receipts'] as List?) ?? const [];
    for (final e in rawReceipts) {
      try {
        final r = Receipt.fromMap(Map<String, dynamic>.from(e));
        r.syncStatus = 'synced';
        r.sourceRepCode = repCode;
        await DbService.instance.upsertReceipt(r);
        receiptsImported++;
      } catch (_) {}
    }

    if (rep != null) {
      rep.lastSyncAt = DateTime.now();
      await DbService.instance.upsertRepresentative(rep);
    }

    return RepImportResult(
      invoicesImported: invoicesImported,
      receiptsImported: receiptsImported,
      customersImported: customersImported,
    );
  }

  // ==================== سجل المزامنة ====================
  Future<List<SyncLogEntry>> getLogs({String? type}) =>
      DbService.instance.getSyncLogs(type: type);

  // ==================== التصدير (إنشاء تحديث) ====================
  /// رقم التحديث القادم دون استهلاكه (للعرض قبل الإنشاء الفعلي)
  Future<int> peekNextUpdateNumber() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getInt(_kNextUpdateNumber) ?? 0) + 1;
  }

  Future<int> _consumeNextUpdateNumber() async {
    final prefs = await SharedPreferences.getInstance();
    final next = (prefs.getInt(_kNextUpdateNumber) ?? 0) + 1;
    await prefs.setInt(_kNextUpdateNumber, next);
    return next;
  }

  /// يبني محتوى ملف تحديث (JSON) يضم الفئات المختارة، لمندوب محدد أو لكل
  /// المندوبين. categories المتاحة: products, prices, customers, offers,
  /// settings
  Future<(String json, String fileName)> _buildUpdatePackage({
    required Set<String> categories,
    String? targetRepCode,
  }) async {
    final updateNumber = await _consumeNextUpdateNumber();
    final includes = {
      'products': categories.contains('products'),
      'prices': categories.contains('prices'),
      'customers': categories.contains('customers'),
      'offers': categories.contains('offers'),
      'settings': categories.contains('settings'),
    };

    final payload = <String, dynamic>{
      'kind': 'manager_update',
      'formatVersion': _formatVersion,
      'updateNumber': updateNumber,
      'generatedAt': DateTime.now().toIso8601String(),
      'targetRepCode': targetRepCode,
      'includes': includes,
    };

    int productsCount = 0;
    int customersCount = 0;
    int offersCount = 0;

    if (includes['products'] == true) {
      final products = await DbService.instance.getProducts();
      payload['products'] = products.map((p) => p.toMap()).toList();
      productsCount = products.length;
    }

    if (includes['prices'] == true) {
      final products = await DbService.instance.getProducts();
      payload['priceUpdates'] =
          products.map((p) => {'id': p.id, 'price': p.price}).toList();
    }

    if (includes['customers'] == true) {
      final customers = await DbService.instance.getCustomers();
      payload['customers'] = customers.map((c) => c.toMap()).toList();
      customersCount = customers.length;
    }

    if (includes['offers'] == true) {
      final offers = await DbService.instance.getOffers();
      payload['offers'] = offers.map((o) => o.toMap()).toList();
      offersCount = offers.length;
    }

    if (includes['settings'] == true) {
      final CompanySettings settings = await SettingsService.instance.load();
      payload['companySettings'] = {
        'companyName': settings.companyName,
        'companyPhone': settings.companyPhone,
        'companyAddress': settings.companyAddress,
      };
    }

    // إرفاق تأكيدات استلام آخر عمليات الاستيراد المُعتمدة من هذا المندوب،
    // لإغلاق حلقة المزامنة لديه تلقائيًا عند استيراده لهذا التحديث
    if (targetRepCode != null && targetRepCode.trim().isNotEmpty) {
      final approvedImports = (await DbService.instance.getSyncLogs(
              type: 'import'))
          .where((l) =>
              l.status == 'approved' &&
              l.repCode != null &&
              l.repCode!.trim() == targetRepCode.trim())
          .toList();
      final batchIds = <String>[];
      for (final l in approvedImports) {
        if (l.payload == null) continue;
        try {
          final d = Map<String, dynamic>.from(jsonDecode(l.payload!));
          final b = d['batchId'] as String?;
          if (b != null) batchIds.add(b);
        } catch (_) {}
      }
      payload['acknowledgedBatchIds'] = batchIds;
    }

    final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final target = (targetRepCode != null && targetRepCode.trim().isNotEmpty)
        ? targetRepCode.trim()
        : 'الكل';
    final fileName = 'تحديث_${target}_رقم${updateNumber}_$stamp.json';
    final json = jsonEncode(payload);

    await DbService.instance.insertSyncLog(SyncLogEntry(
      id: _uuid.v4(),
      type: 'export',
      fileName: fileName,
      repCode: targetRepCode,
      status: 'sent',
      recordCount: productsCount + customersCount + offersCount,
      details: {
        'updateNumber': updateNumber,
        'includes': includes,
        'productsCount': productsCount,
        'customersCount': customersCount,
        'offersCount': offersCount,
      },
    ));

    return (json, fileName);
  }

  Future<void> createUpdatePackageAndShare({
    required Set<String> categories,
    String? targetRepCode,
  }) async {
    final (json, fileName) = await _buildUpdatePackage(
        categories: categories, targetRepCode: targetRepCode);
    final bytes = Uint8List.fromList(utf8.encode(json));
    await ShareUtil.shareBytes(bytes, fileName,
        mimeType: 'application/json', text: 'ملف تحديث - تطبيق كادي للمنظفات');
  }

  // ==================== لوحة التحكم ====================
  Future<ManagerDashboardStats> getDashboardStats() async {
    final reps = await DbService.instance.getRepresentatives();
    final importLogs = await DbService.instance.getSyncLogs(type: 'import');

    final approvedLogs =
        importLogs.where((l) => l.status == 'approved').toList();
    final receivedOperationsCount =
        approvedLogs.fold<int>(0, (sum, l) => sum + l.recordCount);

    final pendingLogs =
        importLogs.where((l) => l.status == 'pending').toList();
    final unimportedOperationsCount =
        pendingLogs.fold<int>(0, (sum, l) => sum + l.recordCount);

    final summaries = <RepSyncSummary>[];
    for (final rep in reps) {
      final repLogs = approvedLogs
          .where((l) =>
              l.repCode != null && l.repCode!.trim() == rep.repCode.trim())
          .toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      final last = repLogs.isNotEmpty ? repLogs.first : null;
      summaries.add(RepSyncSummary(
        representative: rep,
        lastSyncAt: rep.lastSyncAt,
        lastOperationsCount: last?.recordCount ?? 0,
      ));
    }

    return ManagerDashboardStats(
      repsCount: reps.length,
      receivedOperationsCount: receivedOperationsCount,
      unimportedOperationsCount: unimportedOperationsCount,
      repSummaries: summaries,
    );
  }

  // ==================== العروض ====================
  Future<List<Offer>> getOffers() => DbService.instance.getOffers();
  Future<void> saveOffer(Offer o) => DbService.instance.upsertOffer(o);
  Future<void> deleteOffer(String id) => DbService.instance.deleteOffer(id);
}
