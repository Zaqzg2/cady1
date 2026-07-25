class Payment {
  int? id;
  String receiptNumber;
  int customerId;
  String customerName;
  double amount;
  String paymentType;
  DateTime date;
  String? notes;
  String? signature;
  double? previousBalance;
  double? newBalance;
  String? createdAt;

  Payment({
    this.id,
    required this.receiptNumber,
    required this.customerId,
    required this.customerName,
    required this.amount,
    required this.paymentType,
    required this.date,
    this.notes,
    this.signature,
    this.previousBalance,
    this.newBalance,
    this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'receiptNumber': receiptNumber,
      'customerId': customerId,
      'customerName': customerName,
      'amount': amount,
      'paymentType': paymentType,
      'date': date.toIso8601String(),
      'notes': notes,
      'signature': signature,
      'previousBalance': previousBalance,
      'newBalance': newBalance,
      'createdAt': createdAt ?? DateTime.now().toIso8601String(),
    };
  }

  factory Payment.fromMap(Map<String, dynamic> map) {
    return Payment(
      id: map['id'],
      receiptNumber: map['receiptNumber'],
      customerId: map['customerId'],
      customerName: map['customerName'],
      amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
      paymentType: map['paymentType'],
      date: DateTime.parse(map['date']),
      notes: map['notes'],
      signature: map['signature'],
      previousBalance: (map['previousBalance'] as num?)?.toDouble(),
      newBalance: (map['newBalance'] as num?)?.toDouble(),
      createdAt: map['createdAt'],
    );
  }
}
