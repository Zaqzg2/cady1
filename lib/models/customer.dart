class Customer {
  int? id;
  String name;
  String phone;
  String? address;
  double balance;
  String? notes;
  String? createdAt;

  Customer({
    this.id,
    required this.name,
    required this.phone,
    this.address,
    this.balance = 0.0,
    this.notes,
    this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'phone': phone,
      'address': address,
      'balance': balance,
      'notes': notes,
      'createdAt': createdAt ?? DateTime.now().toIso8601String(),
    };
  }

  factory Customer.fromMap(Map<String, dynamic> map) {
    return Customer(
      id: map['id'],
      name: map['name'],
      phone: map['phone'],
      address: map['address'],
      balance: (map['balance'] as num?)?.toDouble() ?? 0.0,
      notes: map['notes'],
      createdAt: map['createdAt'],
    );
  }
}
