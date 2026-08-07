import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import '../models/customer.dart';
import '../models/product.dart';
import '../models/invoice.dart';
import '../models/receipt.dart';
import '../models/representative.dart';
import '../models/offer.dart';
import '../models/sync_log_entry.dart';

/// حالات عنصر طابور المزامنة (Sync Queue)
class SyncQueueStatus {
  static const pending = 'pending'; // لم يُصدَّر بعد
  static const exported = 'exported'; // صُدِّر ضمن ملف لكن لم يُؤكَّد استلامه
  static const synced = 'synced'; // تم تأكيد استلامه من المدير
}

/// طبقة الوصول لقاعدة بيانات التطبيق — Hive بالكامل (nosql محلي سريع
/// يعمل بنفس الطريقة على الجوال والويب عبر IndexedDB). كل سجل يُخزَّن
/// كـ Map بنفس صيغة toMap()/fromMap() الموجودة أصلاً بكل موديل، بالمفتاح
/// id — بدون أي TypeAdapter لأن كل القيم أصلاً أنواع أساسية
/// (String/num/bool/List/Map) يدعمها Hive مباشرة.
class DbService {
  DbService._();
  static final DbService instance = DbService._();

  /// رقم "جيل" مخطط البيانات — لا يقود أي ترحيل (Hive بلا مخطط ثابت أصلاً)،
  /// يُستخدم فقط للعرض التعريفي في شاشة إعدادات المزامنة
  static const int schemaVersion = 1;

  static const _customersBoxName = 'customers';
  static const _productsBoxName = 'products';
  static const _invoicesBoxName = 'invoices';
  static const _receiptsBoxName = 'receipts';
  static const _syncQueueBoxName = 'sync_queue';
  static const _representativesBoxName = 'representatives';
  static const _syncLogBoxName = 'sync_log';
  static const _offersBoxName = 'offers';

  Future<void>? _initFuture;
  late Box _customersBox;
  late Box _productsBox;
  late Box _invoicesBox;
  late Box _receiptsBox;
  late Box _syncQueueBox;
  late Box _representativesBox;
  late Box _syncLogBox;
  late Box _offersBox;

  /// نستخدم Future واحدة محفوظة (memoized) بدل علامة boolean بسيطة: لو
  /// استدعت أكثر من شاشة دالة من دوال قاعدة البيانات "بالتوازي" (كما يحدث
  /// مثلاً مع عدة FutureBuilder في نفس الإطار)، فكل الاستدعاءات تنتظر نفس
  /// عملية التهيئة الجارية بدل أن يحاول كل استدعاء تشغيل تهيئة منفصلة قد
  /// تحاول إعادة تعيين حقول late أكثر من مرة.
  Future<void> _ensureReady() {
    _initFuture ??= _init();
    return _initFuture!;
  }

  Future<void> _init() async {
    await Hive.initFlutter();
    _customersBox = await Hive.openBox(_customersBoxName);
    _productsBox = await Hive.openBox(_productsBoxName);
    _invoicesBox = await Hive.openBox(_invoicesBoxName);
    _receiptsBox = await Hive.openBox(_receiptsBoxName);
    _syncQueueBox = await Hive.openBox(_syncQueueBoxName);
    _representativesBox = await Hive.openBox(_representativesBoxName);
    _syncLogBox = await Hive.openBox(_syncLogBoxName);
    _offersBox = await Hive.openBox(_offersBoxName);
  }

  /// يحوّل أي Map يعيدها Hive (قد تكون Map<dynamic, dynamic> وقت التشغيل)
  /// إلى Map<String, dynamic> التي تتوقعها دوال fromMap() في كل موديل
  Map<String, dynamic> _asStringMap(dynamic raw) =>
      Map<String, dynamic>.from(raw as Map);

  // ---------------- العملاء ----------------
  Future<void> upsertCustomer(Customer c) async {
    await _ensureReady();
    await _customersBox.put(c.id, c.toMap());
  }

