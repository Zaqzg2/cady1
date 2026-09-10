import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// شاشة مسح Barcode (القسم V). تُعيد النص المُمسوح/المُدخَل عبر
/// Navigator.pop(context, code)، أو null عند الإلغاء.
///
/// على الويب: لا كاميرا إطلاقًا (القسم V يسمح صراحةً بهذا: "اجعل Barcode
/// Scanner يعمل على Android فقط مع fallback للبحث اليدوي على Web") — حقل
/// إدخال يدوي فقط. على أندرويد: كاميرا فعلية + نفس حقل الإدخال اليدوي
/// متاح دائمًا أسفلها (شبكة أمان إن تعذّر إذن الكاميرا أو قراءة الكود).
///
/// ⚠️ لم يُختبَر المسح الفعلي بالكاميرا على جهاز حقيقي في بيئة التطوير هذه.
class BarcodeScannerScreen extends StatefulWidget {
  const BarcodeScannerScreen({super.key});

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> {
  MobileScannerController? _controller;
  final _manualController = TextEditingController();
  bool _handled = false; // يمنع استدعاء pop مرتين لو اكتُشف الكود أكثر من إطار متتالٍ

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      _controller = MobileScannerController(formats: const [
        BarcodeFormat.ean13,
        BarcodeFormat.ean8,
        BarcodeFormat.upcA,
        BarcodeFormat.upcE,
        BarcodeFormat.code128,
        BarcodeFormat.code39,
        BarcodeFormat.qrCode,
      ]);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _manualController.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    final value = capture.barcodes.firstOrNull?.rawValue?.trim();
    if (value == null || value.isEmpty) return;
    _handled = true;
    Navigator.of(context).pop(value);
  }

  void _submitManual() {
    final value = _manualController.text.trim();
    if (value.isEmpty) return;
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      appBar: AppBar(title: const Text('مسح Barcode')),
      body: Column(
        children: [
          if (controller != null)
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  MobileScanner(controller: controller, onDetect: _onDetect),
                  Align(
                    alignment: Alignment.topCenter,
                    child: Container(
                      margin: const EdgeInsets.only(top: 16),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text('وجّه الكاميرا نحو الـ Barcode',
                          style: TextStyle(color: Colors.white, fontSize: 12.5)),
                    ),
                  ),
                ],
              ),
            )
          else
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'المسح بالكاميرا متاح على تطبيق أندرويد. أدخل الرقم يدويًا هنا:',
                textAlign: TextAlign.center,
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _manualController,
                      keyboardType: TextInputType.text,
                      decoration: const InputDecoration(
                        labelText: 'إدخال يدوي',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _submitManual(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(onPressed: _submitManual, child: const Text('بحث')),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
