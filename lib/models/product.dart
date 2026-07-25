class Product {
  int? id;
  String name;
  double price;
  String? imagePath;
  String? category;
  bool isActive;
  String? createdAt;

  Product({
    this.id,
    required this.name,
    required this.price,
    this.imagePath,
    this.category,
    this.isActive = true,
    this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'price': price,
      'imagePath': imagePath,
      'category': category,
      'isActive': isActive ? 1 : 0,
      'createdAt': createdAt ?? DateTime.now().toIso8601String(),
    };
  }

  factory Product.fromMap(Map<String, dynamic> map) {
    return Product(
      id: map['id'],
      name: map['name'],
      price: (map['price'] as num?)?.toDouble() ?? 0.0,
      imagePath: map['imagePath'],
      category: map['category'],
      isActive: map['isActive'] == 1,
      createdAt: map['createdAt'],
    );
  }
}
