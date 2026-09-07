import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'incoming_file_types.dart';

/// يغلّف receive_sharing_intent (أندرويد/iOS فقط) وينسخ كل ملف وارد إلى
/// بايتات فورًا (queries content:// عبر الحزمة نفسها التي تنسخه إلى ملف
/// مؤقت داخليًا) — فلا نعتمد نحن على أي URI بعد انتهاء الـ Intent (قسم ٥).
class IncomingFileServiceImpl {
  StreamSubscription<List<SharedMediaFile>>? _sub;
  StreamController<IncomingFile>? _controller;

  Future<IncomingFile?> consumeInitialFile() async {
    try {
      final media = await ReceiveSharingIntent.instance.getInitialMedia();
      // لا حاجة لبقاء هذا الملف في ذاكرة تخزين الحزمة المؤقتة بعد قراءته —
      // ويهم استدعاء reset() هنا تحديدًا حتى لا يُعاد نفس الملف عند أي إعادة
      // بناء لاحقة لواجهة التطبيق (موثَّق في الحزمة).
      ReceiveSharingIntent.instance.reset();
      if (media.isEmpty) return null;
      // await صريح هنا مهم فعليًا (وليس أسلوبًا فقط): بدونه، أي خطأ يُرمى
      // داخل _toIncomingFile يصل بعد أن يكون catch هنا قد انتهى فعليًا (تسلسل
      // Future غير مُنتظَر لا يلتقطه try/catch المحيط) فيفلت كخطأ غير مُمسوك.
      return await _toIncomingFile(media.first);
    } catch (e) {
      debugPrint('IncomingFileService: فشل قراءة الملف الابتدائي: $e');
      return null;
    }
  }

  Stream<IncomingFile> get onFileReceived {
    _controller ??= StreamController<IncomingFile>.broadcast(
      onListen: () {
        _sub = ReceiveSharingIntent.instance.getMediaStream().listen(
          (mediaList) async {
            if (mediaList.isEmpty) return;
            try {
              _controller?.add(await _toIncomingFile(mediaList.first));
            } catch (e) {
              debugPrint('IncomingFileService: فشل قراءة ملف مُستقبَل: $e');
            }
          },
          onError: (Object e) => debugPrint('IncomingFileService: خطأ في تدفق المشاركة: $e'),
        );
      },
      onCancel: () => _sub?.cancel(),
    );
    return _controller!.stream;
  }

  Future<IncomingFile> _toIncomingFile(SharedMediaFile media) async {
    final file = File(media.path);
    try {
      final bytes = await file.readAsBytes();
      final fileName = media.path.split(Platform.pathSeparator).last;
      return IncomingFile(fileName: fileName, mimeType: media.mimeType, bytes: bytes);
    } on FileSystemException catch (e) {
      // نظريًا لا يجب أن يحدث هذا: الحزمة توثّق أنها تنسخ كل ملف (سواء وصل
      // بصيغة content:// أو file://) إلى ملف حقيقي في ذاكرة تخزين مؤقتة
      // قبل أن تُعيد media.path — لكن لو فشل هذا الافتراض في حالة نادرة، لا
      // نملك طريقة Dart خالصة لقراءة content:// مباشرة بلا كود Android أصلي
      // إضافي (Platform Channel جديد) — وهذا بالضبط نوع الاعتماديات الأصلية
      // التي يتجنّبها هذا المشروع عمدًا لتقليل مخاطر CI (راجع README).
      // نفشل هنا بوضوح ورسالة قابلة للتصرف، بدل استثناء خام أو تعليق صامت.
      debugPrint('IncomingFileService: تعذّرت قراءة مسار الملف الوارد (${media.path}): $e');
      throw StateError('تعذّرت قراءة الملف المُشارَك. جرّب المشاركة مرة أخرى، أو افتح التطبيق واستخدم "استيراد" مباشرة.');
    }
  }

  void dispose() {
    _sub?.cancel();
    _controller?.close();
  }
}
