/// يمثّل مندوب مبيعات كما يراه المدير: بيانات التعريف، الحالة، وآخر مزامنة.
/// هذا الجدول موجود فقط لدى تطبيق (أو وضع) المدير.
class Representative {
  final String id;
  String repCode; // رقم/رمز المندوب — يُستخدم لمطابقة ملفات المزامنة الواردة
  String repName;
  String phone;
  bool isActive;
  DateTime? lastSyncAt;
  String notes;
  DateTime createdAt;

  Representative({
    required this.id,
    required this.repCode,
    required this.repName,
    this.phone = '',
    this.isActive = true,
    this.lastSyncAt,
    this.notes = '',
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
        'id': id,
        'repCode': repCode,
        'repName': repName,
        'phone': phone,
        'isActive': isActive ? 1 : 0,
        'lastSyncAt': lastSyncAt?.toIso8601String(),
        'notes': notes,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Representative.fromMap(Map<String, dynamic> m) => Representative(
        id: m['id'] as String,
        repCode: m['repCode'] as String? ?? '',
        repName: m['repName'] as String? ?? '',
        phone: m['phone'] as String? ?? '',
        isActive: ((m['isActive'] as num?) ?? 1) != 0,
        lastSyncAt: m['lastSyncAt'] != null
            ? DateTime.tryParse(m['lastSyncAt'] as String)
            : null,
        notes: m['notes'] as String? ?? '',
        createdAt: m['createdAt'] != null
            ? (DateTime.tryParse(m['createdAt'] as String) ?? DateTime.now())
            : DateTime.now(),
      );
}
