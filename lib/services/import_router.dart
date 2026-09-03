enum RoutedFileType { excel, csv, pdf, image, unsupported }

/// يحدد نوع الملف تلقائيًا (قسم ٧). هذه الطبقة تصنيف فقط — لا تحتوي أي
/// منطق استيراد بنفسها؛ التوجيه الفعلي يتم في
/// ImportSessionProvider.importRoutedFile عبر استدعاء دوال الاستيراد
/// الموجودة أصلًا (Excel/PDF/صورة)، فلا يوجد أي مسار استيراد مستقل مكرر
/// لملفات المشاركة (قسم ١٤).
class ImportRouter {
  const ImportRouter();

  static const _excelMimeTypes = {
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'application/vnd.ms-excel',
  };
  static const _csvMimeTypes = {'text/csv', 'application/csv'};
  static const _imageMimeTypes = {'image/jpeg', 'image/png', 'image/webp'};

  RoutedFileType classify({required String fileName, String? mimeType}) {
    final byMime = _classifyByMime(mimeType);
    if (byMime != RoutedFileType.unsupported) return byMime;
    // احتياطي: بعض تطبيقات المشاركة ترسل application/octet-stream عامًا أو
    // mimeType غير دقيق — الامتداد هو المرجع الثاني (قسم ٧).
    return _classifyByExtension(fileName);
  }

  RoutedFileType _classifyByMime(String? mimeType) {
    if (mimeType == null) return RoutedFileType.unsupported;
    if (_excelMimeTypes.contains(mimeType)) return RoutedFileType.excel;
    if (_csvMimeTypes.contains(mimeType)) return RoutedFileType.csv;
    if (mimeType == 'application/pdf') return RoutedFileType.pdf;
    if (_imageMimeTypes.contains(mimeType)) return RoutedFileType.image;
    return RoutedFileType.unsupported;
  }

  RoutedFileType _classifyByExtension(String fileName) {
    final dot = fileName.lastIndexOf('.');
    final ext = dot == -1 ? '' : fileName.substring(dot + 1).toLowerCase();
    switch (ext) {
      case 'xlsx':
      case 'xls':
        return RoutedFileType.excel;
      case 'csv':
        return RoutedFileType.csv;
      case 'pdf':
        return RoutedFileType.pdf;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'webp':
        return RoutedFileType.image;
      default:
        return RoutedFileType.unsupported;
    }
  }
}

extension RoutedFileTypePresentation on RoutedFileType {
  String get labelAr => switch (this) {
        RoutedFileType.excel => 'ملف Excel',
        RoutedFileType.csv => 'ملف CSV',
        RoutedFileType.pdf => 'ملف PDF',
        RoutedFileType.image => 'صورة',
        RoutedFileType.unsupported => 'نوع غير مدعوم',
      };
}
