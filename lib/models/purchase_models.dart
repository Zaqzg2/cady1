import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// حالات طلب الشراء (القسم 14)
enum PurchaseRequestStatus { draft, requested, partial, completed, cancelled }

extension PurchaseRequestStatusX on PurchaseRequestStatus {
  String get labelAr => switch (this) {
        PurchaseRequestStatus.draft => 'مسودة',
        PurchaseRequestStatus.requested => 'مطلوب',
        PurchaseRequestStatus.partial => 'جزئي',
        PurchaseRequestStatus.completed => 'مكتمل',
        PurchaseRequestStatus.cancelled => 'ملغي',
      };
}

/// سطر صنف واحد داخل طلب شراء — يحسب تلقائيًا المتبقي ونسبة التوريد (القسم 14)
class PurchaseRequestItem {
  final String id;
  String productId;
  double requestedQty;
  double receivedQty;

  PurchaseRequestItem({
    String? id,
    required this.productId,
    required this.requestedQty,
    this.receivedQty = 0,
  }) : id = id ?? _uuid.v4();

  double get remainingQty => (requestedQty - receivedQty) < 0 ? 0 : (requestedQty - receivedQty);

  double get fulfillmentPct =>
      requestedQty <= 0 ? 0 : ((receivedQty / requestedQty) * 100).clamp(0, 100);

  Map<String, dynamic> toMap() => {
        'id': id,
        'productId': productId,
        'requestedQty': requestedQty,
        'receivedQty': receivedQty,
      };

  factory PurchaseRequestItem.fromMap(Map<dynamic, dynamic> map) => PurchaseRequestItem(
        id: map['id'] as String,
        productId: map['productId'] as String,
        requestedQty: (map['requestedQty'] as num?)?.toDouble() ?? 0,
        receivedQty: (map['receivedQty'] as num?)?.toDouble() ?? 0,
      );
}

enum PurchaseAttachmentType { image, pdf, excel, other }

extension PurchaseAttachmentTypeX on PurchaseAttachmentType {
  String get labelAr => switch (this) {
        PurchaseAttachmentType.image => 'صورة',
        PurchaseAttachmentType.pdf => 'PDF',
        PurchaseAttachmentType.excel => 'Excel',
        PurchaseAttachmentType.other => 'ملف',
      };
}

PurchaseAttachmentType attachmentTypeFromFileName(String fileName) {
  final lower = fileName.toLowerCase();
  if (lower.endsWith('.pdf')) return PurchaseAttachmentType.pdf;
  if (lower.endsWith('.xlsx') || lower.endsWith('.xls') || lower.endsWith('.csv')) {
    return PurchaseAttachmentType.excel;
  }
  if (lower.endsWith('.png') ||
      lower.endsWith('.jpg') ||
      lower.endsWith('.jpeg') ||
      lower.endsWith('.webp')) {
    return PurchaseAttachmentType.image;
  }
  return PurchaseAttachmentType.other;
}

/// مرفق داخل طلب شراء — يُحفَظ محليًا فقط (القسم 15)، بلا أي Cloud Storage.
///
/// ⚠️ المحتوى يُخزَّن Base64 داخل نفس سطر Hive (وليس كملف عبر dart:io) عمدًا:
/// `dart:io`/`File`/`path_provider` (نظام الملفات) غير مدعومين على Flutter
/// Web، والتطبيق يستهدف أندرويد والويب معًا (نفس سبب اختيار Hive أصلًا لكل
/// تخزين التطبيق — راجع README). هذا يبقي المرفق ضمن قاعدة البيانات المحلية
/// نفسها على كلتا المنصتين بلا أي كود خاص بمنصة واحدة.
class PurchaseAttachment {
  final String id;
  String fileName;
  PurchaseAttachmentType type;

  /// المحتوى الفعلي مُرمَّزًا Base64 (راجع attachment_service.dart للترميز/فك الترميز)
  String dataBase64;
  int sizeBytes;
  DateTime addedAt;

