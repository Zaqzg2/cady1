import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// حالة الاتصال بـ Mistral — القسم ١٦ من المواصفة. تُبنى من رمز HTTP الفعلي
/// وليس من شكل المفتاح (نفس مبدأ ما كان معتمدًا مع Anthropic سابقًا).
enum MistralConnectionStatus {
  noKey,
  valid,
  invalidKey, // 401
  forbidden, // 403
  rateLimited, // 429
  badRequest, // 400 / 404 / 422 — طلب أو تهيئة غير صالحة، وليس مشكلة في المفتاح نفسه
  networkError,
  timeout,
  serverError, // 5xx
}

enum MistralStatusIndicator { connected, attentionNeeded, invalid, inactive }

extension MistralConnectionStatusPresentation on MistralConnectionStatus {
  MistralStatusIndicator get indicator => switch (this) {
        MistralConnectionStatus.valid => MistralStatusIndicator.connected,
        MistralConnectionStatus.noKey => MistralStatusIndicator.inactive,
        MistralConnectionStatus.invalidKey ||
        MistralConnectionStatus.forbidden =>
          MistralStatusIndicator.invalid,
        MistralConnectionStatus.rateLimited ||
        MistralConnectionStatus.badRequest ||
        MistralConnectionStatus.networkError ||
        MistralConnectionStatus.timeout ||
        MistralConnectionStatus.serverError =>
          MistralStatusIndicator.attentionNeeded,
      };

  String get emoji => switch (indicator) {
        MistralStatusIndicator.connected => '🟢',
        MistralStatusIndicator.attentionNeeded => '🟠',
        MistralStatusIndicator.invalid => '🔴',
        MistralStatusIndicator.inactive => '⚪',
      };

  String get labelAr => switch (indicator) {
        MistralStatusIndicator.connected => 'متصل',
        MistralStatusIndicator.attentionNeeded => 'يحتاج إعداد',
        MistralStatusIndicator.invalid => 'مفتاح غير صالح',
        MistralStatusIndicator.inactive => 'غير مفعّل',
      };
}

class MistralHealthResult {
  final MistralConnectionStatus status;
  final String messageAr;
  final String? debugDetail;
  const MistralHealthResult({required this.status, required this.messageAr, this.debugDetail});
}

/// إعداد قابل للتخصيص (القسم ٢٤) بدل تثبيت اسم النموذج/الرابط داخل الكود.
class MistralOcrConfig {
  final String model;
  final String endpoint;
  const MistralOcrConfig({
    this.model = 'mistral-ocr-latest',
    this.endpoint = 'https://api.mistral.ai/v1/ocr',
  });

  /// يُشتَق من endpoint بدل تثبيت رابط منفصل — .../v1/ocr → .../v1/models
  /// (رابط خفيف رسميًا لاختبار المفتاح بلا أي تكلفة OCR فعلية — القسم ١٦).
  Uri get modelsUri {
    final uri = Uri.parse(endpoint);
    final segments = List<String>.from(uri.pathSegments);
    if (segments.isNotEmpty && segments.last == 'ocr') {
      segments[segments.length - 1] = 'models';
    } else if (!segments.contains('models')) {
      segments.add('models');
    }
    return uri.replace(pathSegments: segments);
  }
}

/// طبقة HTTP / Authentication / Errors المستقلة لـ Mistral (القسم ٢٧).
/// تحل محل ApiHealthService القديم (Anthropic) بالكامل — لا اعتماد متبقٍ على
/// x-api-key أو anthropic-version أو أي شيء خاص بـ Claude (القسم ٣، ٢٦).
class MistralApiClient {
  final MistralOcrConfig config;
  static const _timeout = Duration(seconds: 90); // OCR فعلي قد يأخذ وقتًا أطول من فحص مفتاح بسيط
  static const _healthCheckTimeout = Duration(seconds: 15);

  const MistralApiClient({this.config = const MistralOcrConfig()});

  static const Map<MistralConnectionStatus, String> _messages = {
    MistralConnectionStatus.noKey: 'لم يتم إعداد Mistral. جميع الميزات المحلية متاحة.',
    MistralConnectionStatus.valid: 'المفتاح صالح ومتصل بخدمة Mistral بنجاح.',
    MistralConnectionStatus.invalidKey: 'مفتاح Mistral غير صالح أو غير مصادق عليه.',
    MistralConnectionStatus.forbidden: 'الوصول إلى خدمة Mistral مرفوض.',
    MistralConnectionStatus.rateLimited: 'تم تجاوز الحد المسموح حاليًا. حاول لاحقًا.',
    MistralConnectionStatus.badRequest: 'طلب غير صالح إلى خدمة Mistral. تحقق من الإعداد.',
    MistralConnectionStatus.networkError: 'لا يوجد اتصال بالإنترنت.',
    MistralConnectionStatus.timeout: 'انتهت مهلة الاتصال بخدمة Mistral.',
    MistralConnectionStatus.serverError: 'خدمة Mistral غير متاحة مؤقتًا.',
  };

