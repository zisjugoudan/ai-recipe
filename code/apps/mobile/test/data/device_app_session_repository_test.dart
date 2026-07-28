import 'dart:convert';

import 'package:ai_recipe/data/device_app_session_repository.dart';
import 'package:ai_recipe/domain/access/app_session.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_app_access_dependencies.dart';

void main() {
  late MemoryAppSessionKeyValueStore store;
  late DeviceAppSessionRepository repository;

  setUp(() {
    store = MemoryAppSessionKeyValueStore();
    repository = DeviceAppSessionRepository(store: store);
  });

  test('missing metadata loads guest session', () async {
    expect(await repository.load(), const AppSession.guest());
  });

  test('guest session round trips', () async {
    await repository.save(const AppSession.guest());

    expect(await repository.load(), const AppSession.guest());
    expect(
      jsonDecode(store.values[DeviceAppSessionRepository.storageKey]!),
      const {'schemaVersion': 1, 'kind': 'guest'},
    );
  });

  test('authenticated metadata round trips without credentials', () async {
    final session = AppSession.authenticated(
      userId: 'user-42',
      displayName: '测试用户',
      signedInAt: DateTime.utc(2026, 7, 28, 12),
    );

    await repository.save(session);
    final raw = store.values[DeviceAppSessionRepository.storageKey]!;
    final normalizedRaw = raw.toLowerCase();

    expect(await repository.load(), session);
    expect(normalizedRaw, isNot(contains('token')));
    expect(normalizedRaw, isNot(contains('apikey')));
    expect(normalizedRaw, isNot(contains('cookie')));
    expect(normalizedRaw, isNot(contains('authorization')));
  });

  test('rejects malformed json', () async {
    store.values[DeviceAppSessionRepository.storageKey] = '{broken';

    await expectLater(repository.load(), throwsFormatException);
  });

  test('rejects unknown schema version', () async {
    _writeJson(store, {'schemaVersion': 2, 'kind': 'guest'});

    await expectLater(repository.load(), throwsFormatException);
  });

  test('rejects authenticated session without userId', () async {
    _writeJson(store, {
      'schemaVersion': 1,
      'kind': 'authenticated',
      'signedInAt': '2026-07-28T12:00:00.000Z',
    });

    await expectLater(repository.load(), throwsFormatException);
  });

  test('rejects invalid signedInAt', () async {
    _writeJson(store, {
      'schemaVersion': 1,
      'kind': 'authenticated',
      'userId': 'user-1',
      'signedInAt': 'not-a-date',
    });

    await expectLater(repository.load(), throwsFormatException);
  });

  test('rejects unknown or credential-like fields', () async {
    _writeJson(store, {
      'schemaVersion': 1,
      'kind': 'authenticated',
      'userId': 'user-1',
      'signedInAt': '2026-07-28T12:00:00.000Z',
      'accessToken': 'must-not-be-here',
    });

    await expectLater(repository.load(), throwsFormatException);
  });

  test('rejects identity fields on guest metadata', () async {
    _writeJson(store, {
      'schemaVersion': 1,
      'kind': 'guest',
      'userId': 'unexpected',
    });

    await expectLater(repository.load(), throwsFormatException);
  });
}

void _writeJson(
  MemoryAppSessionKeyValueStore store,
  Map<String, Object?> json,
) {
  store.values[DeviceAppSessionRepository.storageKey] = jsonEncode(json);
}
