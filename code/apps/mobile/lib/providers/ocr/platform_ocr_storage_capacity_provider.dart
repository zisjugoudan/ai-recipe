import 'dart:io';

import 'package:flutter/services.dart';

class PlatformOcrStorageCapacityProvider {
  PlatformOcrStorageCapacityProvider({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('ai_recipe/local_ocr');

  final MethodChannel _channel;

  Future<int?> availableBytes(Directory directory) async {
    try {
      final result = await _channel.invokeMethod<Object?>(
        'getAvailableStorageBytes',
        <String, Object?>{'directory': directory.absolute.path},
      );
      return result is int && result >= 0 ? result : null;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}
