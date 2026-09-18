enum PaddleOcrColorOrder { bgr, rgb }

class OcrTensorBinding {
  OcrTensorBinding({String? inputName, String? outputName})
    : inputName = _optionalText(inputName),
      outputName = _optionalText(outputName);

  final String? inputName;
  final String? outputName;

  factory OcrTensorBinding.fromJson(Map<String, Object?> json) {
    _requireOnlyKeys(json, const <String>{'inputName', 'outputName'});
    return OcrTensorBinding(
      inputName: _optionalString(json, 'inputName'),
      outputName: _optionalString(json, 'outputName'),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'inputName': inputName,
    'outputName': outputName,
  };
}

class OcrImageNormalization {
  OcrImageNormalization({
    required this.scale,
    required Iterable<double> mean,
    required Iterable<double> standardDeviation,
    required this.colorOrder,
  }) : mean = _requireTriple(mean, 'mean', allowZero: true),
       standardDeviation = _requireTriple(
         standardDeviation,
         'standardDeviation',
         allowZero: false,
       ) {
    if (!scale.isFinite || scale <= 0) {
      throw ArgumentError.value(scale, 'scale', 'must be finite and positive');
    }
  }

  final double scale;
  final List<double> mean;
  final List<double> standardDeviation;
  final PaddleOcrColorOrder colorOrder;

  factory OcrImageNormalization.fromJson(Map<String, Object?> json) {
    _requireOnlyKeys(json, const <String>{
      'scale',
      'mean',
      'standardDeviation',
      'colorOrder',
    });
    return OcrImageNormalization(
      scale: _requireDouble(json, 'scale'),
      mean: _requireDoubleList(json, 'mean'),
      standardDeviation: _requireDoubleList(json, 'standardDeviation'),
      colorOrder: switch (_requireString(json, 'colorOrder')) {
        'bgr' => PaddleOcrColorOrder.bgr,
        'rgb' => PaddleOcrColorOrder.rgb,
        final value => throw FormatException(
          'Unsupported OCR color order: $value',
        ),
      },
    );
  }

  Map<String, Object> toJson() => <String, Object>{
    'scale': scale,
    'mean': mean,
    'standardDeviation': standardDeviation,
    'colorOrder': colorOrder.name,
  };
}

class PaddleOcrDetectionRuntimeConfig {
  PaddleOcrDetectionRuntimeConfig({
    String modelRole = 'detector',
    OcrTensorBinding? tensor,
    this.resizeLongSide = 960,
    OcrImageNormalization? normalization,
    this.pixelThreshold = 0.3,
    this.boxThreshold = 0.6,
    this.maxCandidates = 1000,
    this.unclipRatio = 1.5,
  }) : modelRole = _requireRole(modelRole, 'modelRole'),
       tensor = tensor ?? OcrTensorBinding(),
       normalization =
           normalization ??
           OcrImageNormalization(
             scale: 1 / 255,
             mean: const <double>[0.485, 0.456, 0.406],
             standardDeviation: const <double>[0.229, 0.224, 0.225],
             colorOrder: PaddleOcrColorOrder.bgr,
           ) {
    if (resizeLongSide < 32 || resizeLongSide > 4096) {
      throw ArgumentError.value(
        resizeLongSide,
        'resizeLongSide',
        'must be between 32 and 4096',
      );
    }
    _requireProbability(pixelThreshold, 'pixelThreshold');
    _requireProbability(boxThreshold, 'boxThreshold');
    if (maxCandidates <= 0 || maxCandidates > 10000) {
      throw ArgumentError.value(
        maxCandidates,
        'maxCandidates',
        'must be between 1 and 10000',
      );
    }
    if (!unclipRatio.isFinite || unclipRatio <= 0 || unclipRatio > 10) {
      throw ArgumentError.value(
        unclipRatio,
        'unclipRatio',
        'must be finite and between 0 and 10',
      );
    }
  }

  final String modelRole;
  final OcrTensorBinding tensor;
  final int resizeLongSide;
  final OcrImageNormalization normalization;
  final double pixelThreshold;
  final double boxThreshold;
  final int maxCandidates;
  final double unclipRatio;

