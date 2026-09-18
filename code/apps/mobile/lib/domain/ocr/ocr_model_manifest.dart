export 'ocr_model_runtime_config.dart';

import 'ocr_model_runtime_config.dart';

enum OcrRuntimePlatform { android, ios }

enum OcrModelInstallState {
  notInstalled,
  downloading,
  verifying,
  installed,
  failed,
}

class OcrModelFile {
  OcrModelFile({
    required String role,
    required String path,
    required String downloadUrl,
    required String sha256,
    required this.sizeBytes,
  }) : role = _requireText(role, 'role'),
       path = _requireSafeRelativePath(path),
       downloadUrl = _requireHttpsUrl(downloadUrl, 'downloadUrl'),
       sha256 = _requireSha256(sha256) {
    if (sizeBytes <= 0) {
      throw ArgumentError.value(
        sizeBytes,
        'sizeBytes',
        'must be greater than zero',
      );
    }
  }

  final String role;
  final String path;
  final String downloadUrl;
  final String sha256;
  final int sizeBytes;

  factory OcrModelFile.fromJson(Map<String, Object?> json) {
    _requireOnlyKeys(json, const <String>{
      'role',
      'path',
      'downloadUrl',
      'sha256',
      'sizeBytes',
    });
    return OcrModelFile(
      role: _requireString(json, 'role'),
      path: _requireString(json, 'path'),
      downloadUrl: _requireString(json, 'downloadUrl'),
      sha256: _requireString(json, 'sha256'),
      sizeBytes: _requireInt(json, 'sizeBytes'),
    );
  }

  Map<String, Object> toJson() => <String, Object>{
    'role': role,
    'path': path,
    'downloadUrl': downloadUrl,
    'sha256': sha256,
    'sizeBytes': sizeBytes,
  };
}

class OcrModelManifest {
  OcrModelManifest({
    required this.schemaVersion,
    required String packageId,
    required String version,
    required String engine,
    required Iterable<OcrRuntimePlatform> platforms,
    required Iterable<String> languages,
    required String minAppVersion,
    required String license,
    required Iterable<OcrModelFile> files,
    this.runtimeConfig,
  }) : packageId = _requirePackageId(packageId),
       version = _requireSemanticVersion(version, 'version'),
       engine = _requireEngine(engine),
       platforms = _requirePlatforms(platforms),
       languages = List<String>.unmodifiable(
         languages.map((language) => _requireText(language, 'language')),
       ),
       minAppVersion = _requireSemanticVersion(minAppVersion, 'minAppVersion'),
       license = _requireText(license, 'license'),
       files = List<OcrModelFile>.unmodifiable(files) {
    if (schemaVersion != 1 && schemaVersion != 2) {
      throw ArgumentError.value(
        schemaVersion,
        'schemaVersion',
        'must be 1 or 2',
      );
    }
    if (schemaVersion == 1 && runtimeConfig != null) {
      throw ArgumentError('schemaVersion 1 must not define runtimeConfig');
    }
    if (schemaVersion == 2 && runtimeConfig == null) {
      throw ArgumentError('schemaVersion 2 requires runtimeConfig');
    }
    if (this.platforms.isEmpty) {
      throw ArgumentError('platforms must not be empty');
    }
    if (this.languages.isEmpty) {
      throw ArgumentError('languages must not be empty');
    }
    if (this.files.isEmpty) {
      throw ArgumentError('files must not be empty');
    }
    if (this.languages.toSet().length != this.languages.length) {
      throw ArgumentError('languages must not contain duplicates');
    }
    final roles = this.files.map((file) => file.role).toSet();
    final paths = this.files.map((file) => file.path).toSet();
    if (roles.length != this.files.length) {
      throw ArgumentError('file roles must be unique');
    }
    if (paths.length != this.files.length) {
      throw ArgumentError('file paths must be unique');
    }
    final runtime = runtimeConfig;
    if (runtime != null) {
      final missingRoles = runtime.requiredFileRoles.difference(roles);
      if (missingRoles.isNotEmpty) {
        throw ArgumentError(
          'runtimeConfig references missing file roles: '
          '${missingRoles.toList()..sort()}',
        );
      }
      for (final role in <String>{
        runtime.detector.modelRole,
        runtime.recognizer.modelRole,
      }) {
        final file = this.files.singleWhere((entry) => entry.role == role);
        if (!file.path.toLowerCase().endsWith('.onnx')) {
          throw ArgumentError(
            'OCR model role $role must reference an ONNX file',
          );
        }
      }
      final dictionary = this.files.singleWhere(
        (entry) => entry.role == runtime.recognizer.dictionaryRole,
      );
      if (!dictionary.path.toLowerCase().endsWith('.txt')) {
        throw ArgumentError('OCR dictionary role must reference a TXT file');
      }
    }
  }

  final int schemaVersion;
  final String packageId;
  final String version;
  final String engine;
  final Set<OcrRuntimePlatform> platforms;
  final List<String> languages;
  final String minAppVersion;
  final String license;
  final List<OcrModelFile> files;
  final PaddleOcrRuntimeConfig? runtimeConfig;

  int get totalSizeBytes =>
      files.fold<int>(0, (total, file) => total + file.sizeBytes);

