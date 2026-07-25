import 'invoice_item.dart';

class Invoice {
  int? id;
  String invoiceNumber;
  int customerId;
  String customerName;
  String type;
  DateTime date;
  List<InvoiceItem> items;
  double subtotal;
  double? discountPercent;
  double? discountAmount;
  double total;
  String? notes;
  String? signature;
  double? previousBalance;
  double? newBalance;
  String? createdAt;

  Invoice({
    this.id,
    required this.invoiceNumber,
    required this.customerId,
    required this.customerName,
    required this.type,
    required this.date,
    required this.items,
    this.subtotal = 0.0,
    this.discountPercent,
    this.discountAmount,
    this.total = 0.0,
    this.notes,
    this.signature,
    this.previousBalance,
    this.newBalance,
    this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'invoiceNumber': invoiceNumber,
      'customerId': customerId,
      'customerName': customerName,
      'type': type,
      'date': date.toIso8601String(),
      'subtotal': subtotal,
      'discountPercent': discountPercent,
      'discountAmount': discountAmount,
      'total': total,
      'notes': notes,
      'signature': signature,
      'previousBalance': previousBalance,
      'newBalance': newBalance,
      'createdAt': createdAt ?? DateTime.now().toIso8601String(),
    };
  }

  factory Invoice.fromMap(Map<String, dynamic> map) {
    return Invoice(
      id: map['id'],
      invoiceNumber: map['invoiceNumber'],
      customerId: map['customerId'],
      customerName: map['customerName'],
      type: map['type'],
      date: DateTime.parse(map['date']),
      items: [],
      subtotal: (map['subtotal'] as num?)?.toDouble() ?? 0.0,
      discountPercent: (map['discountPercent'] as num?)?.toDouble(),
      discountAmount: (map['discountAmount'] as num?)?.toDouble(),
      total: (map['total'] as num?)?.toDouble() ?? 0.0,
      notes: map['notes'],
      signature: map['signature'],
      previousBalance: (map['previousBalance'] as num?)?.toDouble(),
      newBalance: (map['newBalance'] as num?)?.toDouble(),
      createdAt: map['createdAt'],
    );
  }
}
