import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// حالة اتصال OCR.space — نفس شكل حالة Mistral (القسم ١٦ من مواصفة Mistral،
/// والقسم ١٩ من مواصفة الدمج) لكن بمزوّد مستقل تمامًا وبمفتاح مستقل (القسم
/// ٣٧: "كل محرك له API Key مستقل" — لا خلط إطلاقًا).
enum OcrSpaceConnectionStatus {
  noKey,
  valid,
  invalidKey,
  rateLimited,
  badRequest,
  networkError,
  timeout,
  serverError,
}

enum OcrSpaceStatusIndicator { connected, attentionNeeded, invalid, inactive }

extension OcrSpaceConnectionStatusPresentation on OcrSpaceConnectionStatus {
  OcrSpaceStatusIndicator get indicator => switch (this) {
        OcrSpaceConnectionStatus.valid => OcrSpaceStatusIndicator.connected,
        OcrSpaceConnectionStatus.noKey => OcrSpaceStatusIndicator.inactive,
        OcrSpaceConnectionStatus.invalidKey => OcrSpaceStatusIndicator.invalid,
        OcrSpaceConnectionStatus.rateLimited ||
        OcrSpaceConnectionStatus.badRequest ||
        OcrSpaceConnectionStatus.networkError ||
        OcrSpaceConnectionStatus.timeout ||
        OcrSpaceConnectionStatus.serverError =>
          OcrSpaceStatusIndicator.attentionNeeded,
      };

  String get emoji => switch (indicator) {
        OcrSpaceStatusIndicator.connected => '🟢',
        OcrSpaceStatusIndicator.attentionNeeded => '🟠',
        OcrSpaceStatusIndicator.invalid => '🔴',
        OcrSpaceStatusIndicator.inactive => '⚪',
      };

  String get labelAr => switch (indicator) {
        OcrSpaceStatusIndicator.connected => 'متصل',
        OcrSpaceStatusIndicator.attentionNeeded => 'يحتاج إعداد',
        OcrSpaceStatusIndicator.invalid => 'مفتاح API غير صالح',
        OcrSpaceStatusIndicator.inactive => 'غير مفعّل',
      };
}

class OcrSpaceHealthResult {
  final OcrSpaceConnectionStatus status;
  final String messageAr;
  final String? debugDetail;
  const OcrSpaceHealthResult({required this.status, required this.messageAr, this.debugDetail});
}

class OcrSpaceConfig {
  final String endpoint;
  final String language;
  final int engine;
  final bool isTable;
  final bool detectOrientation;

  const OcrSpaceConfig({
    this.endpoint = 'https://api.ocr.space/parse/image',
    this.language = 'ara',
    this.engine = 3,
    this.isTable = true,
    this.detectOrientation = true,
  });
}

/// طبقة HTTP / Authentication / Errors لـ OCR.space (القسم ٢٧ من مواصفة
/// Mistral، مطبَّقة هنا لمحرك ثانٍ). فرق جوهري عن Mistral: OCR.space يعيد
/// HTTP 200 دائمًا تقريبًا، حتى عند مفتاح غير صالح أو فشل معالجة — الإشارة
/// الحقيقية داخل الجسم (IsErroredOnProcessing / OCRExitCode / ErrorMessage)،
/// فلا يكفي هنا فحص رمز الحالة وحده كما مع Mistral (موثَّق من عيّنات أخطاء
/// حقيقية على forum.ocr.space، مثل "E550: Invalid free API key" ضمن HTTP 200).
class OcrSpaceApiClient {
  final OcrSpaceConfig config;
  static const _timeout = Duration(seconds: 90);
  static const _healthCheckTimeout = Duration(seconds: 20);

  const OcrSpaceApiClient({this.config = const OcrSpaceConfig()});

  static const Map<OcrSpaceConnectionStatus, String> _messages = {
    OcrSpaceConnectionStatus.noKey: 'لم يتم إعداد OCR.space. جميع الميزات المحلية متاحة.',
    OcrSpaceConnectionStatus.valid: 'المفتاح صالح ومتصل بخدمة OCR.space بنجاح.',
    OcrSpaceConnectionStatus.invalidKey: 'مفتاح API غير صالح لخدمة OCR.space.',
    OcrSpaceConnectionStatus.rateLimited: 'تم تجاوز الحد المسموح لخدمة OCR.space حاليًا. حاول لاحقًا.',
    OcrSpaceConnectionStatus.badRequest: 'طلب غير صالح إلى خدمة OCR.space. تحقق من الإعداد.',
    OcrSpaceConnectionStatus.networkError: 'لا يوجد اتصال بالإنترنت.',
    OcrSpaceConnectionStatus.timeout: 'انتهت مهلة الاتصال بخدمة OCR.space.',
    OcrSpaceConnectionStatus.serverError: 'خدمة OCR.space غير متاحة مؤقتًا.',
  };

  String messageFor(OcrSpaceConnectionStatus status) => _messages[status]!;

  /// apikey كـ Header — وليس Authorization: Bearer ولا x-api-key ولا أي شيء
  /// خاص بـ Mistral (تصحيح صريح مطلوب في القسم ٣ و٣٢ من المواصفة).
  Map<String, String> _headers(String apiKey) => {'apikey': apiKey};