  PurchaseAttachment({
    String? id,
    required this.fileName,
    required this.type,
    required this.dataBase64,
    this.sizeBytes = 0,
    DateTime? addedAt,
  })  : id = id ?? _uuid.v4(),
        addedAt = addedAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
        'id': id,
        'fileName': fileName,
        'type': type.name,
        'dataBase64': dataBase64,
        'sizeBytes': sizeBytes,
        'addedAt': addedAt.toIso8601String(),
      };

  factory PurchaseAttachment.fromMap(Map<dynamic, dynamic> map) => PurchaseAttachment(
        id: map['id'] as String,
        fileName: map['fileName'] as String? ?? '',
        type: PurchaseAttachmentType.values.firstWhere(
          (t) => t.name == map['type'],
          orElse: () => PurchaseAttachmentType.other,
        ),
        dataBase64: map['dataBase64'] as String? ?? '',
        sizeBytes: map['sizeBytes'] as int? ?? 0,
        addedAt: DateTime.tryParse(map['addedAt'] as String? ?? '') ?? DateTime.now(),
      );
}

/// طلب شراء كامل — القسم 13.
class PurchaseRequest {
  final String id;
  String requestNumber;
  DateTime date;
  String branchId;
  String? supplierName;
  PurchaseRequestStatus status;
  String? notes;
  List<PurchaseRequestItem> items;
  List<PurchaseAttachment> attachments;
  DateTime createdAt;
  DateTime updatedAt;

  PurchaseRequest({
    String? id,
    String? requestNumber,
    DateTime? date,
    required this.branchId,
    this.supplierName,
    this.status = PurchaseRequestStatus.draft,
    this.notes,
    List<PurchaseRequestItem>? items,
    List<PurchaseAttachment>? attachments,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : id = id ?? _uuid.v4(),
        requestNumber = requestNumber ?? '',
        date = date ?? DateTime.now(),
        items = items ?? [],
        attachments = attachments ?? [],
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  double get totalRequested => items.fold<double>(0, (s, i) => s + i.requestedQty);
  double get totalReceived => items.fold<double>(0, (s, i) => s + i.receivedQty);
  double get totalRemaining =>
      (totalRequested - totalReceived) < 0 ? 0 : (totalRequested - totalReceived);
  double get fulfillmentPct =>
      totalRequested <= 0 ? 0 : ((totalReceived / totalRequested) * 100).clamp(0, 100);

  Map<String, dynamic> toMap() => {
        'id': id,
        'requestNumber': requestNumber,
        'date': date.toIso8601String(),
        'branchId': branchId,
        'supplierName': supplierName,
        'status': status.name,
        'notes': notes,
        'items': items.map((e) => e.toMap()).toList(),
        'attachments': attachments.map((e) => e.toMap()).toList(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory PurchaseRequest.fromMap(Map<dynamic, dynamic> map) => PurchaseRequest(
        id: map['id'] as String,
        requestNumber: map['requestNumber'] as String? ?? '',
        date: DateTime.tryParse(map['date'] as String? ?? '') ?? DateTime.now(),
        branchId: map['branchId'] as String,
        supplierName: map['supplierName'] as String?,
        status: PurchaseRequestStatus.values.firstWhere(
          (s) => s.name == map['status'],
          orElse: () => PurchaseRequestStatus.draft,
        ),
        notes: map['notes'] as String?,
        items: ((map['items'] as List?) ?? const [])
            .map((e) => PurchaseRequestItem.fromMap(e as Map))
            .toList(),
        attachments: ((map['attachments'] as List?) ?? const [])
            .map((e) => PurchaseAttachment.fromMap(e as Map))
            .toList(),
        createdAt: DateTime.tryParse(map['createdAt'] as String? ?? '') ?? DateTime.now(),
        updatedAt: DateTime.tryParse(map['updatedAt'] as String? ?? '') ?? DateTime.now(),
      );
}
