import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// كل حالات صحة خدمة AI/OCR كما وردت في المواصفة حرفيًا.
enum ApiKeyStatus {
  noKey,
  valid,
  invalidKey,
  unauthorized,
  forbidden,
  networkError,
  timeout,
  serverError,
}

/// مجموعة عرض (لون/رمز/تسمية) لكل حالة — تُستخدم في شاشة الإعدادات (قسم ١١).
/// المواصفة عرّفت ٤ ألوان فقط لـ٨ حالات، فوسّعناها منطقيًا: 🔴 لأي حالة
/// المفتاح نفسه فيها هو المشكلة (غير صالح/غير مصرح/ممنوع)، 🟠 لأي مشكلة
/// بيئية عابرة (شبكة/مهلة/خادم) لا علاقة لها بصحة المفتاح، ⚪ لعدم الإعداد،
/// 🟢 فقط للنجاح الفعلي المؤكَّد من المزود.
enum ApiHealthIndicator { connected, attentionNeeded, invalid, inactive }

extension ApiKeyStatusPresentation on ApiKeyStatus {
  ApiHealthIndicator get indicator => switch (this) {
        ApiKeyStatus.valid => ApiHealthIndicator.connected,
        ApiKeyStatus.noKey => ApiHealthIndicator.inactive,
        ApiKeyStatus.invalidKey ||
        ApiKeyStatus.unauthorized ||
        ApiKeyStatus.forbidden =>
          ApiHealthIndicator.invalid,
        ApiKeyStatus.networkError ||
        ApiKeyStatus.timeout ||
        ApiKeyStatus.serverError =>
          ApiHealthIndicator.attentionNeeded,
      };

  String get emoji => switch (indicator) {
        ApiHealthIndicator.connected => '🟢',
        ApiHealthIndicator.attentionNeeded => '🟠',
        ApiHealthIndicator.invalid => '🔴',
        ApiHealthIndicator.inactive => '⚪',
      };

  String get labelAr => switch (indicator) {
        ApiHealthIndicator.connected => 'متصل',
        ApiHealthIndicator.attentionNeeded => 'يحتاج إعداد',
        ApiHealthIndicator.invalid => 'غير صالح',
        ApiHealthIndicator.inactive => 'غير مفعّل',
      };

  /// هل يمكن اعتماد هذه الحالة لبناء محرك استخراج فعلي (وليس فقط للعرض)؟
  bool get usableForExtraction => this == ApiKeyStatus.valid;
}

/// نتيجة فحص واحدة: الحالة + رسالة عربية جاهزة للعرض مباشرة + تفاصيل تقنية
/// (لأغراض Debug Log فقط — قسم ١٥: لا تُعرض هذه للمستخدم أبدًا).
class ApiHealthResult {
  final ApiKeyStatus status;
  final String messageAr;
  final String? debugDetail;

  const ApiHealthResult({
    required this.status,
    required this.messageAr,
    this.debugDetail,
  });
}

/// يتحقق من صحة مفتاح AI عبر نداء فعلي خفيف لمزوّد الخدمة (GET /v1/models —
/// endpoint توثيقي رسمي بلا أي تكلفة توليد نص)، بدل الاكتفاء بفحص شكل
/// المفتاح (Prefix) كما حذّرت المواصفة صراحةً. يُستخدم أيضًا لتصنيف أي فشل
/// حقيقي أثناء الاستخراج (AiVisionOcrEngine) بنفس منظومة الحالات، حتى تكون
/// الرسالة العربية متسقة في كل مكان بالتطبيق.
class ApiHealthService {
  const ApiHealthService();

  static const _defaultMessagesEndpointUrl = 'https://api.anthropic.com/v1/messages';
  static const _anthropicVersion = '2023-06-01';
  static const _checkTimeout = Duration(seconds: 15);

  static const Map<ApiKeyStatus, String> _messages = {
    ApiKeyStatus.noKey: 'لم يتم إعداد AI. جميع الميزات المحلية متاحة.',
    ApiKeyStatus.valid: 'المفتاح صالح ومتصل بخدمة AI بنجاح.',
    ApiKeyStatus.invalidKey:
        'مفتاح AI غير صالح. يمكنك الاستمرار باستخدام الوضع المحلي.',
    ApiKeyStatus.unauthorized:
        'تعذّر التحقق من صلاحية المفتاح مع الخادم المُعد. يمكنك الاستمرار باستخدام الوضع المحلي.',
    ApiKeyStatus.forbidden:
        'مفتاح AI لا يملك صلاحية الوصول لهذه الخدمة حاليًا. راجع إعدادات حسابك، أو استمر بالوضع المحلي.',
    ApiKeyStatus.networkError:
        'تعذّر الاتصال بخدمة AI. تم استخدام الوضع المحلي.',
    ApiKeyStatus.timeout:
        'انتهت مهلة الاتصال بخدمة AI. تحقق من الإنترنت وأعد المحاولة، أو استمر بالوضع المحلي.',
    ApiKeyStatus.serverError:
        'خدمة AI غير متاحة حاليًا (مشكلة من جهة المزوّد). تم استخدام الوضع المحلي.',
  };

  String messageFor(ApiKeyStatus status) => _messages[status]!;

