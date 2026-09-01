import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

enum ImageQualityHint { lowResolution, tooDark, tooBright }

extension ImageQualityHintMessage on ImageQualityHint {
  String get messageAr => switch (this) {
        ImageQualityHint.lowResolution =>
          'دقة الصورة منخفضة جدًا. اقترب من المستند وتأكد من ثبات الهاتف عند التصوير.',
        ImageQualityHint.tooDark =>
          'الصورة غير واضحة بما يكفي (إضاءة ضعيفة). حسّن الإضاءة وتجنّب الظلال.',
        ImageQualityHint.tooBright =>
          'الصورة شديدة السطوع/الانعكاس. غيّر زاوية التصوير أو ابتعد عن مصدر الضوء المباشر.',
      };
}

/// التقاط/اختيار صورة، مع خطوات تحسين أساسية (تدوير حسب EXIF + تباين/سطوع)
/// قبل إرسالها لمحرك الاستخراج. تصحيح المنظور (Perspective) الكامل والقص
/// التفاعلي للحواف متروكان كخطوة تالية موثّقة في README — راجع القسم المخصص.
class ImageImportService {
  final ImagePicker _picker = ImagePicker();

  Future<Uint8List?> pickFromGallery() async {
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 95,
    );
    if (file == null) return null;
    return _preprocess(await file.readAsBytes());
  }

  Future<Uint8List?> captureFromCamera() async {
    final file = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 95,
      preferredCameraDevice: CameraDevice.rear,
    );
    if (file == null) return null;
    return _preprocess(await file.readAsBytes());
  }

  /// فحص جودة سريع يعمل على نسخة مصغَّرة من الصورة (لا يبطئ الواجهة)
  ImageQualityHint? assessQuality(Uint8List bytes) {
    try {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;
      if (decoded.width < 400 || decoded.height < 400) {
        return ImageQualityHint.lowResolution;
      }

      final thumb = img.copyResize(decoded, width: 48);
      var totalLuma = 0.0;
      var count = 0;
      for (var y = 0; y < thumb.height; y++) {
        for (var x = 0; x < thumb.width; x++) {
          final p = thumb.getPixel(x, y);
          totalLuma += 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
          count++;
        }
      }
      final avgLuma = count == 0 ? 128.0 : totalLuma / count;
      if (avgLuma < 55) return ImageQualityHint.tooDark;
      if (avgLuma > 235) return ImageQualityHint.tooBright;
      return null;
    } catch (_) {
      return null;
    }
  }

  Uint8List _preprocess(Uint8List original) {
    try {
      var decoded = img.decodeImage(original);
      if (decoded == null) return original;

      // تصحيح الدوران حسب بيانات EXIF (شائع جدًا في صور الكاميرا)
      decoded = img.bakeOrientation(decoded);

      // تصغير الأبعاد الكبيرة جدًا فقط (يسرّع الرفع دون التأثير على وضوح النص)
      if (decoded.width > 2200) {
        decoded = img.copyResize(decoded, width: 2200);
      }

      decoded = img.adjustColor(decoded, contrast: 1.15, brightness: 1.03);
      return Uint8List.fromList(img.encodeJpg(decoded, quality: 92));
    } catch (_) {
      // أي فشل في التحسين لا يجب أن يوقف الاستيراد بالكامل
      return original;
    }
  }
}
