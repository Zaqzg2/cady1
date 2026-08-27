import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

enum ImportSourceType {
  excel,
  pdf,
  image,
  camera,
}

enum ImportStatus {
  pending,
  processing,
  needsReview,
  completed,
  failed,
}

class ImportRecord extends Equatable {
  final String id;
  final ImportSourceType sourceType;
  final String fileName;
  final String? filePath;
  final ImportStatus status;
  final int totalRows;
  final int verifiedRows;
  final int lowConfidenceRows;
  final String? errorMessage;
  final DateTime importedAt;
  final DateTime? completedAt;
  final Map<String, String>? columnMapping; // original -> standard

  const ImportRecord({
    required this.id,
    required this.sourceType,
    required this.fileName,
    this.filePath,
    required this.status,
    this.totalRows = 0,
    this.verifiedRows = 0,
    this.lowConfidenceRows = 0,
    this.errorMessage,
    required this.importedAt,
    this.completedAt,
    this.columnMapping,
  });

  factory ImportRecord.create({
    required ImportSourceType sourceType,
    required String fileName,
    String? filePath,
  }) {
    return ImportRecord(
      id: const Uuid().v4(),
      sourceType: sourceType,
      fileName: fileName,
      filePath: filePath,
      status: ImportStatus.pending,
      importedAt: DateTime.now(),
    );
  }

  String get sourceTypeLabel {
    switch (sourceType) {
      case ImportSourceType.excel:
        return 'Excel';
      case ImportSourceType.pdf:
        return 'PDF';
      case ImportSourceType.image:
        return 'صورة';
      case ImportSourceType.camera:
        return 'تصوير';
    }
  }

  String get statusLabel {
    switch (status) {
      case ImportStatus.pending:
        return 'قيد الانتظار';
      case ImportStatus.processing:
        return 'جاري المعالجة';
      case ImportStatus.needsReview:
        return 'يحتاج مراجعة';
      case ImportStatus.completed:
        return 'مكتمل';
      case ImportStatus.failed:
        return 'فشل';
    }
  }

  ImportRecord copyWith({
    ImportStatus? status,
    int? totalRows,
    int? verifiedRows,
    int? lowConfidenceRows,
    String? errorMessage,
    DateTime? completedAt,
    Map<String, String>? columnMapping,
  }) {
    return ImportRecord(
      id: id,
      sourceType: sourceType,
      fileName: fileName,
      filePath: filePath,
      status: status ?? this.status,
      totalRows: totalRows ?? this.totalRows,
      verifiedRows: verifiedRows ?? this.verifiedRows,
      lowConfidenceRows: lowConfidenceRows ?? this.lowConfidenceRows,
      errorMessage: errorMessage ?? this.errorMessage,
      importedAt: importedAt,
      completedAt: completedAt ?? this.completedAt,
      columnMapping: columnMapping ?? this.columnMapping,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'sourceType': sourceType.name,
        'fileName': fileName,
        'filePath': filePath,
        'status': status.name,
        'totalRows': totalRows,
        'verifiedRows': verifiedRows,
        'lowConfidenceRows': lowConfidenceRows,
        'errorMessage': errorMessage,
        'importedAt': importedAt.toIso8601String(),
        'completedAt': completedAt?.toIso8601String(),
        'columnMapping': columnMapping,
      };

  factory ImportRecord.fromMap(Map<String, dynamic> map) => ImportRecord(
        id: map['id'] as String,
        sourceType: ImportSourceType.values.firstWhere(
          (e) => e.name == map['sourceType'],
          orElse: () => ImportSourceType.excel,
        ),
        fileName: map['fileName'] as String,
        filePath: map['filePath'] as String?,
        status: ImportStatus.values.firstWhere(
          (e) => e.name == map['status'],
          orElse: () => ImportStatus.pending,
        ),
        totalRows: map['totalRows'] as int? ?? 0,
        verifiedRows: map['verifiedRows'] as int? ?? 0,
        lowConfidenceRows: map['lowConfidenceRows'] as int? ?? 0,
        errorMessage: map['errorMessage'] as String?,
        importedAt: DateTime.parse(map['importedAt'] as String),
        completedAt: map['completedAt'] != null
            ? DateTime.parse(map['completedAt'] as String)
            : null,
        columnMapping: map['columnMapping'] != null
            ? Map<String, String>.from(map['columnMapping'] as Map)
            : null,
      );

  @override
  List<Object?> get props => [id, sourceType, fileName, status];
}