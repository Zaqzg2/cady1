import '../models/import_models.dart';
import 'arabic_text_utils.dart';
import 'fuzzy_matching_service.dart';

/// يكتشف نوع كل عمود من عنوانه، بمطابقة مباشرة/جزئية ثم ضبابية كخط دفاع أخير
class ColumnDetectionService {
  static final Map<FieldType, List<String>> _keywords = {
    FieldType.productName: [
      'الصنف',
      'اسم الصنف',
      'المنتج',
      'اسم المنتج',
      'السلعة',
      'الوصف',
      'اسم السلعة',
    ],
    FieldType.itemNumber: [
      'رقم الصنف',
      'كود الصنف',
      'رقم المنتج',
      'الرقم',
    ],
    FieldType.barcode: [
      'باركود',
      'الباركود',
      'barcode',
      'الرمز الشريطي',
    ],
    FieldType.unit: [
      'الوحدة',
      'وحدة',
      'وحدة القياس',
    ],
    FieldType.quantity: [
      'الكمية',
      'الرصيد',
      'المخزون',
      'الكمية المتبقية',
      'رصيد',
      'الكمية الحالية',
    ],
    FieldType.sales: [
      'المبيعات',
      'مبيعات',
      'كمية البيع',
      'الصرف',
      'كمية الصرف',
    ],
    FieldType.returns: [
      'المرتجع',
      'المرتجعات',
      'مرتجع',
    ],
    FieldType.productionDate: [
      'تاريخ الإنتاج',
      'تاريخ التصنيع',
      'الإنتاج',
    ],
    FieldType.expiryDate: [
      'تاريخ الانتهاء',
      'الصلاحية',
      'تاريخ الصلاحية',
      'انتهاء الصلاحية',
      'التاريخ',
    ],
    FieldType.branch: [
      'الفرع',
      'الفروع',
      'اسم الفرع',
      'الفرع الحالي',
      'branch',
      'branch name',
      'المخزن',
      'المستودع',
      'warehouse',
      'الموقع',
      'location',
    ],
    FieldType.category: [
      'التصنيف',
      'الفئة',
      'القسم',
      'المجموعة',
    ],
    // القسم I من مواصفة الأهداف — كشوف الأهداف الشهرية تحديدًا.
    FieldType.year: ['السنة', 'عام', 'year'],
    FieldType.month: ['الشهر', 'شهر', 'month'],
    FieldType.goal1: ['هدف 1', 'هدف1', 'الهدف الأول', 'goal 1', 'goal1', 'الفئة الأولى'],
    FieldType.goal2: ['هدف 2', 'هدف2', 'الهدف الثاني', 'goal 2', 'goal2', 'الفئة الثانية'],
    FieldType.goal3: ['هدف 3', 'هدف3', 'الهدف الثالث', 'goal 3', 'goal3', 'الفئة الثالثة'],
  };

  final _fuzzy = FuzzyMatchingService();

  /// يحاول تحديد [FieldType] لعنوان عمود واحد، أو null إن تعذّر (يحتاج Mapping يدوي)
  FieldType? detectColumn(String header) {
    final normalizedHeader = ArabicTextUtils.normalize(header);
    if (normalizedHeader.isEmpty) return null;

    // 1) مطابقة مباشرة/احتواء نصّي (أسرع وأدق من الضبابية)
    for (final entry in _keywords.entries) {
      for (final keyword in entry.value) {
        final normalizedKeyword = ArabicTextUtils.normalize(keyword);
        if (normalizedHeader == normalizedKeyword ||
            normalizedHeader.contains(normalizedKeyword) ||
            normalizedKeyword.contains(normalizedHeader)) {
          return entry.key;
        }
      }
    }

    // 2) مطابقة ضبابية كخط دفاع أخير (يلتقط أخطاء إملائية بسيطة في العنوان
    //    نفسه، مثل "الكميه" بدل "الكمية")
    FieldType? bestField;
    var bestScore = 0.72; // عتبة أعلى من مطابقة الأصناف لتفادي تخمينات خاطئة
    for (final entry in _keywords.entries) {
      for (final keyword in entry.value) {
        final score = _fuzzy.similarity(
          normalizedHeader,
          ArabicTextUtils.normalize(keyword),
        );
        if (score > bestScore) {
          bestScore = score;
          bestField = entry.key;
        }
      }
    }
    return bestField;
  }

  /// يبني قائمة [ColumnMapping] لكل الأعمدة، ويترك mappedField=unknown لما تعذّر اكتشافه
  List<ColumnMapping> detectColumns(List<String> headers) {
    return List.generate(headers.length, (i) {
      final detected = detectColumn(headers[i]);
      return ColumnMapping(
        columnIndex: i,
        header: headers[i],
        mappedField: detected ?? FieldType.unknown,
      );
    });
  }

  /// هل تحتاج نتيجة الاكتشاف لمراجعة يدوية (Mapping) من المستخدم؟
  bool needsManualMapping(List<ColumnMapping> mappings) {
    final hasProduct =
        mappings.any((m) => m.mappedField == FieldType.productName);
    final hasQuantity =
        mappings.any((m) => m.mappedField == FieldType.quantity);
    final hasUnknown = mappings.any((m) => m.mappedField == FieldType.unknown);
    return !hasProduct || !hasQuantity || hasUnknown;
  }
}
