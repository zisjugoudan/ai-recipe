import 'dart:io';

import 'package:ai_recipe/providers/ocr/platform_ocr_storage_capacity_provider.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('ai_recipe/local_ocr_storage_test');
  late Directory root;
  late PlatformOcrStorageCapacityProvider provider;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('ai-recipe-ocr-storage-');
    provider = PlatformOcrStorageCapacityProvider(channel: channel);
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('requests available bytes for the absolute model directory', () async {
    late MethodCall capturedCall;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          capturedCall = call;
          return 1024;
        });

    final availableBytes = await provider.availableBytes(root);

    expect(availableBytes, 1024);
    expect(capturedCall.method, 'getAvailableStorageBytes');
    expect(
      Map<Object?, Object?>.from(
        capturedCall.arguments as Map<Object?, Object?>,
      ),
      <Object?, Object?>{'directory': root.absolute.path},
    );
  });

  test('returns unknown when the platform implementation is missing', () async {
    expect(await provider.availableBytes(root), isNull);
  });

  test('returns unknown for platform errors without leaking details', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          throw PlatformException(
            code: 'storage_unavailable',
            message: 'private platform detail',
          );
        });

    expect(await provider.availableBytes(root), isNull);
  });

  test('returns unknown for invalid or negative responses', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => -1);
    expect(await provider.availableBytes(root), isNull);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => '1024');
    expect(await provider.availableBytes(root), isNull);
  });
}
