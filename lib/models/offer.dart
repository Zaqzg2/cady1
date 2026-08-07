/// عرض ترويجي بسيط يُنشئه المدير ويُصدَّر ضمن ملف التحديث إلى المندوبين.
class Offer {
  final String id;
  String title;
  String description;
  double discountPercent; // نسبة خصم اختيارية (0 = بلا خصم محدد، وصف نصي فقط)
  DateTime? startDate;
  DateTime? endDate;
  bool isActive;
  DateTime createdAt;
  DateTime updatedAt;

  Offer({
    required this.id,
    required this.title,
    this.description = '',
    this.discountPercent = 0,
    this.startDate,
    this.endDate,
    this.isActive = true,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  /// هل العرض ساري حاليًا (نشط ومن ضمن الفترة الزمنية إن وُجدت)
  bool get isCurrentlyValid {
    if (!isActive) return false;
    final now = DateTime.now();
    if (startDate != null && now.isBefore(startDate!)) return false;
    if (endDate != null && now.isAfter(endDate!)) return false;
    return true;
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'description': description,
        'discountPercent': discountPercent,
        'startDate': startDate?.toIso8601String(),
        'endDate': endDate?.toIso8601String(),
        'isActive': isActive ? 1 : 0,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory Offer.fromMap(Map<String, dynamic> m) => Offer(
        id: m['id'] as String,
        title: m['title'] as String? ?? '',
        description: m['description'] as String? ?? '',
        discountPercent: (m['discountPercent'] as num?)?.toDouble() ?? 0,
        startDate: m['startDate'] != null
            ? DateTime.tryParse(m['startDate'] as String)
            : null,
        endDate: m['endDate'] != null
            ? DateTime.tryParse(m['endDate'] as String)
            : null,
        isActive: ((m['isActive'] as num?) ?? 1) != 0,
        createdAt: m['createdAt'] != null
            ? (DateTime.tryParse(m['createdAt'] as String) ?? DateTime.now())
            : DateTime.now(),
        updatedAt: m['updatedAt'] != null
            ? (DateTime.tryParse(m['updatedAt'] as String) ?? DateTime.now())
            : DateTime.now(),
      );
}
