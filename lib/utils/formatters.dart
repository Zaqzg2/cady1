import 'package:intl/intl.dart';

/// تنسيق المبالغ بالريال اليمني، وتنسيق التاريخ المستخدم في كل التطبيق
class Formatters {
  static final currency = NumberFormat.currency(
    locale: 'ar',
    symbol: 'ر.ي',
    decimalDigits: 0,
  );

  static final date = DateFormat('yyyy/MM/dd');
  static final dateTime = DateFormat('yyyy/MM/dd - hh:mm a');
  static final time = DateFormat('hh:mm a');

  static String money(num value) => currency.format(value);
  static String d(DateTime dt) => date.format(dt);
  static String dt(DateTime dt) => dateTime.format(dt);

  /// تنسيق ذكي لعرض "آخر مزامنة": الوقت إن كان اليوم، "أمس" إن كان بالأمس،
  /// وإلا التاريخ الكامل
  static String smartWhen(DateTime value) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(value.year, value.month, value.day);
    final diffDays = today.difference(that).inDays;
    if (diffDays == 0) return time.format(value);
    if (diffDays == 1) return 'أمس';
    if (diffDays > 1 && diffDays < 7) return 'قبل $diffDays أيام';
    return d(value);
  }
}
