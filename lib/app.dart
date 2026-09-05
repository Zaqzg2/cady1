import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'providers/import_session_provider.dart';
import 'providers/inventory_provider.dart';
import 'providers/settings_provider.dart';
import 'screens/home_shell.dart';
import 'screens/incoming_import_screen.dart';
import 'services/incoming_file_service.dart';
import 'services/storage_service.dart';
import 'theme/app_theme.dart';

class InventoryAnalyzerApp extends StatefulWidget {
  final String? storageInitError;
  const InventoryAnalyzerApp({super.key, this.storageInitError});

  @override
  State<InventoryAnalyzerApp> createState() => _InventoryAnalyzerAppState();
}

class _InventoryAnalyzerAppState extends State<InventoryAnalyzerApp> {
  late String? _storageError = widget.storageInitError;
  bool _retrying = false;

  // Navigator منفصل عبر مفتاح عام، حتى نستطيع التنقّل لشاشة الاستيراد فور
  // استقبال ملف مُشارَك من نظام أندرويد — بمعزل عن أي BuildContext محلي
  // (قسم ٦: التطبيق مغلق/خلفية/مفتوح، الثلاثة تصل هنا بنفس الآلية).
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  StreamSubscription<IncomingFile>? _incomingSub;

  @override
  void initState() {
    super.initState();
    _wireIncomingShares();
  }

  @override
  void dispose() {
    _incomingSub?.cancel();
    IncomingFileService.instance.dispose();
    super.dispose();
  }

  Future<void> _wireIncomingShares() async {
    // حالة "التطبيق كان مغلقًا تمامًا ثم فُتح عبر مشاركة/Open With"
    final initial = await IncomingFileService.instance.consumeInitialFile();
    if (initial != null) _openIncomingImport(initial);

    // حالتا "التطبيق في الخلفية" و"التطبيق مفتوح" — كلاهما يصل كعنصر جديد
    // في نفس هذا التدفق (الحزمة تربطهما بـ onNewIntent داخليًا).
    _incomingSub = IncomingFileService.instance.onFileReceived.listen(_openIncomingImport);
  }

  void _openIncomingImport(IncomingFile file) {
    if (_storageError != null) return; // لا نفتح استيرادًا فوق شاشة خطأ تخزين
    // ننتظر أول/أقرب فريم مبني حتى يكون Navigator جاهزًا فعليًا (مهم خصوصًا
    // عند الفتح البارد، حيث قد يُنجز consumeInitialFile قبل اكتمال أول build).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _navigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => IncomingImportScreen(file: file)),
      );
    });
  }

  Future<void> _retryInit() async {
    setState(() => _retrying = true);
    try {
      await StorageService.instance.init();
      setState(() => _storageError = null);
    } catch (e) {
      setState(() => _storageError = e.toString());
    } finally {
      setState(() => _retrying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // ⚠️ MultiProvider يجب أن يُحيط بـ MaterialApp بالكامل، وليس home: فقط.
    // السبب: MaterialApp يُنشئ Navigator داخليًا، وhome: هو محتوى المسار
    // الأول فقط داخل ذلك الـ Navigator. أي شاشة تُفتَح لاحقًا عبر
    // Navigator.push (الاستيراد، المراجعة، تفاصيل الفرع...) تصبح مسارًا
    // شقيقًا لمسار home ضمن نفس الـ Navigator — وليست امتدادًا لشجرة
    // widgets الخاصة بـhome — فلا ترى أي Provider معرَّف داخل home: إطلاقًا.
    // النتيجة: ProviderNotFoundException أثناء build()، وفي بناء release
    // (على عكس debug) تُستبدَل شاشة الخطأ الحمراء التفصيلية بمربع رمادي
    // فارغ بلا أي رسالة — بالضبط ما ظهر عند فتح شاشة الاستيراد.
    // (الأمر نفسه ينطبق على IncomingImportScreen التي تُفتح عبر _navigatorKey
    // أعلاه — بما أنها تُدفَع على نفس Navigator الداخلي لـ MaterialApp، فهي
    // تبقى ضمن شجرة MultiProvider ولا تحتاج أي ترتيب خاص.)
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => InventoryProvider()..load()),
        ChangeNotifierProvider(create: (_) => ImportSessionProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()..load()),
      ],
      child: MaterialApp(
        navigatorKey: _navigatorKey,
        title: 'محلل المخزون والتقارير الذكي',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, child) => Directionality(
          textDirection: TextDirection.rtl,
          child: child ?? const SizedBox.shrink(),
        ),
        home: _storageError != null
            ? _StorageErrorScreen(
                error: _storageError!,
                retrying: _retrying,
                onRetry: _retryInit,
              )
            : const HomeShell(),
      ),
    );
  }
}

/// شاشة خطأ صريحة بدل تعليق صامت — التطبيق المباشر لدرس "الشاشة البيضاء
/// المعلَّقة للأبد" في دليل الأعطال.
class _StorageErrorScreen extends StatelessWidget {
  final String error;
  final bool retrying;
  final VoidCallback onRetry;
  const _StorageErrorScreen({
    required this.error,
    required this.retrying,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.storage_rounded, size: 56, color: Colors.redAccent),
              const SizedBox(height: 16),
              const Text('تعذّرت تهيئة التخزين المحلي',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(error, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: retrying ? null : onRetry,
                icon: retrying
                    ? const SizedBox(
                        width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh),
                label: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
