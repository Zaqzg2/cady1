/// سجل موحّد لعمليات الاستيراد (من مندوب) والتصدير (تحديث إلى مندوب/مندوبين)
/// لدى المدير. type يحدد النوع: 'import' أو 'export'.
class SyncLogEntry {
  final String id;
  String type; // import / export
  String fileName;
  String? repId;
  String? repCode;
  String? repName;
  DateTime timestamp;
  int recordCount;
  String status; // import: pending/approved/cancelled — export: sent
  Map<String, dynamic> details; // إحصائيات إضافية حسب النوع
  String? payload; // نص JSON الخام (للاستيراد) لدعم "إعادة الاستيراد" لاحقًا

  SyncLogEntry({
    required this.id,
    required this.type,
    required this.fileName,
    this.repId,
    this.repCode,
    this.repName,
    DateTime? timestamp,
    this.recordCount = 0,
    required this.status,
    Map<String, dynamic>? details,
    this.payload,
  })  : timestamp = timestamp ?? DateTime.now(),
        details = details ?? {};
}
