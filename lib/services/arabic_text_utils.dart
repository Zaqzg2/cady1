/// أدوات تطبيع النصوص العربية — الأساس الذي تُبنى عليه المطابقة الضبابية
/// واكتشاف الأعمدة تلقائيًا. كل التطبيع هنا نصّي بحت (بدون أي اعتماديات).
class ArabicTextUtils {
  ArabicTextUtils._();

  // علامات التشكيل (فتحة، ضمة، كسرة، سكون، تنوين، شدة...)
  static final RegExp _diacritics = RegExp(
    r'[\u064B-\u0652\u0670\u0653-\u065F\u06D6-\u06ED]',
  );

  // التطويل (ـ)
  static final RegExp _tatweel = RegExp(r'\u0640');

  static final RegExp _multiSpace = RegExp(r'\s+');

  // أرقام هندية/عربية شرقية -> غربية
  static const _easternDigits = '٠١٢٣٤٥٦٧٨٩';
  static const _westernDigits = '0123456789';

  /// يحوّل الأرقام العربية الشرقية (٠-٩) إلى غربية (0-9)
  static String normalizeDigits(String input) {
    final buffer = StringBuffer();
    for (final ch in input.runes) {
      final c = String.fromCharCode(ch);
      final idx = _easternDigits.indexOf(c);
      buffer.write(idx == -1 ? c : _westernDigits[idx]);
    }
    return buffer.toString();
  }

  /// التطبيع الكامل المستخدم في المقارنة والمطابقة (وليس للعرض للمستخدم)
  static String normalize(String input) {
    var text = input.trim();
    text = normalizeDigits(text);
    text = text.replaceAll(_diacritics, '');
    text = text.replaceAll(_tatweel, '');

    // توحيد اختلافات الألف: أ إ آ ٱ -> ا
    text = text.replaceAll(RegExp(r'[أإآٱ]'), 'ا');
    // الياء المقصورة -> ياء
    text = text.replaceAll('ى', 'ي');
    // التاء المربوطة -> هاء (لأن الفرق بينهما غالبًا خطأ إملائي شائع في الكشوف)
    text = text.replaceAll('ة', 'ه');
    // الهمزة على الواو/الياء المفردة -> حرفها الأساسي لتسهيل المطابقة
    text = text.replaceAll('ؤ', 'و').replaceAll('ئ', 'ي');

    text = text.toLowerCase();
    text = text.replaceAll(_multiSpace, ' ').trim();
    return text;
  }

  /// يحاول تفسير نص كرقم بعد تطبيع الأرقام العربية وإزالة فواصل الآلاف
  static double? tryParseNumber(String input) {
    var text = normalizeDigits(input.trim());
    text = text.replaceAll(RegExp(r'[,٬\s]'), '');
    text = text.replaceAll('٫', '.'); // الفاصلة العشرية العربية
    return double.tryParse(text);
  }

  /// يحاول تفسير نص كتاريخ بصيغ شائعة في الكشوف العربية (يوم/شهر/سنة أساسًا)
  static DateTime? tryParseArabicDate(String input) {
    final text = normalizeDigits(input.trim());
    final cleaned = text.replaceAll(RegExp(r'[\\\.]'), '/').replaceAll('-', '/');
    final parts = cleaned.split('/').where((p) => p.isNotEmpty).toList();
    if (parts.length != 3) return DateTime.tryParse(text);

    int? p0 = int.tryParse(parts[0]);
    int? p1 = int.tryParse(parts[1]);
    int? p2 = int.tryParse(parts[2]);
    if (p0 == null || p1 == null || p2 == null) return null;

    // افتراض الصيغة الشائعة يوم/شهر/سنة إن كان الجزء الأول <= 31 والثاني <= 12
    int day, month, year;
    if (p0 > 31 || (p0 > 12 && p1 <= 12)) {
      // الصيغة الأولى قد تكون سنة/شهر/يوم
      year = p0;
      month = p1;
      day = p2;
    } else {
      day = p0;
      month = p1;
      year = p2 < 100 ? 2000 + p2 : p2;
    }
    try {
      return DateTime(year, month, day);
    } catch (_) {
      return null;
    }
  }
}
