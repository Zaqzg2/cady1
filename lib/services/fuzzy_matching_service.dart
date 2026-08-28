import '../models/catalog_models.dart';
import 'arabic_text_utils.dart';

class ProductMatch {
  final Product product;
  final double score; // 0.0 - 1.0

  ProductMatch(this.product, this.score);
}

/// محرك مطابقة ضبابية بسيط (بدون اعتماديات خارجية) مبني على:
/// 1) مسافة Levenshtein على النص المُطبَّع بالكامل
/// 2) تشابه مجموعة الكلمات (Jaccard) لالتقاط حالات ترتيب الكلمات المختلف
///    أو نقصان كلمة (مثال: "حليب سعودي" مقابل "حليب السعودية كامل الدسم")
/// النتيجة النهائية هي أعلى القيمتين (وليس المتوسط) لأن أيًا من الطريقتين
/// قد يلتقط تشابهًا حقيقيًا فاتته الطريقة الأخرى.
class FuzzyMatchingService {
  /// أوجد أفضل [topN] تطابقات لاسم [query] من بين [candidates]
  List<ProductMatch> findBestMatches(
    String query,
    List<Product> candidates, {
    int topN = 3,
    double minScore = 0.35,
  }) {
    final normalizedQuery = ArabicTextUtils.normalize(query);
    if (normalizedQuery.isEmpty) return [];

    final scored = candidates.map((p) {
      final score = _similarity(normalizedQuery, p.normalizedName);
      return ProductMatch(p, score);
    }).where((m) => m.score >= minScore).toList();

    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.take(topN).toList();
  }

  /// هل النتيجة الأفضل قوية بما يكفي لاقتراحها تلقائيًا للمستخدم؟
  static bool isStrongEnoughToSuggest(double score) => score >= 0.55;

  /// تشابه بين نصّين مُطبَّعين مسبقًا (0.0 - 1.0). عامة لإعادة استخدامها في
  /// أي مكان يحتاج مقارنة نصوص عربية تقريبية (مثل اكتشاف عناوين الأعمدة).
  double similarity(String a, String b) => _similarity(a, b);

  double _similarity(String a, String b) {
    if (a.isEmpty || b.isEmpty) return 0;
    if (a == b) return 1;

    final levenshteinScore = _levenshteinSimilarity(a, b);
    final tokenScore = _tokenSimilarity(a, b);
    return levenshteinScore > tokenScore ? levenshteinScore : tokenScore;
  }

  double _levenshteinSimilarity(String a, String b) {
    final distance = _levenshtein(a, b);
    final maxLen = a.length > b.length ? a.length : b.length;
    if (maxLen == 0) return 1;
    return 1 - (distance / maxLen);
  }

  /// تشابه مبني على تقاطع/اتحاد مجموعتيّ الكلمات (Jaccard)، مع مكافأة جزئية
  /// إذا كانت إحدى الكلمات "بادئة" لكلمة أخرى (يلتقط "سعودي" داخل "السعودية")
  double _tokenSimilarity(String a, String b) {
    final tokensA = a.split(' ').where((t) => t.isNotEmpty).toSet();
    final tokensB = b.split(' ').where((t) => t.isNotEmpty).toSet();
    if (tokensA.isEmpty || tokensB.isEmpty) return 0;

    var matched = 0.0;
    for (final ta in tokensA) {
      if (tokensB.contains(ta)) {
        matched += 1;
        continue;
      }
      // مطابقة جزئية: أحدهما بادئة الآخر بطول معقول (>=3 أحرف)
      final partial = tokensB.any((tb) =>
          tb.length >= 3 &&
          ta.length >= 3 &&
          (ta.startsWith(tb) || tb.startsWith(ta)));
      if (partial) matched += 0.6;
    }

    final union = tokensA.length + tokensB.length - matched;
    if (union <= 0) return 0;
    return (matched / union).clamp(0, 1);
  }

  /// خوارزمية Levenshtein القياسية (برمجة ديناميكية بمصفوفة صف واحد)
  int _levenshtein(String s, String t) {
    if (s == t) return 0;
    if (s.isEmpty) return t.length;
    if (t.isEmpty) return s.length;

    var previousRow = List<int>.generate(t.length + 1, (i) => i);
    var currentRow = List<int>.filled(t.length + 1, 0);

    for (var i = 0; i < s.length; i++) {
      currentRow[0] = i + 1;
      for (var j = 0; j < t.length; j++) {
        final deletionCost = previousRow[j + 1] + 1;
        final insertionCost = currentRow[j] + 1;
        final substitutionCost =
            previousRow[j] + (s[i] == t[j] ? 0 : 1);
        currentRow[j + 1] =
            [deletionCost, insertionCost, substitutionCost].reduce(
          (a, b) => a < b ? a : b,
        );
      }
      final temp = previousRow;
      previousRow = currentRow;
      currentRow = temp;
    }
    return previousRow[t.length];
  }
}
