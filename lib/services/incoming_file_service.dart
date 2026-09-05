export 'incoming_file_types.dart';

import 'incoming_file_service_stub.dart' if (dart.library.io) 'incoming_file_service_io.dart' as impl;
import 'incoming_file_types.dart';

/// نقطة الدخول الوحيدة لاستقبال الملفات من خارج التطبيق (Share Sheet /
/// Open With — قسم ٣). طبقة رفيعة فوق conditional import: على أندرويد/iOS
/// تُستخدَم receive_sharing_intent فعليًا، وعلى الويب نسخة بلا عملية تلقائيًا
/// — بلا أي فرع if(kIsWeb) يدوي، وبلا استيراد dart:io هنا إطلاقًا.
class IncomingFileService {
  static final IncomingFileService instance = IncomingFileService._();

  final impl.IncomingFileServiceImpl _impl = impl.IncomingFileServiceImpl();

  IncomingFileService._();

  /// الملف الذي فُتح التطبيق بسببه (تطبيق كان مغلقًا تمامًا) — يُستدعى مرة
  /// واحدة عند إقلاع التطبيق. null إن لم يُفتح التطبيق بهذه الطريقة.
  Future<IncomingFile?> consumeInitialFile() => _impl.consumeInitialFile();

  /// أي ملف يصل بعد أن أصبح التطبيق قيد التشغيل فعلًا (خلفية أو مفتوح).
  Stream<IncomingFile> get onFileReceived => _impl.onFileReceived;

  void dispose() => _impl.dispose();
}
