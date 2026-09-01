import 'dart:typed_data';

import 'package:printing/printing.dart';

class PdfRenderResult {
  final bool success;
  final String? error;
  final List<Uint8List> pageImages;
  final bool truncated;

  PdfRenderResult._({
    required this.success,
    this.error,
    this.pageImages = const [],
    this.truncated = false,
  });

  factory PdfRenderResult.failure(String error) =>
      PdfRenderResult._(success: false, error: error);

  factory PdfRenderResult.success(List<Uint8List> images, {bool truncated = false}) =>
      PdfRenderResult._(success: true, pageImages: images, truncated: truncated);
}

/// يحوّل كل صفحة PDF إلى صورة PNG، بدل محاولة استخراج طبقة نص PDF مباشرة.
/// هذا يوحّد المسار مع مسار الصور/الكاميرا (نفس محرك OCR/الذكاء الاصطناعي)،
/// ويتعامل بنفس الجودة مع الملفات الممسوحة ضوئيًا والملفات الرقمية الأصلية.
class PdfImportService {
  Future<PdfRenderResult> renderPagesAsImages(
    Uint8List pdfBytes, {
    int maxPages = 15,
    double dpi = 200,
  }) async {
    try {
      final images = <Uint8List>[];
      var count = 0;
      var truncated = false;

      await for (final page in Printing.raster(pdfBytes, dpi: dpi)) {
        if (count >= maxPages) {
          truncated = true;
          break;
        }
        final png = await page.toPng();
        images.add(png);
        count++;
      }

      if (images.isEmpty) {
        return PdfRenderResult.failure('لم يتم العثور على صفحات قابلة للقراءة في ملف PDF.');
      }
      return PdfRenderResult.success(images, truncated: truncated);
    } catch (e) {
      return PdfRenderResult.failure('تعذّرت قراءة ملف PDF: $e');
    }
  }
}
