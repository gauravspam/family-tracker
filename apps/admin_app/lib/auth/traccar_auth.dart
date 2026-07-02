import 'package:dio/dio.dart';

class TraccarAuthResult {
  final String jSessionId;
  final int userId;
  final String email;
  final bool administrator;

  const TraccarAuthResult({
    required this.jSessionId,
    required this.userId,
    required this.email,
    required this.administrator,
  });
}

class TraccarAuth {
  final Dio _dio;

  TraccarAuth(String baseUrl)
      : _dio = Dio(BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        ));

  Future<TraccarAuthResult> login(String email, String password) async {
    final response = await _dio.post(
      '/api/session',
      data: 'email=$email&password=$password',
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        followRedirects: false,
        validateStatus: (s) => s != null && s < 500,
      ),
    );

    if (response.statusCode != 200) {
      final message = response.data?.toString() ?? '';
      throw Exception(_friendlyAuthError(response.statusCode, message));
    }

    final data = response.data as Map<String, dynamic>;

    final setCookieHeaders = response.headers.map['set-cookie'] ?? [];
    final jSessionId = _extractJSessionId(setCookieHeaders);
    if (jSessionId == null) {
      throw Exception('No JSESSIONID returned by Traccar');
    }

    if (data['administrator'] != true) {
      throw Exception('This account is not an administrator');
    }

    return TraccarAuthResult(
      jSessionId: jSessionId,
      userId: data['id'] as int,
      email: data['email'] as String,
      administrator: true,
    );
  }

  String? _extractJSessionId(List<String> cookies) {
    for (final c in cookies) {
      final parts = c.split(';');
      for (final p in parts) {
        final trimmed = p.trim();
        if (trimmed.startsWith('JSESSIONID=')) {
          return trimmed.substring('JSESSIONID='.length);
        }
      }
    }
    return null;
  }

  String _friendlyAuthError(int? code, String body) {
    if (code == 401) return 'Wrong email or password';
    if (code == 403) return 'Access denied';
    return 'Login failed (HTTP $code): $body';
  }
}