  String messageFor(MistralConnectionStatus status) => _messages[status]!;

  Map<String, String> _headers(String apiKey) => {
        'Content-Type': 'application/json',
        // Bearer فقط — ممنوع x-api-key أو anthropic-version (القسم ٣، ٢٦)
        'Authorization': 'Bearer $apiKey',
      };

  /// اختبار اتصال خفيف (القسم ١٦) — GET /v1/models، بلا أي استدعاء OCR فعلي
  /// (لا داعٍ لدفع تكلفة معالجة مستند فقط للتحقق من صلاحية المفتاح).
  Future<MistralHealthResult> testConnection(String apiKey) async {
    final trimmed = apiKey.trim();
    if (trimmed.isEmpty) {
      return MistralHealthResult(status: MistralConnectionStatus.noKey, messageAr: _messages[MistralConnectionStatus.noKey]!);
    }
    try {
      final response = await http
          .get(config.modelsUri, headers: _headers(trimmed))
          .timeout(_healthCheckTimeout);
      return classifyHttpResponse(response);
    } catch (e) {
      return classifyException(e);
    }
  }

  /// نداء OCR خام — تُبنى معاملات الطلب في MistralOcrService، هذه الطبقة
  /// مسؤولة فقط عن الاتصال HTTP نفسه وتصنيف أي فشل.
  Future<http.Response> postOcr(String apiKey, Map<String, dynamic> body) {
    return http
        .post(Uri.parse(config.endpoint), headers: _headers(apiKey.trim()), body: jsonEncode(body))
        .timeout(_timeout);
  }

  MistralHealthResult classifyHttpResponse(http.Response response) {
    final code = response.statusCode;
    if (code == 200) {
      return MistralHealthResult(status: MistralConnectionStatus.valid, messageAr: _messages[MistralConnectionStatus.valid]!);
    }
    final status = switch (code) {
      401 => MistralConnectionStatus.invalidKey,
      403 => MistralConnectionStatus.forbidden,
      429 => MistralConnectionStatus.rateLimited,
      400 || 404 || 422 => MistralConnectionStatus.badRequest,
      504 => MistralConnectionStatus.timeout,
      _ => MistralConnectionStatus.serverError, // يشمل 500/502/503 وأي رمز غير متوقع آخر
    };
    return MistralHealthResult(
      status: status,
      messageAr: _messages[status]!,
      debugDetail: 'HTTP $code: ${_errorDetailOf(response.bodyBytes)}',
    );
  }

  /// يصنّف Exception عابرًا بلا الاعتماد على dart:io (SocketException) —
  /// استيرادها يكسر بناء الويب لهذا المشروع؛ فحص نصي دفاعي بدلًا منه (نفس
  /// النمط المستخدم سابقًا في ApiHealthService، محفوظ هنا الآن).
  MistralHealthResult classifyException(Object e) {
    if (e is TimeoutException) {
      return MistralHealthResult(status: MistralConnectionStatus.timeout, messageAr: _messages[MistralConnectionStatus.timeout]!);
    }
    final raw = e.toString();
    debugPrint('MistralApiClient: $raw'); // للـ Debug Log فقط — لا يُعرض للمستخدم أبدًا (القسم ١٥، ١٨)
    final status = _looksLikeNetworkFailure(raw) ? MistralConnectionStatus.networkError : MistralConnectionStatus.serverError;
    return MistralHealthResult(status: status, messageAr: _messages[status]!, debugDetail: raw);
  }

  bool _looksLikeNetworkFailure(String raw) {
    final lower = raw.toLowerCase();
    const markers = [
      'socketexception',
      'failed host lookup',
      'connection refused',
      'connection reset',
      'connection closed',
      'network is unreachable',
      'clientexception',
      'failed to fetch',
      'xmlhttprequest',
      'err_internet_disconnected',
      'err_name_not_resolved',
      'handshakeexception',
      'certificate',
    ];
    return markers.any(lower.contains);
  }

  String _errorDetailOf(Uint8List bodyBytes) {
    // شكل Mistral الموثَّق: {"object":"error","message":...,"type":...,"param":...,"code":...}
    // لكن بعض استجابات ٤٠١ الفعلية تصل بشكل أبسط {"message":...,"request_id":...} —
    // نتعامل دفاعيًا مع الحالتين، الرمز الرقمي وحده كافٍ للتصنيف أعلاه بأي حال.
    try {
      final decoded = jsonDecode(utf8.decode(bodyBytes));
      if (decoded is Map && decoded['message'] is String) return decoded['message'] as String;
    } catch (_) {}
    final text = utf8.decode(bodyBytes, allowMalformed: true);
    return text.length > 200 ? '${text.substring(0, 200)}…' : text;
  }
}
