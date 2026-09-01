import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'services/storage_service.dart';

void main() {
  // درس رقم 7 في دليل الأعطال: أي init() غير متزامن يُستدعى بلا try/catch قد
  // يختفي بصمت كـ"unhandled Future rejection" ويترك المستخدم على شاشة تحميل
  // معلّقة للأبد بلا أي تفسير. لذلك: runZonedGuarded كخط دفاع أخير + try/catch
  // صريح حول أي تهيئة حرجة قبل runApp.
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      debugPrint('FlutterError: ${details.exceptionAsString()}');
    };

    String? initError;
    try {
      await StorageService.instance.init();
    } catch (e, st) {
      initError = e.toString();
      debugPrint('فشل تهيئة التخزين المحلي: $e\n$st');
      // نستمر بتشغيل التطبيق رغم الفشل — كل Provider يحمل نفس مبدأ try/catch
      // الخاص به ويعرض رسالة خطأ واضحة في الواجهة بدل تعليق صامت بلا تفسير.
    }

    runApp(InventoryAnalyzerApp(storageInitError: initError));
  }, (error, stack) {
    debugPrint('Uncaught zone error: $error\n$stack');
  });
}