  factory PaddleOcrDetectionRuntimeConfig.fromJson(Map<String, Object?> json) {
    _requireOnlyKeys(json, const <String>{
      'modelRole',
      'tensor',
      'resizeLongSide',
      'normalization',
      'pixelThreshold',
      'boxThreshold',
      'maxCandidates',
      'unclipRatio',
    });
    return PaddleOcrDetectionRuntimeConfig(
      modelRole: _requireString(json, 'modelRole'),
      tensor: OcrTensorBinding.fromJson(_requireObject(json, 'tensor')),
      resizeLongSide: _requireInt(json, 'resizeLongSide'),
      normalization: OcrImageNormalization.fromJson(
        _requireObject(json, 'normalization'),
      ),
      pixelThreshold: _requireDouble(json, 'pixelThreshold'),
      boxThreshold: _requireDouble(json, 'boxThreshold'),
      maxCandidates: _requireInt(json, 'maxCandidates'),
      unclipRatio: _requireDouble(json, 'unclipRatio'),
    );
  }

  Map<String, Object> toJson() => <String, Object>{
    'modelRole': modelRole,
    'tensor': tensor.toJson(),
    'resizeLongSide': resizeLongSide,
    'normalization': normalization.toJson(),
    'pixelThreshold': pixelThreshold,
    'boxThreshold': boxThreshold,
    'maxCandidates': maxCandidates,
    'unclipRatio': unclipRatio,
  };
}

class PaddleOcrRecognitionRuntimeConfig {
  PaddleOcrRecognitionRuntimeConfig({
    String modelRole = 'recognizer',
    String dictionaryRole = 'dictionary',
    OcrTensorBinding? tensor,
    Iterable<int> imageShape = const <int>[3, 48, 320],
    OcrImageNormalization? normalization,
    this.blankIndex = 0,
    this.useSpaceCharacter = false,
  }) : modelRole = _requireRole(modelRole, 'modelRole'),
       dictionaryRole = _requireRole(dictionaryRole, 'dictionaryRole'),
       tensor = tensor ?? OcrTensorBinding(),
       imageShape = _requireImageShape(imageShape),
       normalization =
           normalization ??
           OcrImageNormalization(
             scale: 1 / 255,
             mean: const <double>[0.5, 0.5, 0.5],
             standardDeviation: const <double>[0.5, 0.5, 0.5],
             colorOrder: PaddleOcrColorOrder.bgr,
           ) {
    if (blankIndex < 0) {
      throw ArgumentError.value(
        blankIndex,
        'blankIndex',
        'must be non-negative',
      );
    }
    if (this.modelRole == this.dictionaryRole) {
      throw ArgumentError('recognizer model and dictionary roles must differ');
    }
  }

  final String modelRole;
  final String dictionaryRole;
  final OcrTensorBinding tensor;
  final List<int> imageShape;
  final OcrImageNormalization normalization;
  final int blankIndex;
  final bool useSpaceCharacter;

  factory PaddleOcrRecognitionRuntimeConfig.fromJson(
    Map<String, Object?> json,
  ) {
    _requireOnlyKeys(json, const <String>{
      'modelRole',
      'dictionaryRole',
      'tensor',
      'imageShape',
      'normalization',
      'blankIndex',
      'useSpaceCharacter',
    });
    return PaddleOcrRecognitionRuntimeConfig(
      modelRole: _requireString(json, 'modelRole'),
      dictionaryRole: _requireString(json, 'dictionaryRole'),
      tensor: OcrTensorBinding.fromJson(_requireObject(json, 'tensor')),
      imageShape: _requireIntList(json, 'imageShape'),
      normalization: OcrImageNormalization.fromJson(
        _requireObject(json, 'normalization'),
      ),
      blankIndex: _requireInt(json, 'blankIndex'),
      useSpaceCharacter: _requireBool(json, 'useSpaceCharacter'),
    );
  }

