import 'dart:convert';
import 'dart:typed_data';

/// يتعامل مع محتوى مرفقات طلبات الشراء كـ Base64 داخل Hive مباشرة (بلا نظام
/// ملفات منفصل عبر dart:io) — يعمل بنفس الطريقة تمامًا على أندرويد والويب،
/// لنفس سبب اختيار Hive أصلًا لكل تخزين التطبيق (راجع README). هذا يُبقي
/// "بلا Cloud Storage" (القسم 15) صحيحًا حرفيًا: كل بايت يبقى داخل قاعدة
/// البيانات المحلية للجهاز نفسها.
class AttachmentService {
  /// حد أعلى معقول لحجم مرفق واحد حتى لا يُثقِل صندوق Hive (8 ميغابايت)
  static const maxBytes = 8 * 1024 * 1024;

  String encode(Uint8List bytes) => base64Encode(bytes);

  Uint8List decode(String base64Data) {
    try {
      return base64Decode(base64Data);
    } catch (_) {
      return Uint8List(0);
    }
  }

  bool exceedsLimit(Uint8List bytes) => bytes.lengthInBytes > maxBytes;

  String formatSize(int bytes) {
    if (bytes < 1024) return '$bytes بايت';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} ك.ب';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} م.ب';
  }
}
