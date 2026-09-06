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
      return _toIncomingFile(media.first);
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
    final bytes = await File(media.path).readAsBytes();
    final fileName = media.path.split(Platform.pathSeparator).last;
    return IncomingFile(fileName: fileName, mimeType: media.mimeType, bytes: bytes);
  }

  void dispose() {
    _sub?.cancel();
    _controller?.close();
  }
}
