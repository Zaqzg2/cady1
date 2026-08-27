class ArabicUtils {
  /// Normalize Arabic text for fuzzy matching
  static String normalize(String text) {
    if (text.isEmpty) return text;
    return text
        .replaceAll('ة', 'ه')
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ى', 'ي')
        .replaceAll('ؤ', 'و')
        .replaceAll('ئ', 'ي')
        .replaceAll(RegExp(r'[ًٌٍَُِّْ]'), '') // remove diacritics
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .toLowerCase();
  }

  /// Simple Levenshtein distance for fuzzy matching
  static int levenshtein(String s1, String s2) {
    if (s1 == s2) return 0;
    if (s1.isEmpty) return s2.length;
    if (s2.isEmpty) return s1.length;

    final len1 = s1.length;
    final len2 = s2.length;
    final matrix = List.generate(len1 + 1, (_) => List<int>.filled(len2 + 1, 0));

    for (var i = 0; i <= len1; i++) {
      matrix[i][0] = i;
    }
    for (var j = 0; j <= len2; j++) {
      matrix[0][j] = j;
    }

    for (var i = 1; i <= len1; i++) {
      for (var j = 1; j <= len2; j++) {
        final cost = s1[i - 1] == s2[j - 1] ? 0 : 1;
        matrix[i][j] = [
          matrix[i - 1][j] + 1,
          matrix[i][j - 1] + 1,
          matrix[i - 1][j - 1] + cost,
        ].reduce((a, b) => a < b ? a : b);
      }
    }
    return matrix[len1][len2];
  }

  /// Similarity score 0.0 - 1.0
  static double similarity(String a, String b) {
    final n1 = normalize(a);
    final n2 = normalize(b);
    if (n1.isEmpty || n2.isEmpty) return 0;
    if (n1 == n2) return 1.0;
    final distance = levenshtein(n1, n2);
    final maxLen = n1.length > n2.length ? n1.length : n2.length;
    return 1.0 - (distance / maxLen);
  }

  /// Check if two product names likely refer to the same item
  static bool isLikelySameProduct(String a, String b, {double threshold = 0.72}) {
    return similarity(a, b) >= threshold;
  }
}