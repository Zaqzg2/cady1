import 'dart:convert';
import 'dart:typed_data';

import 'repository.dart';

/// نسخ احتياطي/استعادة محلية كاملة (القسم 33) — JSON نصي بسيط، بلا أي اتصال
/// شبكي أو تخزين سحابي. الحفظ/المشاركة تتم عبر نفس آلية مشاركة الملفات
/// المستخدمة أصلًا للتقارير (share_plus) فلا حاجة لأي تبعية جديدة.
class BackupService {
  final Repository _repo;
  BackupService(this._repo);

  String buildBackupJson() {
    final data = _repo.exportAll();
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  Uint8List buildBackupBytes() => Uint8List.fromList(utf8.encode(buildBackupJson()));

  /// يقرأ الأقسام وعدد السجلات في كل قسم بلا أي كتابة فعلية — لعرضها للمستخدم
  /// قبل طلب تأكيده الصريح (راجع "Confirmation" قبل أي عملية استعادة/حذف).
  Map<String, int> preview(String json) {
    final data = jsonDecode(json) as Map<String, dynamic>;
    final counts = <String, int>{};
    for (final entry in data.entries) {
      if (entry.value is List) counts[entry.key] = (entry.value as List).length;
    }
    return counts;
  }

  /// استعادة فعلية — دمج (Upsert) بالمعرّف عبر Repository.importAll، لا تحذف
  /// أي بيانات حالية غير مذكورة في الملف.
  Future<void> restore(String json) async {
    final data = jsonDecode(json) as Map<String, dynamic>;
    await _repo.importAll(data);
  }
}
