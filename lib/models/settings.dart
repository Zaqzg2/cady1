class AppSettings {
  String companyName;
  String companyPhone;
  String? companyAddress;
  String? logoPath;
  String representativeName;
  String currency;
  String? printerAddress;
  double tableFontSize;
  int tableColumns;
  bool darkMode;

  AppSettings({
    this.companyName = 'كادي للمنظفات',
    this.companyPhone = '',
    this.companyAddress,
    this.logoPath,
    this.representativeName = '',
    this.currency = 'ريال يمني',
    this.printerAddress,
    this.tableFontSize = 12.0,
    this.tableColumns = 5,
    this.darkMode = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'companyName': companyName,
      'companyPhone': companyPhone,
      'companyAddress': companyAddress,
      'logoPath': logoPath,
      'representativeName': representativeName,
      'currency': currency,
      'printerAddress': printerAddress,
      'tableFontSize': tableFontSize,
      'tableColumns': tableColumns,
      'darkMode': darkMode,
    };
  }

  factory AppSettings.fromMap(Map<String, dynamic> map) {
    return AppSettings(
      companyName: map['companyName'] ?? 'كادي للمنظفات',
      companyPhone: map['companyPhone'] ?? '',
      companyAddress: map['companyAddress'],
      logoPath: map['logoPath'],
      representativeName: map['representativeName'] ?? '',
      currency: map['currency'] ?? 'ريال يمني',
      printerAddress: map['printerAddress'],
      tableFontSize: (map['tableFontSize'] as num?)?.toDouble() ?? 12.0,
      tableColumns: map['tableColumns'] ?? 5,
      darkMode: map['darkMode'] ?? false,
    );
  }
}