  Map<String, Object> toJson() => <String, Object>{
    'modelRole': modelRole,
    'dictionaryRole': dictionaryRole,
    'tensor': tensor.toJson(),
    'imageShape': imageShape,
    'normalization': normalization.toJson(),
    'blankIndex': blankIndex,
    'useSpaceCharacter': useSpaceCharacter,
  };
}

class PaddleOcrRuntimeConfig {
  PaddleOcrRuntimeConfig({
    String type = 'paddleocr-ppocrv5',
    required this.detector,
    required this.recognizer,
  }) : type = _requireType(type) {
    if (detector.modelRole == recognizer.modelRole ||
        detector.modelRole == recognizer.dictionaryRole) {
      throw ArgumentError(
        'detector, recognizer, and dictionary roles must differ',
      );
    }
  }

  final String type;
  final PaddleOcrDetectionRuntimeConfig detector;
  final PaddleOcrRecognitionRuntimeConfig recognizer;

  Set<String> get requiredFileRoles => <String>{
    detector.modelRole,
    recognizer.modelRole,
    recognizer.dictionaryRole,
  };

  factory PaddleOcrRuntimeConfig.fromJson(Map<String, Object?> json) {
    _requireOnlyKeys(json, const <String>{'type', 'detector', 'recognizer'});
    return PaddleOcrRuntimeConfig(
      type: _requireString(json, 'type'),
      detector: PaddleOcrDetectionRuntimeConfig.fromJson(
        _requireObject(json, 'detector'),
      ),
      recognizer: PaddleOcrRecognitionRuntimeConfig.fromJson(
        _requireObject(json, 'recognizer'),
      ),
    );
  }

  Map<String, Object> toJson() => <String, Object>{
    'type': type,
    'detector': detector.toJson(),
    'recognizer': recognizer.toJson(),
  };
}

String _requireType(String value) {
  final normalized = value.trim();
  if (normalized != 'paddleocr-ppocrv5') {
    throw ArgumentError.value(value, 'type', 'must be paddleocr-ppocrv5');
  }
  return normalized;
}

String _requireRole(String value, String name) {
  final normalized = value.trim();
  if (!RegExp(r'^[a-z][a-z0-9_-]*$').hasMatch(normalized)) {
    throw ArgumentError.value(value, name, 'has an invalid role format');
  }
  return normalized;
}

String? _optionalText(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

List<double> _requireTriple(
  Iterable<double> values,
  String name, {
  required bool allowZero,
}) {
  final list = values.toList(growable: false);
  if (list.length != 3 ||
      list.any(
        (value) => !value.isFinite || (allowZero ? value < 0 : value <= 0),
      )) {
    throw ArgumentError.value(values, name, 'must contain three valid values');
  }
  return List<double>.unmodifiable(list);
}

List<int> _requireImageShape(Iterable<int> values) {
  final list = values.toList(growable: false);
  if (list.length != 3 || list[0] != 3 || list[1] <= 0 || list[2] <= 0) {
    throw ArgumentError.value(
      values,
      'imageShape',
      'must be [3, positive height, positive width]',
    );
  }
  return List<int>.unmodifiable(list);
}

void _requireProbability(double value, String name) {
  if (!value.isFinite || value < 0 || value > 1) {
    throw ArgumentError.value(value, name, 'must be between 0 and 1');
  }
}

void _requireOnlyKeys(Map<String, Object?> json, Set<String> allowed) {
  final unknown = json.keys.where((key) => !allowed.contains(key)).toList();
  if (unknown.isNotEmpty) {
    throw FormatException('Unknown OCR runtime fields: ${unknown.join(', ')}');
  }
}

String _requireString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String) throw FormatException('$key must be a string');
  return value;
}

String? _optionalString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String) throw FormatException('$key must be a string or null');
  return value;
}

int _requireInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! int) throw FormatException('$key must be an integer');
  return value;
}

double _requireDouble(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! num) throw FormatException('$key must be a number');
  return value.toDouble();
}

bool _requireBool(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! bool) throw FormatException('$key must be a boolean');
  return value;
}

Map<String, Object?> _requireObject(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! Map) throw FormatException('$key must be an object');
  return Map<String, Object?>.from(value);
}

List<int> _requireIntList(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! List || value.any((item) => item is! int)) {
    throw FormatException('$key must be an integer array');
  }
  return value.cast<int>();
}

List<double> _requireDoubleList(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! List || value.any((item) => item is! num)) {
    throw FormatException('$key must be a number array');
  }
  return value.cast<num>().map((value) => value.toDouble()).toList();
}