  /// اختبار اتصال خفيف (القسم ١٩) — صورة بيضاء 1×1 حقيقية بدل نص وهمي، حتى
  /// يمر الطلب فعليًا عبر مسار OCR الحقيقي (لا يوجد عند OCR.space endpoint
  /// تعريف/نماذج منفصل مثل GET /v1/models عند Mistral).
  Future<OcrSpaceHealthResult> testConnection(String apiKey) async {
    final trimmed = apiKey.trim();
    if (trimmed.isEmpty) {
      return OcrSpaceHealthResult(status: OcrSpaceConnectionStatus.noKey, messageAr: _messages[OcrSpaceConnectionStatus.noKey]!);
    }
    try {
      final response = await http
          .post(
            Uri.parse(config.endpoint),
            headers: _headers(trimmed),
            body: {'base64Image': _tinyPngDataUri, 'language': config.language, 'isOverlayRequired': 'false'},
          )
          .timeout(_healthCheckTimeout);
      return classifyResponse(response);
    } catch (e) {
      return classifyException(e);
    }
  }

  Future<http.Response> parseImage(String apiKey, Map<String, String> formFields) {
    return http
        .post(Uri.parse(config.endpoint), headers: _headers(apiKey.trim()), body: formFields)
        .timeout(_timeout);
  }

  /// يفحص رمز HTTP أولًا (طبقات شبكة/بروكسي قد تُصدر 429/5xx فعلية)، ثم
  /// يفحص جسم الاستجابة دفاعيًا حتى مع 200 — هذا هو الفرق الجوهري عن Mistral.
  OcrSpaceHealthResult classifyResponse(http.Response response) {
    final code = response.statusCode;
    if (code == 401 || code == 403) {
      return OcrSpaceHealthResult(status: OcrSpaceConnectionStatus.invalidKey, messageAr: _messages[OcrSpaceConnectionStatus.invalidKey]!);
    }
    if (code == 429) {
      return OcrSpaceHealthResult(status: OcrSpaceConnectionStatus.rateLimited, messageAr: _messages[OcrSpaceConnectionStatus.rateLimited]!);
    }
    if (code >= 500) {
      return OcrSpaceHealthResult(status: OcrSpaceConnectionStatus.serverError, messageAr: _messages[OcrSpaceConnectionStatus.serverError]!);
    }

    Map<String, dynamic>? body;
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) body = decoded;
    } catch (_) {
      // جسم غير JSON — نتعامل معه كخطأ خادم عام بدل الانهيار
      return OcrSpaceHealthResult(status: OcrSpaceConnectionStatus.serverError, messageAr: _messages[OcrSpaceConnectionStatus.serverError]!);
    }
    if (body == null) {
      return OcrSpaceHealthResult(status: OcrSpaceConnectionStatus.serverError, messageAr: _messages[OcrSpaceConnectionStatus.serverError]!);
    }

    final isErrored = body['IsErroredOnProcessing'] == true;
    if (!isErrored && code == 200) {
      return OcrSpaceHealthResult(status: OcrSpaceConnectionStatus.valid, messageAr: _messages[OcrSpaceConnectionStatus.valid]!);
    }

    final messages = _errorMessagesOf(body);
    final joined = messages.join(' ').toLowerCase();
    if (joined.contains('api key') || joined.contains('apikey')) {
      return OcrSpaceHealthResult(
        status: OcrSpaceConnectionStatus.invalidKey,
        messageAr: _messages[OcrSpaceConnectionStatus.invalidKey]!,
        debugDetail: messages.join(' | '),
      );
    }
    if (joined.contains('limit') || joined.contains('too many') || joined.contains('exceeded')) {
      return OcrSpaceHealthResult(
        status: OcrSpaceConnectionStatus.rateLimited,
        messageAr: _messages[OcrSpaceConnectionStatus.rateLimited]!,
        debugDetail: messages.join(' | '),
      );
    }
    return OcrSpaceHealthResult(
      status: OcrSpaceConnectionStatus.badRequest,
      messageAr: _messages[OcrSpaceConnectionStatus.badRequest]!,
      debugDetail: messages.join(' | '),
    );
  }

  List<String> _errorMessagesOf(Map<String, dynamic> body) {
    final raw = body['ErrorMessage'];
    if (raw is List) return raw.map((e) => e.toString()).toList();
    if (raw is String && raw.isNotEmpty) return [raw];
    return ['استجابة غير معروفة من OCR.space'];
  }

  OcrSpaceHealthResult classifyException(Object e) {
    if (e is TimeoutException) {
      return OcrSpaceHealthResult(status: OcrSpaceConnectionStatus.timeout, messageAr: _messages[OcrSpaceConnectionStatus.timeout]!);
    }
    final raw = e.toString();
    debugPrint('OcrSpaceApiClient: $raw'); // Debug Log فقط — لا يُعرض للمستخدم
    final status = _looksLikeNetworkFailure(raw) ? OcrSpaceConnectionStatus.networkError : OcrSpaceConnectionStatus.serverError;
    return OcrSpaceHealthResult(status: status, messageAr: _messages[status]!, debugDetail: raw);
  }

  bool _looksLikeNetworkFailure(String raw) {
    final lower = raw.toLowerCase();
    const markers = [
      'socketexception', 'failed host lookup', 'connection refused', 'connection reset',
      'connection closed', 'network is unreachable', 'clientexception', 'failed to fetch',
      'xmlhttprequest', 'err_internet_disconnected', 'err_name_not_resolved', 'handshakeexception', 'certificate',
    ];
    return markers.any(lower.contains);
  }

  // صورة PNG بيضاء 1×1 بكسل صالحة فعليًا — كافية لاختبار مسار OCR الحقيقي
  // بلا تحميل أي ملف مستخدم فعلي فقط لأجل زر [اختبار OCR.space].
  static const _tinyPngDataUri =
      'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';
}
