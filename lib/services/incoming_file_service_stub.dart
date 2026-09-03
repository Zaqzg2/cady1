import 'incoming_file_types.dart';

/// نسخة بلا عملية فعلية — تُستخدَم تلقائيًا فقط على منصّات بلا dart:io
/// (الويب حاليًا). لا نستورد receive_sharing_intent هنا إطلاقًا، والحزمة
/// نفسها أصلًا أندرويد/iOS فقط، فهذا يضمن عدم وجود أي مسار قد يكسر
/// flutter build web.
class IncomingFileServiceImpl {
  Future<IncomingFile?> consumeInitialFile() async => null;

  Stream<IncomingFile> get onFileReceived => const Stream<IncomingFile>.empty();

  void dispose() {}
}
