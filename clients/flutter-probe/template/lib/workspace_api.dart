import 'dart:async';
import 'dart:convert';
import 'dart:io';

typedef ApiTransport = Future<Map<String, dynamic>> Function(
    String method, String path, String? token, Map<String, dynamic>? body);

class ApiFailure implements Exception {
  final int status;
  final String message;
  const ApiFailure(this.status, this.message);
  @override
  String toString() => message;
}

class WorkspaceApi {
  final ApiTransport _transport;
  WorkspaceApi({ApiTransport? transport}) : _transport = transport ?? _http;
  static final origin = Uri.parse('https://xn--b1aedylep.xn--p1ai/api/v1/');

  static Future<Map<String, dynamic>> _http(String method, String path,
      String? token, Map<String, dynamic>? body) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      return await (() async {
        final request = await client.openUrl(method, origin.resolve(path));
        request.followRedirects = false;
        request.headers.set(HttpHeaders.acceptHeader, 'application/json');
        if (token != null) request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
        if (body != null) {
          request.headers.contentType = ContentType.json;
          request.write(jsonEncode(body));
        }
        final response = await request.close();
        if (response.statusCode >= 300 && response.statusCode < 400) {
          throw const ApiFailure(0, 'Сервер перенаправил запрос. Проверь адрес и HTTPS на сайте.');
        }
        final bytes = <int>[];
        await for (final chunk in response) {
          if (bytes.length + chunk.length > 2 * 1024 * 1024) {
            throw const ApiFailure(0, 'Ответ сервера слишком большой.');
          }
          bytes.addAll(chunk);
        }
        Map<String, dynamic>? document;
        try {
          final decoded = jsonDecode(utf8.decode(bytes));
          if (decoded is Map<String, dynamic>) document = decoded;
        } catch (_) {
          // Never display raw bodies: proxy responses can contain private data.
        }
        final status = response.statusCode;
        if (status == 401) throw const ApiFailure(401, 'Сессия истекла или токен отозван. Войди снова.');
        if (status == 429) throw const ApiFailure(429, 'Слишком много запросов. Подожди и повтори.');
        if (status == 422 && path == 'auth/token') {
          throw const ApiFailure(422, 'Не удалось войти. Проверь email и пароль; также проверь лимит устройств в профиле сайта.');
        }
        if (status < 200 || status >= 300) {
          throw ApiFailure(status, 'Сервер вернул ошибку $status. Повтори позже.');
        }
        if (document == null || !document.containsKey('data')) {
          throw const ApiFailure(0, 'Неожиданный формат ответа API.');
        }
        return document;
      })().timeout(const Duration(seconds: 25));
    } on ApiFailure {
      rethrow;
    } on TimeoutException {
      throw const ApiFailure(0, 'Сервер не ответил вовремя. Проверь соединение.');
    } on HandshakeException {
      throw const ApiFailure(0, 'Не удалось проверить HTTPS-соединение с сервером.');
    } on SocketException {
      throw const ApiFailure(0, 'Нет соединения с сервером. Локальные задачи доступны отдельно.');
    } on HttpException {
      throw const ApiFailure(0, 'Соединение прервалось. Повтори запрос.');
    } finally {
      client.close(force: true);
    }
  }

  Future<String> login(String email, String password) async {
    final response = await _transport('POST', 'auth/token', null, {
      'email': email.trim(), 'password': password,
      'device_name': 'СовДело · ${Platform.isAndroid ? 'Android' : 'Desktop'}',
      'access': 'read',
    });
    final data = response['data'];
    if (data is! Map || data['token'] is! String || (data['token'] as String).isEmpty) {
      throw const ApiFailure(0, 'Сервер не выдал токен устройства.');
    }
    return data['token'] as String;
  }

  Future<Map<String, dynamic>> me(String token) async {
    final data = (await _transport('GET', 'me', token, null))['data'];
    if (data is! Map || data['id'] is! int || data['email'] is! String) {
      throw const ApiFailure(0, 'Некорректный профиль аккаунта.');
    }
    return Map<String, dynamic>.from(data);
  }

  Future<Map<String, dynamic>> page(String token, String resource, int number) async {
    if (!['tasks', 'projects'].contains(resource) || number < 1) {
      throw ArgumentError('Некорректная страница');
    }
    final response = await _transport('GET', '$resource?state=active&per_page=50&page=$number', token, null);
    if (response['data'] is! List || response['meta'] is! Map) {
      throw const ApiFailure(0, 'Некорректный список API.');
    }
    return response;
  }

  Future<void> revoke(String token) async {
    await _transport('DELETE', 'auth/token', token, null);
  }
}

abstract class TokenVault {
  Future<String?> read();
  Future<void> write(String token);
  Future<void> delete();
}

class AccountSession {
  final WorkspaceApi api;
  final TokenVault vault;
  AccountSession(this.api, this.vault);

  Future<String> login(String email, String password) async {
    final token = await api.login(email, password);
    try {
      await api.me(token);
      await vault.write(token);
      if (await vault.read() != token) throw StateError('Token verification failed');
      return token;
    } catch (_) {
      try { await api.revoke(token); } catch (_) { /* Can be revoked in the site's device list. */ }
      try { await vault.delete(); } catch (_) { /* No plaintext fallback. */ }
      rethrow;
    }
  }

  /// Local logout completes even when the server cannot be reached.
  Future<bool> logout(String token) async {
    var revoked = false;
    try {
      await api.revoke(token);
      revoked = true;
    } on ApiFailure catch (e) {
      revoked = e.status == 401;
    } catch (_) {
      // Inform the user that remote revocation was not confirmed.
    }
    await vault.delete();
    return revoked;
  }
}