  Future<void> deleteCustomer(String id) async {
    await _ensureReady();
    await _customersBox.delete(id);
  }

  Future<List<Customer>> getCustomers() async {
    await _ensureReady();
    final list = _customersBox.values
        .map((v) => Customer.fromMap(_asStringMap(v)))
        .toList();
    list.sort((a, b) {
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return list;
  }

  Future<Customer?> getCustomerById(String id) async {
    await _ensureReady();
    final raw = _customersBox.get(id);
    if (raw == null) return null;
    return Customer.fromMap(_asStringMap(raw));
  }

  // ---------------- المنتجات ----------------
  Future<void> upsertProduct(Product p) async {
    await _ensureReady();
    await _productsBox.put(p.id, p.toMap());
  }

  Future<void> deleteProduct(String id) async {
    await _ensureReady();
    await _productsBox.delete(id);
  }

  Future<List<Product>> getProducts() async {
    await _ensureReady();
    final list =
        _productsBox.values.map((v) => Product.fromMap(_asStringMap(v))).toList();
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  Future<Product?> getProductById(String id) async {
    await _ensureReady();
    final raw = _productsBox.get(id);
    if (raw == null) return null;
    return Product.fromMap(_asStringMap(raw));
  }

  /// تحديث سعر منتج فقط (يُستخدم في تحديث "الأسعار" السريع من المدير)
  Future<bool> updateProductPrice(String id, double price) async {
    await _ensureReady();
    final raw = _productsBox.get(id);
    if (raw == null) return false;
    final p = Product.fromMap(_asStringMap(raw));
    p.price = price;
    p.updatedAt = DateTime.now();
    await _productsBox.put(id, p.toMap());
    return true;
  }

  // ---------------- الفواتير ----------------
  Future<void> upsertInvoice(Invoice inv) async {
    await _ensureReady();
    await _invoicesBox.put(inv.id, inv.toMap());
  }

  Future<void> deleteInvoice(String id) async {
    await _ensureReady();
    await _invoicesBox.delete(id);
  }

  Future<List<Invoice>> getInvoices({String? customerId}) async {
    await _ensureReady();
    var list =
        _invoicesBox.values.map((v) => Invoice.fromMap(_asStringMap(v))).toList();
    list.sort((a, b) => b.date.compareTo(a.date));
    if (customerId != null) {
      list = list.where((i) => i.customerId == customerId).toList();
    }
    return list;
  }

  Future<Invoice?> getInvoiceById(String id) async {
    await _ensureReady();
    final v = _invoicesBox.get(id);
    if (v == null) return null;
    return Invoice.fromMap(_asStringMap(v));
  }

  // ---------------- السندات ----------------
  Future<void> upsertReceipt(Receipt r) async {
    await _ensureReady();
    await _receiptsBox.put(r.id, r.toMap());
  }

  Future<void> deleteReceipt(String id) async {
    await _ensureReady();
    await _receiptsBox.delete(id);
  }

  Future<List<Receipt>> getReceipts({String? customerId}) async {
    await _ensureReady();
    var list =
        _receiptsBox.values.map((v) => Receipt.fromMap(_asStringMap(v))).toList();
    list.sort((a, b) => b.date.compareTo(a.date));
    if (customerId != null) {
      list = list.where((r) => r.customerId == customerId).toList();
    }
    return list;
  }

  Future<Receipt?> getReceiptById(String id) async {
    await _ensureReady();
    final v = _receiptsBox.get(id);
    if (v == null) return null;
    return Receipt.fromMap(_asStringMap(v));
  }

  // ---------------- حساب رصيد العميل ----------------
  Future<double> getCustomerBalance(String customerId, double openingBalance) async {
    final invoices = await getInvoices(customerId: customerId);
    final receipts = await getReceipts(customerId: customerId);
    double balance = openingBalance;
    for (final inv in invoices) {
      balance += inv.effect;
    }
    for (final r in receipts) {
      balance -= r.amount;
    }
    return balance;
  }

  DateTime _parseDt(dynamic v) =>
      DateTime.tryParse(v as String? ?? '') ?? DateTime(2000);

  // ==================== طابور المزامنة (Sync Queue) ====================
  // بدل إرسال ملف كبير يحوي كل البيانات، كل عملية (فاتورة/سند/عميل) تُسجَّل
  // كعنصر هنا. التصدير يجمع فقط العناصر التي ما زالت "pending"/"exported"،
  // وعند تأكيد المدير للاستلام تتحول العناصر إلى "synced". نستخدم مفتاحًا
  // ثابتًا (entityType_entityId) بدل UUID عشوائي فيصبح "التحديث أو الإضافة"
  // بعملية Box.put واحدة دون الحاجة لبحث يدوي عن سجل مطابق.

  /// إضافة/تحديث عنصر في طابور المزامنة لسجل مُعدَّل — يُعاد ضبطه إلى pending
  /// حتى لو كان قد صُدِّر سابقًا، لأن محتواه تغيّر ويحتاج إعادة إرسال. تاريخ
  /// الإنشاء الأصلي (createdAt) يبقى كما هو إن كان العنصر موجودًا مسبقًا.
  Future<void> enqueueSync(String entityType, String entityId) async {
    await _ensureReady();
    final key = '${entityType}_$entityId';
    final now = DateTime.now().toIso8601String();
    final existingRaw = _syncQueueBox.get(key);
    if (existingRaw != null) {
      final existing = _asStringMap(existingRaw);
      existing['status'] = SyncQueueStatus.pending;
      existing['updatedAt'] = now;
      existing['syncedAt'] = null;
      await _syncQueueBox.put(key, existing);
    } else {
      await _syncQueueBox.put(key, {
        'id': key,
        'entityType': entityType,
        'entityId': entityId,
        'status': SyncQueueStatus.pending,
        'createdAt': now,
        'updatedAt': now,
        'syncedAt': null,
        'batchId': null,
      });
    }
  }

  /// كل العناصر التي لم تُؤكَّد مزامنتها بعد (pending أو exported)
  Future<List<Map<String, dynamic>>> getActiveQueueItems() async {
    await _ensureReady();
    final list = _syncQueueBox.values
        .map((v) => _asStringMap(v))
        .where((m) => m['status'] != SyncQueueStatus.synced)
        .toList();
    list.sort((a, b) => _parseDt(a['createdAt']).compareTo(_parseDt(b['createdAt'])));
    return list;
  }

  Future<int> countActiveQueueItems() async {
    final items = await getActiveQueueItems();
    return items.length;
  }

  /// تعليم عناصر كـ "exported" ضمن دفعة تصدير معيّنة
  Future<void> markQueueExported(List<String> queueIds, String batchId) async {
    if (queueIds.isEmpty) return;
    await _ensureReady();
    final now = DateTime.now().toIso8601String();
    for (final id in queueIds) {
      final raw = _syncQueueBox.get(id);
      if (raw == null) continue;
      final m = _asStringMap(raw);
      m['status'] = SyncQueueStatus.exported;
      m['batchId'] = batchId;
      m['updatedAt'] = now;
      await _syncQueueBox.put(id, m);
    }
  }

  /// تعليم كل عناصر دفعة معيّنة كـ "synced" (بعد تأكيد المدير للاستلام)
  Future<void> markQueueSyncedByBatch(String batchId) async {
    await _ensureReady();
    final now = DateTime.now().toIso8601String();
    for (final key in _syncQueueBox.keys.toList()) {
      final raw = _syncQueueBox.get(key);
      if (raw == null) continue;
      final m = _asStringMap(raw);
      if (m['batchId'] == batchId) {
        m['status'] = SyncQueueStatus.synced;
        m['syncedAt'] = now;
        m['updatedAt'] = now;
        await _syncQueueBox.put(key, m);
      }
    }
  }

  Future<List<Map<String, dynamic>>> getQueueItemsByBatch(String batchId) async {
    await _ensureReady();
    return _syncQueueBox.values
        .map((v) => _asStringMap(v))
        .where((m) => m['batchId'] == batchId)
        .toList();
  }

  // ==================== المندوبون (لدى المدير) ====================
  Future<void> upsertRepresentative(Representative r) async {
    await _ensureReady();
    await _representativesBox.put(r.id, r.toMap());
  }

  Future<void> deleteRepresentative(String id) async {
    await _ensureReady();
    await _representativesBox.delete(id);
  }

  Future<List<Representative>> getRepresentatives() async {
    await _ensureReady();
    final list = _representativesBox.values
        .map((v) => Representative.fromMap(_asStringMap(v)))
        .toList();
    list.sort((a, b) => a.repName.toLowerCase().compareTo(b.repName.toLowerCase()));
    return list;
  }

  Future<Representative?> getRepresentativeByCode(String code) async {
    await _ensureReady();
    for (final v in _representativesBox.values) {
      final m = _asStringMap(v);
      if (m['repCode'] == code) return Representative.fromMap(m);
    }
    return null;
  }

  Future<Representative?> getRepresentativeById(String id) async {
    await _ensureReady();
    final raw = _representativesBox.get(id);
    if (raw == null) return null;
    return Representative.fromMap(_asStringMap(raw));
  }

  // ==================== سجل المزامنة (استيراد/تصدير) لدى المدير ====================
  Future<void> insertSyncLog(SyncLogEntry e) async {
    await _ensureReady();
    await _syncLogBox.put(e.id, {
      'id': e.id,
      'type': e.type,
      'fileName': e.fileName,
      'repId': e.repId,
      'repCode': e.repCode,
      'repName': e.repName,
      'timestamp': e.timestamp.toIso8601String(),
      'recordCount': e.recordCount,
      'status': e.status,
      // Hive يخزّن Map متداخلة مباشرة (بلا حاجة لـ jsonEncode)
      'details': e.details,
      'payload': e.payload,
    });
  }

  Future<void> updateSyncLogStatus(String id, String status) async {
    await _ensureReady();
    final raw = _syncLogBox.get(id);
    if (raw == null) return;
    final m = _asStringMap(raw);
    m['status'] = status;
    await _syncLogBox.put(id, m);
  }

  Future<List<SyncLogEntry>> getSyncLogs({String? type}) async {
    await _ensureReady();
    var list =
        _syncLogBox.values.map((v) => _syncLogFromMap(_asStringMap(v))).toList();
    if (type != null) {
      list = list.where((l) => l.type == type).toList();
    }
    list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return list;
  }

  Future<SyncLogEntry?> getSyncLogById(String id) async {
    await _ensureReady();
    final raw = _syncLogBox.get(id);
    if (raw == null) return null;
    return _syncLogFromMap(_asStringMap(raw));
  }

  SyncLogEntry _syncLogFromMap(Map<String, dynamic> m) => SyncLogEntry(
        id: m['id'] as String,
        type: m['type'] as String,
        fileName: m['fileName'] as String? ?? '',
        repId: m['repId'] as String?,
        repCode: m['repCode'] as String?,
        repName: m['repName'] as String?,
        timestamp: m['timestamp'] != null ? _parseDt(m['timestamp']) : DateTime.now(),
        recordCount: (m['recordCount'] as num?)?.toInt() ?? 0,
        status: m['status'] as String,
        details: m['details'] != null
            ? Map<String, dynamic>.from(m['details'] as Map)
            : {},
        payload: m['payload'] as String?,
      );

  // ==================== العروض ====================
  Future<void> upsertOffer(Offer o) async {
    await _ensureReady();
    await _offersBox.put(o.id, o.toMap());
  }

  Future<void> deleteOffer(String id) async {
    await _ensureReady();
    await _offersBox.delete(id);
  }

  Future<List<Offer>> getOffers() async {
    await _ensureReady();
    final list =
        _offersBox.values.map((v) => Offer.fromMap(_asStringMap(v))).toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }
}
