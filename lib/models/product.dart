class Product {
  final String id;
  String name;
  double price;
  String unit; // وحدة القياس: قطعة/كرتون/عبوة ...
  String? imagePath;

  // ---- حقول تتبّع (تُستخدم عند دفع تحديثات الأسعار/الكتالوج من المدير) ----
  DateTime createdAt;
  DateTime updatedAt;

  Product({
    required this.id,
    required this.name,
    required this.price,
    this.unit = 'قطعة',
    this.imagePath,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'price': price,
        'unit': unit,
        'imagePath': imagePath,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory Product.fromMap(Map<String, dynamic> m) => Product(
        id: m['id'] as String,
        name: m['name'] as String,
        price: (m['price'] as num).toDouble(),
        unit: m['unit'] as String? ?? 'قطعة',
        imagePath: m['imagePath'] as String?,
        createdAt: m['createdAt'] != null
            ? (DateTime.tryParse(m['createdAt'] as String) ?? DateTime.now())
            : DateTime.now(),
        updatedAt: m['updatedAt'] != null
            ? (DateTime.tryParse(m['updatedAt'] as String) ?? DateTime.now())
            : DateTime.now(),
      );
}
