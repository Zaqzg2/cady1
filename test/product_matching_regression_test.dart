import 'package:flutter_test/flutter_test.dart';
import 'package:inventory_analyzer/models/catalog_models.dart';
import 'package:inventory_analyzer/models/import_models.dart';
import 'package:inventory_analyzer/providers/import_session_provider.dart';

ExtractedRow _rowNamed(String name) => ExtractedRow(
      cells: [ExtractedCell(fieldType: FieldType.productName, value: name, confidence: 0.95)],
    );

void main() {
  group('Product matching — regression: silent merge via fuzzy name similarity', () {
    // القصة الحقيقية المُبلَّغ عنها: استيراد 93 صفًا ينتج 43 منتجًا فقط، لأن
    // matchAgainstCatalog كانت تُثبِّت matchedProductId تلقائيًا لأي تشابه
    // اسم ≥ 55% (عتبة "يستحق الاقتراح" وليست "مؤكَّد بلا مراجعة") — فتُدمَج
    // أصناف مختلفة فعليًا (مثل حجمين مختلفين لنفس المنتج) في صنف واحد صامتًا.

    test('similar-but-different product names do NOT get auto-matched without user confirmation', () {
      final session = ImportSessionProvider();
      final existing = [Product(name: 'حليب 200 مل')];
      session.rows = [_rowNamed('حليب 125 مل')]; // نفس المنتج تقريبًا نصيًا، لكن حجم مختلف = صنف مختلف فعليًا

      session.matchAgainstCatalog(existing);

      final row = session.rows.first;
      // ✅ الإصلاح: matchedProductId يبقى null بلا تدخّل المستخدم — حتى لو
      // كان التشابه النصي عاليًا. الدمج التلقائي محصور بمطابقة Barcode
      // الحرفية فقط (هوية عمل قاطعة، وليست تخمين تشابه نصي).
      expect(row.matchedProductId, isNull);
      // لكن الاقتراح نفسه يجب أن يبقى متاحًا (لعرضه في شريط الاقتراح
      // Approve/Change بشاشة المراجعة) — لسنا نُخفي الإشارة، فقط لا نُثبِّتها تلقائيًا.
      expect(row.matchSuggestionProductId, isNotNull);
      expect(row.matchScore, greaterThan(0));
    });

    test('an exact barcode match DOES auto-confirm — a real, unambiguous business identity', () {
      final session = ImportSessionProvider();
      final existing = [Product(name: 'صنف قديم', barcode: '6291012345')];
      session.rows = [
        ExtractedRow(cells: [
          ExtractedCell(fieldType: FieldType.productName, value: 'اسم مختلف تمامًا', confidence: 0.9),
          ExtractedCell(fieldType: FieldType.barcode, value: '6291012345', confidence: 0.9),
        ]),
      ];

      session.matchAgainstCatalog(existing);

      // Barcode حرفي مطابق تمامًا → يبقى الاستثناء الوحيد للتثبيت التلقائي،
      // لأنه هوية عمل قاطعة (ليس تخمين تشابه نصي كالاسم).
      expect(session.rows.first.matchedProductId, existing.first.id);
    });

    test('explicit user approval (acceptSuggestedProduct) is what actually confirms a name-based suggestion', () {
      final session = ImportSessionProvider();
      final existing = [Product(name: 'حليب 200 مل')];
      session.rows = [_rowNamed('حليب 200مل')]; // فروق طفيفة كتابيًا فقط

      session.matchAgainstCatalog(existing);
      final rowId = session.rows.first.id;
      expect(session.rows.first.matchedProductId, isNull);

      // فعل صريح من المستخدم (زر [✓ اعتماد] في شريط الاقتراح) — هذا هو
      // المسار الوحيد الصحيح لتثبيت مطابقة نصية الآن.
      session.acceptSuggestedProduct(rowId);
      expect(session.rows.first.matchedProductId, existing.first.id);
    });

    test('multiple genuinely different products all stay unmatched, none silently collapse', () {
      final session = ImportSessionProvider();
      final existing = [Product(name: 'سكر 1 كيلو')];
      session.rows = [
        _rowNamed('سكر 1 كيلو'), // شبه مطابق تمامًا نصيًا لصنف موجود
        _rowNamed('سكر 5 كيلو'), // كمية مختلفة = صنف مختلف
        _rowNamed('أرز بسمتي'), // لا علاقة له إطلاقًا
      ];

      session.matchAgainstCatalog(existing);

      // الثلاثة صفوف تبقى بلا matchedProductId مُثبَّت تلقائيًا — القرار
      // النهائي للمستخدم دائمًا، بصرف النظر عن درجة التشابه النصي.
      for (final row in session.rows) {
        expect(row.matchedProductId, isNull, reason: 'row: ${row.cellOf(FieldType.productName)?.value}');
      }
    });
  });
}
