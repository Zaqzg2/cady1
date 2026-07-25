class InvoiceItem {
  int? id;
  int? invoiceId;
  int productId;
  String productName;
  double price;
  int quantity;
  double total;

  InvoiceItem({
    this.id,
    this.invoiceId,
    required this.productId,
    required this.productName,
    required this.price,
    required this.quantity,
    this.total = 0.0,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'invoiceId': invoiceId,
      'productId': productId,
      'productName': productName,
      'price': price,
      'quantity': quantity,
      'total': total,
    };
  }

  factory InvoiceItem.fromMap(Map<String, dynamic> map) {
    return InvoiceItem(
      id: map['id'],
      invoiceId: map['invoiceId'],
      productId: map['productId'],
      productName: map['productName'],
      price: (map['price'] as num?)?.toDouble() ?? 0.0,
      quantity: map['quantity'],
      total: (map['total'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
