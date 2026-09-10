import 'package:flutter_test/flutter_test.dart';
import 'package:inventory_analyzer/services/import_router.dart';

void main() {
  const router = ImportRouter();

  group('ImportRouter — classification by MIME type (primary signal)', () {
    test('xlsx MIME → excel', () {
      expect(
        router.classify(
          fileName: 'file.bin',
          mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        ),
        RoutedFileType.excel,
      );
    });

    test('csv MIME → csv', () {
      expect(router.classify(fileName: 'file.bin', mimeType: 'text/csv'), RoutedFileType.csv);
    });

    test('pdf MIME → pdf', () {
      expect(router.classify(fileName: 'file.bin', mimeType: 'application/pdf'), RoutedFileType.pdf);
    });

    test('jpeg/png/webp MIME → image', () {
      expect(router.classify(fileName: 'f.bin', mimeType: 'image/jpeg'), RoutedFileType.image);
      expect(router.classify(fileName: 'f.bin', mimeType: 'image/png'), RoutedFileType.image);
      expect(router.classify(fileName: 'f.bin', mimeType: 'image/webp'), RoutedFileType.image);
    });
  });

  group('ImportRouter — extension fallback (when MIME is missing or generic)', () {
    test('application/octet-stream falls back to extension', () {
      expect(router.classify(fileName: 'invoice.pdf', mimeType: 'application/octet-stream'), RoutedFileType.pdf);
      expect(router.classify(fileName: 'sheet.xlsx', mimeType: 'application/octet-stream'), RoutedFileType.excel);
      expect(router.classify(fileName: 'photo.jpg', mimeType: 'application/octet-stream'), RoutedFileType.image);
    });

    test('null MIME type falls back to extension entirely', () {
      expect(router.classify(fileName: 'data.csv', mimeType: null), RoutedFileType.csv);
      expect(router.classify(fileName: 'scan.png', mimeType: null), RoutedFileType.image);
    });

    test('legacy .xls extension is recognized', () {
      expect(router.classify(fileName: 'old.xls', mimeType: null), RoutedFileType.excel);
    });
  });

  group('ImportRouter — unsupported files', () {
    test('unrecognized MIME and extension → unsupported', () {
      expect(router.classify(fileName: 'archive.zip', mimeType: 'application/zip'), RoutedFileType.unsupported);
    });

    test('no extension and no MIME → unsupported, not a crash', () {
      expect(router.classify(fileName: 'noextension', mimeType: null), RoutedFileType.unsupported);
    });

    test('video/audio types are explicitly not routed anywhere', () {
      expect(router.classify(fileName: 'clip.mp4', mimeType: 'video/mp4'), RoutedFileType.unsupported);
      expect(router.classify(fileName: 'song.mp3', mimeType: 'audio/mpeg'), RoutedFileType.unsupported);
    });
  });

  group('RoutedFileTypePresentation', () {
    test('every type has a non-empty Arabic label', () {
      for (final type in RoutedFileType.values) {
        expect(type.labelAr.trim().isNotEmpty, isTrue, reason: 'type: $type');
      }
    });
  });
}
