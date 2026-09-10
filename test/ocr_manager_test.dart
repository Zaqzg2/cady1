import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:inventory_analyzer/services/ocr_manager.dart';
import 'package:inventory_analyzer/services/ocr_service.dart';

/// محرك وهمي بنتيجة/عدد استدعاءات ثابتة، للتحقق من منطق fallback فقط —
/// بلا أي نداء شبكة حقيقي.
class _FakeEngine implements OcrEngine {
  final bool succeeds;
  final String label;
  int callCount = 0;

  _FakeEngine({required this.succeeds, required this.label});

  @override
  Future<OcrExtractionResult> extractTable(Uint8List bytes, {required String mimeType, String? contextHint}) async {
    callCount++;
    if (succeeds) {
      return OcrExtractionResult.success([], provider: label);
    }
    return OcrExtractionResult.failure('فشل $label للاختبار', provider: label);
  }
}

void main() {
  final bytes = Uint8List(0);

  group('OcrManager — no engines configured', () {
    test('returns a clear failure without touching any engine', () async {
      const manager = OcrManager(
        mistralApiKey: null,
        ocrSpaceApiKey: null,
        selection: OcrEngineSelection.automatic,
        autoFallbackEnabled: true,
      );
      final result = await manager.process(bytes, mimeType: 'image/jpeg');
      expect(result.success, isFalse);
    });
  });

  group('OcrManager — manual selection never falls back (section 8)', () {
    test('selection=mistral with a failing Mistral engine does NOT try OCR.space, even if configured', () async {
      final mistral = _FakeEngine(succeeds: false, label: 'mistral');
      final ocrSpace = _FakeEngine(succeeds: true, label: 'ocr_space');
      final manager = OcrManager(
        mistralApiKey: null,
        ocrSpaceApiKey: null,
        selection: OcrEngineSelection.mistral,
        autoFallbackEnabled: true, // حتى مع تفعيله — لا يُستخدَم إلا في "تلقائي"
        mistralEngineOverride: mistral,
        ocrSpaceEngineOverride: ocrSpace,
      );
      final result = await manager.process(bytes, mimeType: 'image/jpeg');
      expect(result.success, isFalse);
      expect(mistral.callCount, 1);
      expect(ocrSpace.callCount, 0);
    });

    test('selection=ocrSpace uses only OCR.space regardless of Mistral', () async {
      final mistral = _FakeEngine(succeeds: true, label: 'mistral');
      final ocrSpace = _FakeEngine(succeeds: true, label: 'ocr_space');
      final manager = OcrManager(
        mistralApiKey: null,
        ocrSpaceApiKey: null,
        selection: OcrEngineSelection.ocrSpace,
        autoFallbackEnabled: true,
        mistralEngineOverride: mistral,
        ocrSpaceEngineOverride: ocrSpace,
      );
      final result = await manager.process(bytes, mimeType: 'image/jpeg');
      expect(result.success, isTrue);
      expect(result.provider, 'ocr_space');
      expect(mistral.callCount, 0);
    });
  });

  group('OcrManager — automatic mode (section 9, 37)', () {
    test('Mistral succeeds → OCR.space is never called', () async {
      final mistral = _FakeEngine(succeeds: true, label: 'mistral');
      final ocrSpace = _FakeEngine(succeeds: true, label: 'ocr_space');
      final manager = OcrManager(
        mistralApiKey: null,
        ocrSpaceApiKey: null,
        selection: OcrEngineSelection.automatic,
        autoFallbackEnabled: true,
        mistralEngineOverride: mistral,
        ocrSpaceEngineOverride: ocrSpace,
      );
      final result = await manager.process(bytes, mimeType: 'image/jpeg');
      expect(result.success, isTrue);
      expect(result.provider, 'mistral');
      expect(ocrSpace.callCount, 0);
    });

    test('Mistral fails, fallback enabled, OCR.space configured → falls back and succeeds', () async {
      final mistral = _FakeEngine(succeeds: false, label: 'mistral');
      final ocrSpace = _FakeEngine(succeeds: true, label: 'ocr_space');
      final manager = OcrManager(
        mistralApiKey: null,
        ocrSpaceApiKey: null,
        selection: OcrEngineSelection.automatic,
        autoFallbackEnabled: true,
        mistralEngineOverride: mistral,
        ocrSpaceEngineOverride: ocrSpace,
      );
      final result = await manager.process(bytes, mimeType: 'image/jpeg');
      expect(result.success, isTrue);
      expect(result.provider, 'ocr_space');
      expect(mistral.callCount, 1);
      expect(ocrSpace.callCount, 1);
    });

    test('Mistral fails, fallback DISABLED → returns Mistral failure, OCR.space never called', () async {
      final mistral = _FakeEngine(succeeds: false, label: 'mistral');
      final ocrSpace = _FakeEngine(succeeds: true, label: 'ocr_space');
      final manager = OcrManager(
        mistralApiKey: null,
        ocrSpaceApiKey: null,
        selection: OcrEngineSelection.automatic,
        autoFallbackEnabled: false,
        mistralEngineOverride: mistral,
        ocrSpaceEngineOverride: ocrSpace,
      );
      final result = await manager.process(bytes, mimeType: 'image/jpeg');
      expect(result.success, isFalse);
      expect(result.provider, 'mistral');
      expect(ocrSpace.callCount, 0);
    });

    test('both fail → returns the PRIMARY (Mistral) failure, not the fallback one', () async {
      final mistral = _FakeEngine(succeeds: false, label: 'mistral');
      final ocrSpace = _FakeEngine(succeeds: false, label: 'ocr_space');
      final manager = OcrManager(
        mistralApiKey: null,
        ocrSpaceApiKey: null,
        selection: OcrEngineSelection.automatic,
        autoFallbackEnabled: true,
        mistralEngineOverride: mistral,
        ocrSpaceEngineOverride: ocrSpace,
      );
      final result = await manager.process(bytes, mimeType: 'image/jpeg');
      expect(result.success, isFalse);
      expect(result.provider, 'mistral');
    });

    test('Mistral not configured at all → uses OCR.space directly, not framed as a fallback failure', () async {
      final ocrSpace = _FakeEngine(succeeds: true, label: 'ocr_space');
      final manager = OcrManager(
        mistralApiKey: null,
        ocrSpaceApiKey: null,
        selection: OcrEngineSelection.automatic,
        autoFallbackEnabled: true,
        ocrSpaceEngineOverride: ocrSpace,
      );
      final result = await manager.process(bytes, mimeType: 'image/jpeg');
      expect(result.success, isTrue);
      expect(result.provider, 'ocr_space');
    });

    test('Mistral fails, fallback enabled, but OCR.space NOT configured → returns Mistral failure', () async {
      final mistral = _FakeEngine(succeeds: false, label: 'mistral');
      final manager = OcrManager(
        mistralApiKey: null,
        ocrSpaceApiKey: null,
        selection: OcrEngineSelection.automatic,
        autoFallbackEnabled: true,
        mistralEngineOverride: mistral,
      );
      final result = await manager.process(bytes, mimeType: 'image/jpeg');
      expect(result.success, isFalse);
      expect(result.provider, 'mistral');
    });
  });

  group('OcrManager implements OcrEngine transparently', () {
    test('extractTable() and process() behave identically', () async {
      final mistral = _FakeEngine(succeeds: true, label: 'mistral');
      final OcrEngine manager = OcrManager(
        mistralApiKey: null,
        ocrSpaceApiKey: null,
        selection: OcrEngineSelection.mistral,
        autoFallbackEnabled: false,
        mistralEngineOverride: mistral,
      );
      final result = await manager.extractTable(bytes, mimeType: 'image/jpeg');
      expect(result.success, isTrue);
    });
  });
}
