class ColumnDetector {
  static const Map<String, List<String>> fieldKeywords = {
    'product': [
      'الصنف',
      'اسم الصنف',
      'المنتج',
      'السلعة',
      'اسم المنتج',
      'الوصف',
      'item',
      'product',
      'name',
      'description',
    ],
    'quantity': [
      'الكمية',
      'الرصيد',
      'المخزون',
      'الكمية المتبقية',
      'الكمية الحالية',
      'qty',
      'quantity',
      'stock',
      'balance',
    ],
    'price': [
      'السعر',
      'سعر الشراء',
      'سعر البيع',
      'التكلفة',
      'القيمة',
      'price',
      'cost',
      'unit price',
    ],
    'sale_price': [
      'سعر البيع',
      'سعر المبيع',
      'selling price',
      'sale price',
    ],
    'purchase_price': [
      'سعر الشراء',
      'تكلفة',
      'purchase price',
      'cost price',
    ],
    'date': [
      'التاريخ',
      'تاريخ',
      'date',
    ],
    'expiry': [
      'تاريخ الانتهاء',
      'الانتهاء',
      'الصلاحية',
      'expiry',
      'expiration',
      'exp date',
    ],
    'production': [
      'تاريخ الإنتاج',
      'الإنتاج',
      'production',
      'mfg',
      'manufacturing',
    ],
    'branch': [
      'الفرع',
      'اسم الفرع',
      'المستودع',
      'المخزن',
      'branch',
      'warehouse',
      'location',
    ],
    'category': [
      'التصنيف',
      'الفئة',
      'القسم',
      'category',
      'group',
    ],
    'barcode': [
      'الباركود',
      'الرمز',
      'barcode',
      'sku',
      'code',
    ],
    'unit': [
      'الوحدة',
      'وحدة',
      'unit',
      'uom',
    ],
    'sales': [
      'المبيعات',
      'كمية المبيعات',
      'sales',
      'sold',
    ],
    'returns': [
      'المرتجع',
      'المرتجعات',
      'returns',
      'returned',
    ],
  };

  /// Try to detect the standard field type from a column header
  static String? detectField(String header) {
    final normalized = header.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    for (final entry in fieldKeywords.entries) {
      for (final keyword in entry.value) {
        if (normalized.contains(keyword.toLowerCase()) ||
            keyword.toLowerCase().contains(normalized)) {
          return entry.key;
        }
      }
    }
    return null;
  }

  /// Map a list of headers to standard fields
  static Map<int, String> mapHeaders(List<String> headers) {
    final result = <int, String>{};
    final used = <String>{};

    for (var i = 0; i < headers.length; i++) {
      final detected = detectField(headers[i]);
      if (detected != null && !used.contains(detected)) {
        result[i] = detected;
        used.add(detected);
      }
    }
    return result;
  }

  static String fieldLabel(String field) {
    const labels = {
      'product': 'الصنف',
      'quantity': 'الكمية',
      'price': 'السعر',
      'sale_price': 'سعر البيع',
      'purchase_price': 'سعر الشراء',
      'date': 'التاريخ',
      'expiry': 'تاريخ الانتهاء',
      'production': 'تاريخ الإنتاج',
      'branch': 'الفرع',
      'category': 'التصنيف',
      'barcode': 'الباركود',
      'unit': 'الوحدة',
      'sales': 'المبيعات',
      'returns': 'المرتجع',
      'ignore': 'تجاهل',
    };
    return labels[field] ?? field;
  }

  static List<String> get allStandardFields => [
        'product',
        'quantity',
        'price',
        'sale_price',
        'purchase_price',
        'date',
        'expiry',
        'production',
        'branch',
        'category',
        'barcode',
        'unit',
        'sales',
        'returns',
        'ignore',
      ];
}