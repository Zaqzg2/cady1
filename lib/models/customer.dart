class Customer {
  final String id;
  String name;
  String phone;
  String address;
  double openingBalance; // رصيد افتتاحي (مديونية سابقة)
  bool isPinned; // تثبيت العميل أعلى القائمة
  bool isActive; // حالة العميل: نشط/متوقف
  double creditLimit; // الحد الائتماني المسموح به (0 = بلا حد)
  String notes; // ملاحظات داخلية عن العميل

  // ---- حقول المزامنة ----
  String syncStatus; // pending / synced — حالة مزامنة هذا العميل مع المدير
  String? sourceRepCode; // (لدى المدير فقط) رمز المندوب الذي أضاف هذا العميل
  DateTime createdAt;
  DateTime updatedAt;

  Customer({
    required this.id,
    required this.name,
    this.phone = '',
    this.address = '',
    this.openingBalance = 0,
    this.isPinned = false,
    this.isActive = true,
    this.creditLimit = 0,
    this.notes = '',
    this.syncStatus = 'pending',
    this.sourceRepCode,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'phone': phone,
        'address': address,
        'openingBalance': openingBalance,
        'isPinned': isPinned ? 1 : 0,
        'isActive': isActive ? 1 : 0,
        'creditLimit': creditLimit,
        'notes': notes,
        'syncStatus': syncStatus,
        'sourceRepCode': sourceRepCode,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory Customer.fromMap(Map<String, dynamic> m) => Customer(
        id: m['id'] as String,
        name: m['name'] as String,
        phone: m['phone'] as String? ?? '',
        address: m['address'] as String? ?? '',
        openingBalance: (m['openingBalance'] as num?)?.toDouble() ?? 0,
        isPinned: ((m['isPinned'] as num?) ?? 0) != 0,
        isActive: ((m['isActive'] as num?) ?? 1) != 0,
        creditLimit: (m['creditLimit'] as num?)?.toDouble() ?? 0,
        notes: m['notes'] as String? ?? '',
        syncStatus: m['syncStatus'] as String? ?? 'pending',
        sourceRepCode: m['sourceRepCode'] as String?,
        createdAt: m['createdAt'] != null
            ? (DateTime.tryParse(m['createdAt'] as String) ?? DateTime.now())
            : DateTime.now(),
        updatedAt: m['updatedAt'] != null
            ? (DateTime.tryParse(m['updatedAt'] as String) ?? DateTime.now())
            : DateTime.now(),
      );
}
