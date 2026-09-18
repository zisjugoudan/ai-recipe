// 一次性脚本：处理 design/assets/icon/home/ 下的首页图标素材，
// 输出到 assets/icon/home/，供冰箱区、分类、快速导入、底部导航使用。
//
// 处理流程（对每张输入图）：
//   1. 自动去底：采样四角颜色取众数作为背景色，容差内像素设为透明。
//   2. 统一主题色：非透明像素替换为 AppColors.greenDeep（0xFF476B52），保留 alpha。
//   3. 按目标尺寸缩放（最近邻，保持像素风锐利）。
//   4. nav.png 按 4×2 网格切分为 8 张（未选中/选中各 4 个）。
//
// 用法：dart run tool/process_home_icons.dart
import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

const _sourceRoot = r'E:\AI\ai食谱\design\assets\icon\home';
const _outputRoot = r'E:\AI\ai食谱\code\apps\mobile\assets\icon\home';

// AppColors.greenDeep
const _themeColor = img.ColorRgba8(0x47, 0x6B, 0x52, 0xFF);

// 处理参数：背景容差、缩放目标尺寸。
const _bgTolerance = 36;
const _fridgeSize = 64;
const _categorySize = 64;
const _quickSize = 64;
const _navSize = 64;

void main() {
  final stopwatch = Stopwatch()..start();

  // 清空旧输出，保证产物可复现。
  _cleanOutput();

  // 1. 冰箱区（4 张）。
  _processDirectory(
    source: '$_sourceRoot/冰箱',
    output: '$_outputRoot/fridge',
    size: _fridgeSize,
  );

  // 2. 分类（12 张）。
  _processDirectory(
    source: '$_sourceRoot/菜品分类',
    output: '$_outputRoot/categories',
    size: _categorySize,
  );

  // 3. 快速导入（4 张）。
  _processDirectory(
    source: '$_sourceRoot/快速导图',
    output: '$_outputRoot/quick',
    size: _quickSize,
  );

  // 4. 导航栏（nav.png 切 8 张）。
  _processNavSprite(
    source: '$_sourceRoot/nav.png',
    output: '$_outputRoot/nav',
    size: _navSize,
  );

  stopwatch.stop();
  print('Done in ${stopwatch.elapsedMilliseconds}ms');
}

void _cleanOutput() {
  final root = Directory(_outputRoot);
  if (root.existsSync()) root.deleteSync(recursive: true);
  root.createSync(recursive: true);
}

void _processDirectory({
  required String source,
  required String output,
  required int size,
}) {
  Directory(output).createSync(recursive: true);
  final files = Directory(source)
      .listSync()
      .whereType<File>()
      .where((f) => f.path.toLowerCase().endsWith('.png'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  for (final file in files) {
    final bytes = file.readAsBytesSync();
    final decoded = img.decodePng(bytes);
    if (decoded == null) {
      print('Skip (not PNG): ${file.path}');
      continue;
    }
    final processed = _processImage(decoded, size);
    final outName = _baseName(file.path);
    final outPath = '$output/$outName';
    File(outPath).writeAsBytesSync(img.encodePng(processed));
    print('Processed: $outPath (${processed.width}x${processed.height})');
  }
}

String _baseName(String path) {
  return path.split(Platform.pathSeparator).last;
}

img.Image _processImage(img.Image src, int size) {
  final bg = _estimateBackground(src);
  final cleaned = img.Image.from(src);

  for (final pixel in cleaned) {
    final c = pixel;
    final alpha = c.a;
    if (alpha == 0) continue;
    if (_colorDistance(c, bg) <= _bgTolerance) {
      pixel.r = 0;
      pixel.g = 0;
      pixel.b = 0;
      pixel.a = 0;
    } else {
      // 统一为主题色，保留原 alpha（让抗锯齿边缘更自然）。
      pixel.r = _themeColor.r;
      pixel.g = _themeColor.g;
      pixel.b = _themeColor.b;
    }
  }

  // 最近邻缩放，保持像素边缘锐利。
  return img.copyResize(
    cleaned,
    width: size,
    height: size,
    interpolation: img.Interpolation.nearest,
  );
}

/// 估计背景色：采样四个角，取 RGB 出现次数最多的颜色（忽略 alpha）。
img.ColorRgba8 _estimateBackground(img.Image src) {
  final samples = <img.ColorRgba8>[
    _pixelAt(src, 0, 0),
    _pixelAt(src, src.width - 1, 0),
    _pixelAt(src, 0, src.height - 1),
    _pixelAt(src, src.width - 1, src.height - 1),
  ];

  final counts = <int, int>{};
  for (final c in samples) {
    final key = (c.r << 16) | (c.g << 8) | c.b;
    counts[key] = (counts[key] ?? 0) + 1;
  }
  final dominantKey = counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  final r = (dominantKey >> 16) & 0xFF;
  final g = (dominantKey >> 8) & 0xFF;
  final b = dominantKey & 0xFF;
  return img.ColorRgba8(r, g, b, 0xFF);
}

img.ColorRgba8 _pixelAt(img.Image src, int x, int y) {
  final c = src.getPixel(math.max(0, x), math.max(0, y));
  return img.ColorRgba8(c.r, c.g, c.b, c.a);
}

int _colorDistance(img.Pixel a, img.ColorRgba8 b) {
  final dr = a.r - b.r;
  final dg = a.g - b.g;
  final db = a.b - b.b;
  return dr * dr + dg * dg + db * db;
}

void _processNavSprite({
  required String source,
  required String output,
  required int size,
}) {
  final file = File(source);
  if (!file.existsSync()) {
    print('Nav sprite not found: $source');
    return;
  }
  Directory(output).createSync(recursive: true);
  final decoded = img.decodePng(file.readAsBytesSync());
  if (decoded == null) {
    print('Cannot decode nav sprite');
    return;
  }

  // 4 列 × 2 行：上排未选中，下排选中；列顺序：首页、菜谱库、冰箱、我的。
  const cols = 4;
  const rows = 2;
  const labels = <String>[
    'home',
    'library',
    'fridge',
    'profile',
  ];
  const states = <String>['inactive', 'active'];

  final cellW = decoded.width ~/ cols;
  final cellH = decoded.height ~/ rows;

  for (var row = 0; row < rows; row++) {
    for (var col = 0; col < cols; col++) {
      final crop = img.copyCrop(
        decoded,
        x: col * cellW,
        y: row * cellH,
        width: cellW,
        height: cellH,
      );
      final processed = _processImage(crop, size);
      final name = '${labels[col]}_${states[row]}.png';
      final outPath = '$output/$name';
      File(outPath).writeAsBytesSync(img.encodePng(processed));
      print('Processed nav: $outPath');
    }
  }
}
