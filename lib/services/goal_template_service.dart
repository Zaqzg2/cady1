import 'dart:typed_data';

import 'package:excel/excel.dart' as xl;

/// قالب Excel رسمي فارغ لاستيراد الأهداف (القسم L) — رأس أعمدة فقط بالترتيب
/// الحرفي المطلوب بالمواصفة، ليعبّئه المستخدم يدويًا ثم يعيده عبر "استيراد
/// أهداف" (يمر بنفس Pipeline المعتاد: معاينة → تعيين أعمدة → تحقق → مراجعة).
/// عمود "الفرع" هنا اسم نصي حر — وليس معرّفًا داخليًا — لأن من يملأ الملف
/// شخص لا نظام آخر؛ استيراد الأهداف أصلًا يتعرّف على اسم فرع جديد ويعرضه
/// كذلك بدل رفضه (نفس منطق أنواع الاستيراد الأخرى).
class GoalTemplateService {
  static const columns = [
    'اسم الصنف',
    'رقم الصنف',
    'Barcode',
    'الفرع',
    'السنة',
    'الشهر',
    'الهدف 1',
    'الهدف 2',
    'الهدف 3',
    'العمولة 1',
    'العمولة 2',
    'العمولة 3',
  ];

  Uint8List buildEmptyTemplate() {
    final workbook = xl.Excel.createExcel();
    final sheet = workbook['Sheet1'];
    sheet.appendRow(columns.map((c) => xl.TextCellValue(c)).toList());
    final bytes = workbook.save();
    return Uint8List.fromList(bytes ?? []);
  }
}
