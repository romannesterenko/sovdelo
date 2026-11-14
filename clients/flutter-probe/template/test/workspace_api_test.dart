import 'package:flutter_test/flutter_test.dart';
import 'package:sovdelo_probe/workspace_api.dart';

class MemoryVault implements TokenVault {
  String? value;
  bool failWrite = false;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String token) async {
    if (failWrite) throw StateError('Locked keyring');
    value = token;
  }
  @override
  Future<void> delete() async { value = null; }
}

void main() {
  test('Вход запрашивает write-токен и сохраняет после проверки профиля', () async {
    final vault = MemoryVault();
    final calls = <String>[];
    final api = WorkspaceApi(transport: (method, path, token, body) async {
      calls.add('$method $path');
      if (path == 'auth/token') {
        expect(token, isNull);
        final input = body!;
        expect(input['access'], 'write');
        expect(input['email'], 'user@example.com');
        expect(input['password'], 'pass');
        return {'data': {'token': 'fake-device-token'}};
      }
      expect(token, 'fake-device-token');
      expect(vault.value, isNull);
      return {'data': {'id': 7, 'email': 'user@example.com'}};
    });
    expect(await AccountSession(api, vault).login(' user@example.com ', 'pass'), 'fake-device-token');
    expect(vault.value, 'fake-device-token');
    expect(calls, ['POST auth/token', 'GET me']);
  });

  test('Неверный пароль не создаёт сохранённую сессию', () async {
    final vault = MemoryVault();
    final api = WorkspaceApi(transport: (method, path, token, body) async {
      throw const ApiFailure(422, 'Invalid credentials');
    });
    await expectLater(AccountSession(api, vault).login('a@b.ru', 'wrong'), throwsA(isA<ApiFailure>()));
    expect(vault.value, isNull);
  });

  test('Сбой Keyring отзывает только что выданный токен', () async {
    final vault = MemoryVault()..failWrite = true;
    var revoked = false;
    final api = WorkspaceApi(transport: (method, path, token, body) async {
      if (method == 'POST') return {'data': {'token': 'temporary'}};
      if (method == 'DELETE') { revoked = true; return {'data': {'revoked': true}}; }
      return {'data': {'id': 1, 'email': 'a@b.ru'}};
    });
    await expectLater(AccountSession(api, vault).login('a@b.ru', 'pass'), throwsStateError);
    expect(revoked, isTrue);
    expect(vault.value, isNull);
  });

  test('Ошибка проверки профиля не оставляет токен в хранилище', () async {
    final vault = MemoryVault();
    var revoked = false;
    final api = WorkspaceApi(transport: (method, path, token, body) async {
      if (method == 'POST') return {'data': {'token': 'temporary'}};
      if (method == 'DELETE') { revoked = true; return {'data': {'revoked': true}}; }
      throw const ApiFailure(401, 'Revoked');
    });
    await expectLater(AccountSession(api, vault).login('a@b.ru', 'pass'), throwsA(isA<ApiFailure>()));
    expect(vault.value, isNull);
    expect(revoked, isTrue);
  });

  test('Выход без сети удаляет локальный токен и сообщает о неподтверждённом отзыве', () async {
    final vault = MemoryVault()..value = 'old-token';
    final api = WorkspaceApi(transport: (method, path, token, body) async {
      throw const ApiFailure(0, 'Offline');
    });
    expect(await AccountSession(api, vault).logout('old-token'), isFalse);
    expect(vault.value, isNull);
  });

  test('Уже отозванный токен тоже позволяет завершить выход', () async {
    final vault = MemoryVault()..value = 'old-token';
    final api = WorkspaceApi(transport: (method, path, token, body) async {
      throw const ApiFailure(401, 'Revoked');
    });
    expect(await AccountSession(api, vault).logout('old-token'), isTrue);
    expect(vault.value, isNull);
  });

  test('Чтение страниц передаёт Bearer и не теряет номер страницы', () async {
    final api = WorkspaceApi(transport: (method, path, token, body) async {
      expect(method, 'GET');
      expect(path, 'tasks?state=active&per_page=50&page=2');
      expect(token, 'read-token');
      expect(body, isNull);
      return {'data': [{'id': 51, 'title': 'Task'}], 'meta': {'page': 2, 'last_page': 2, 'total': 51}};
    });
    final result = await api.page('read-token', 'tasks', 2);
    expect((result['data'] as List).single['id'], 51);
    await expectLater(api.page('read-token', '../auth/token', 1), throwsArgumentError);
  });
}
