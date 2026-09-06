import 'dart:typed_data';

/// ملف وصل من خارج التطبيق (Share Sheet أو Open With) بعد أن نُسخ فعليًا
/// إلى بايتات محلية — لا اعتماد متبقٍ على أي content:// مؤقت (قسم ٥).
class IncomingFile {
  final String fileName;
  final String? mimeType;
  final Uint8List bytes;

  const IncomingFile({
    required this.fileName,
    required this.bytes,
    this.mimeType,
  });
}