  factory OcrModelManifest.fromJson(Map<String, Object?> json) {
    _requireOnlyKeys(json, const <String>{
      'schemaVersion',
      'packageId',
      'version',
      'engine',
      'platforms',
      'languages',
      'minAppVersion',
      'license',
      'files',
      'runtimeConfig',
    });
    return OcrModelManifest(
      schemaVersion: _requireInt(json, 'schemaVersion'),
      packageId: _requireString(json, 'packageId'),
      version: _requireString(json, 'version'),
      engine: _requireString(json, 'engine'),
      platforms: _requireStringList(json, 'platforms').map((value) {
        return switch (value) {
          'android' => OcrRuntimePlatform.android,
          'ios' => OcrRuntimePlatform.ios,
          _ => throw FormatException('Unsupported OCR platform: $value'),
        };
      }),
      languages: _requireStringList(json, 'languages'),
      minAppVersion: _requireString(json, 'minAppVersion'),
      license: _requireString(json, 'license'),
      files: _requireObjectList(json, 'files').map(OcrModelFile.fromJson),
      runtimeConfig: switch (json['runtimeConfig']) {
        null => null,
        final Map value => PaddleOcrRuntimeConfig.fromJson(
          Map<String, Object?>.from(value),
        ),
        _ => throw const FormatException('runtimeConfig must be an object'),
      },
    );
  }

  Map<String, Object> toJson() => <String, Object>{
    'schemaVersion': schemaVersion,
    'packageId': packageId,
    'version': version,
    'engine': engine,
    'platforms': platforms.map((platform) => platform.name).toList()..sort(),
    'languages': languages,
    'minAppVersion': minAppVersion,
    'license': license,
    'files': files.map((file) => file.toJson()).toList(),
    if (runtimeConfig case final runtime?) 'runtimeConfig': runtime.toJson(),
  };
}

class OcrModelPackageStatus {
  OcrModelPackageStatus({
    required String packageId,
    required this.state,
    required this.progress,
    String? installedVersion,
    String? failureCode,
  }) : packageId = _requirePackageId(packageId),
       installedVersion = installedVersion == null
           ? null
           : _requireSemanticVersion(installedVersion, 'installedVersion'),
       failureCode = _optionalText(failureCode) {
    if (progress < 0 || progress > 1) {
      throw ArgumentError.value(progress, 'progress', 'must be from 0 to 1');
    }
    if (state == OcrModelInstallState.installed &&
        this.installedVersion == null) {
      throw ArgumentError('installedVersion is required when installed');
    }
    if (state == OcrModelInstallState.failed && this.failureCode == null) {
      throw ArgumentError('failureCode is required when installation failed');
    }
  }

  final String packageId;
  final OcrModelInstallState state;
  final double progress;
  final String? installedVersion;
  final String? failureCode;
}

final RegExp _semanticVersion = RegExp(
  r'^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)'
  r'(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$',
);
final RegExp _packageId = RegExp(r'^[a-z0-9]+(?:[._-][a-z0-9]+)*$');
final RegExp _sha256 = RegExp(r'^[a-fA-F0-9]{64}$');

String _requireText(String value, String name) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(value, name, '$name must not be blank');
  }
  return normalized;
}

String? _optionalText(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

String _requirePackageId(String value) {
  final normalized = _requireText(value, 'packageId');
  if (!_packageId.hasMatch(normalized)) {
    throw ArgumentError.value(value, 'packageId', 'has an invalid format');
  }
  return normalized;
}

String _requireSemanticVersion(String value, String name) {
  final normalized = _requireText(value, name);
  if (!_semanticVersion.hasMatch(normalized)) {
    throw ArgumentError.value(value, name, 'must be a semantic version');
  }
  return normalized;
}

Set<OcrRuntimePlatform> _requirePlatforms(Iterable<OcrRuntimePlatform> values) {
  final list = values.toList(growable: false);
  if (list.toSet().length != list.length) {
    throw ArgumentError('platforms must not contain duplicates');
  }
  return Set<OcrRuntimePlatform>.unmodifiable(list);
}

String _requireEngine(String value) {
  final normalized = _requireText(value, 'engine');
  if (normalized != 'onnxruntime') {
    throw ArgumentError.value(value, 'engine', 'must be onnxruntime');
  }
  return normalized;
}

String _requireHttpsUrl(String value, String name) {
  final normalized = _requireText(value, name);
  final uri = Uri.tryParse(normalized);
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
    throw ArgumentError.value(value, name, 'must be an HTTPS URL');
  }
  return uri.toString();
}

String _requireSha256(String value) {
  final normalized = _requireText(value, 'sha256');
  if (!_sha256.hasMatch(normalized)) {
    throw ArgumentError.value(value, 'sha256', 'must be 64 hexadecimal chars');
  }
  return normalized.toLowerCase();
}

String _requireSafeRelativePath(String value) {
  final normalized = _requireText(value, 'path');
  final segments = normalized.split('/');
  if (normalized.startsWith('/') ||
      normalized.contains('\\') ||
      segments.any((segment) => segment.isEmpty || segment == '..')) {
    throw ArgumentError.value(value, 'path', 'must be a safe relative path');
  }
  return normalized;
}

void _requireOnlyKeys(Map<String, Object?> json, Set<String> allowed) {
  final unknown = json.keys.where((key) => !allowed.contains(key)).toList();
  if (unknown.isNotEmpty) {
    throw FormatException('Unknown manifest fields: ${unknown.join(', ')}');
  }
}

String _requireString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String) {
    throw FormatException('$key must be a string');
  }
  return value;
}

int _requireInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! int) {
    throw FormatException('$key must be an integer');
  }
  return value;
}

List<String> _requireStringList(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! List || value.any((item) => item is! String)) {
    throw FormatException('$key must be a string array');
  }
  return value.cast<String>();
}

List<Map<String, Object?>> _requireObjectList(
  Map<String, Object?> json,
  String key,
) {
  final value = json[key];
  if (value is! List || value.any((item) => item is! Map)) {
    throw FormatException('$key must be an object array');
  }
  return value.map((item) => Map<String, Object?>.from(item as Map)).toList();
}