  /// اختبار فعلي للمفتاح — يُستدعى من زر [اختبار المفتاح] في الإعدادات، وعند
  /// كل حفظ لمفتاح جديد.
  Future<ApiHealthResult> testApiKey(
    String apiKey, {
    String messagesEndpointUrl = _defaultMessagesEndpointUrl,
  }) async {
    final trimmed = apiKey.trim();
    if (trimmed.isEmpty) {
      return ApiHealthResult(status: ApiKeyStatus.noKey, messageAr: _messages[ApiKeyStatus.noKey]!);
    }

    try {
      final response = await http.get(
        _healthCheckUri(messagesEndpointUrl),
        headers: {
          'x-api-key': trimmed,
          'anthropic-version': _anthropicVersion,
        },
      ).timeout(_checkTimeout);

      return classifyHttpResponse(response);
    } on TimeoutException {
      return ApiHealthResult(status: ApiKeyStatus.timeout, messageAr: _messages[ApiKeyStatus.timeout]!);
    } catch (e) {
      return classifyException(e);
    }
  }

  /// يحوّل رابط .../v1/messages المُعطى (المُخزَّن في الإعدادات لبناء طلبات
  /// الاستخراج) إلى رابط .../v1/models المكافئ لفحص الصحة. لو كان الرابط
  /// بشكل مختلف (proxy مخصَّص مستقبلًا)، يضيف "models" احتياطيًا بدل الفشل.
  Uri _healthCheckUri(String messagesEndpointUrl) {
    final parsed = Uri.parse(messagesEndpointUrl);
    final segments = List<String>.from(parsed.pathSegments);
    if (segments.isNotEmpty && segments.last == 'messages') {
      segments[segments.length - 1] = 'models';
    } else if (!segments.contains('models')) {
      segments.add('models');
    }
    return parsed.replace(pathSegments: segments, queryParameters: {'limit': '1'});
  }

  /// يُستخدم من [testApiKey] ومباشرة من AiVisionOcrEngine عند فشل نداء
  /// استخراج فعلي، حتى تُصنَّف كل استجابات المزوّد بنفس المنطق.
  ApiHealthResult classifyHttpResponse(http.Response response) {
    final code = response.statusCode;
    if (code == 200) {
      return ApiHealthResult(status: ApiKeyStatus.valid, messageAr: _messages[ApiKeyStatus.valid]!);
    }
    if (code == 401) {
      // ٤٠١ من Anthropic مباشرة يكون دائمًا بشكل authentication_error موثَّق.
      // أي شكل آخر (نادر، غالبًا عبر Proxy مخصَّص مستقبلًا) يُصنَّف
      // UNAUTHORIZED بدل افتراض أنه بالضرورة "مفتاح غير صالح".
      final isDocumentedAuthError = _errorTypeOf(response.bodyBytes) == 'authentication_error';
      final status = isDocumentedAuthError ? ApiKeyStatus.invalidKey : ApiKeyStatus.unauthorized;
      return ApiHealthResult(
        status: status,
        messageAr: _messages[status]!,
        debugDetail: 'HTTP 401: ${_safeBodyPreview(response.bodyBytes)}',
      );
    }
    if (code == 403) {
      return ApiHealthResult(
        status: ApiKeyStatus.forbidden,
        messageAr: _messages[ApiKeyStatus.forbidden]!,
        debugDetail: 'HTTP 403: ${_safeBodyPreview(response.bodyBytes)}',
      );
    }
    if (code == 504) {
      return ApiHealthResult(status: ApiKeyStatus.timeout, messageAr: _messages[ApiKeyStatus.timeout]!);
    }
    // أي رمز آخر غير متوقع (٤xx نادر كـ٤٠٠/٤٠٤/٤٢٩ أو ٥xx) يُعامَل كخطأ من
    // جهة الخدمة وليس تخمينًا بشأن المفتاح تحديدًا — الأصدق هنا بلا افتراض.
    return ApiHealthResult(
      status: ApiKeyStatus.serverError,
      messageAr: _messages[ApiKeyStatus.serverError]!,
      debugDetail: 'HTTP $code: ${_safeBodyPreview(response.bodyBytes)}',
    );
  }

  /// يصنّف أي Exception عابر (مهلة/شبكة/غير متوقع) بلا الاعتماد على dart:io
  /// (SocketException) — استيرادها هنا يكسر بناء الويب لهذا المشروع. نعتمد
  /// بدل ذلك فحصًا نصيًا دفاعيًا على رسالة الخطأ، وهو ما يعمل على المنصتين
  /// معًا (SocketException على أندرويد، فشل fetch/XHR على الويب) بلا خطر.
  ApiHealthResult classifyException(Object e) {
    if (e is TimeoutException) {
      return ApiHealthResult(status: ApiKeyStatus.timeout, messageAr: _messages[ApiKeyStatus.timeout]!);
    }
    final raw = e.toString();
    debugPrint('ApiHealthService: $raw'); // تفصيل فني للـ Debug Log فقط — لا يُعرض للمستخدم أبدًا (قسم ١٥)
    if (_looksLikeNetworkFailure(raw)) {
      return ApiHealthResult(status: ApiKeyStatus.networkError, messageAr: _messages[ApiKeyStatus.networkError]!, debugDetail: raw);
    }
    return ApiHealthResult(status: ApiKeyStatus.serverError, messageAr: _messages[ApiKeyStatus.serverError]!, debugDetail: raw);
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

  String? _errorTypeOf(Uint8List bodyBytes) {
    try {
      final decoded = jsonDecode(utf8.decode(bodyBytes));
      if (decoded is Map && decoded['error'] is Map) {
        return (decoded['error'] as Map)['type'] as String?;
      }
    } catch (_) {
      // جسم غير JSON (مثلاً من Proxy/CDN وسيط) — نتجاهله بصمت، التصنيف
      // بالرمز الرقمي (401/403) يبقى كافيًا بمفرده هنا.
    }
    return null;
  }

  String _safeBodyPreview(Uint8List bodyBytes) {
    try {
      final text = utf8.decode(bodyBytes);
      return text.length > 200 ? '${text.substring(0, 200)}…' : text;
    } catch (_) {
      return '(binary body)';
    }
  }
}
