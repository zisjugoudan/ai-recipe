// 一次性脚本：根据 design/assets/图标.png 生成 Android 与 iOS 应用启动图标。
// 用法：在 code/apps/mobile 目录下执行 `dart run tool/gen_launcher_icons.dart`。
// 处理策略：
//   1. 源图（2026-08-10 更新为 2048x2048，居中裁剪为正方形 2048x2048）。
//   2. 按各平台规范缩放到目标尺寸（cubic 插值）。
//   3. Android 直接输出（允许透明通道）；iOS 先合成纯白底再输出（无 alpha，符合 App Store 要求）。
import 'dart:io';
import 'package:image/image.dart' as img;

void main() {
  final srcFile = File(r'E:\AI\ai食谱\design\assets\图标.png');
  final src = img.decodePng(srcFile.readAsBytesSync());
  if (src == null) throw StateError('无法解码源图: ${srcFile.path}');

  // 居中裁剪为正方形
  final side = src.width < src.height ? src.width : src.height;
  final square = img.copyCrop(src,
      x: (src.width - side) ~/ 2,
      y: (src.height - side) ~/ 2,
      width: side,
      height: side);
  stdout.writeln('源图 ${src.width}x${src.height}，居中裁剪为 ${side}x$side');

  // Android: 各 density 的 ic_launcher.png（允许透明通道）
  const androidSizes = {
    'mipmap-mdpi': 48,
    'mipmap-hdpi': 72,
    'mipmap-xhdpi': 96,
    'mipmap-xxhdpi': 144,
    'mipmap-xxxhdpi': 192,
  };
  const androidResDir = r'E:\AI\ai食谱\code\apps\mobile\android\app\src\main\res';
  for (final entry in androidSizes.entries) {
    final icon = resizeSquare(square, entry.value);
    final out = File('$androidResDir\\${entry.key}\\ic_launcher.png');
    out.writeAsBytesSync(img.encodePng(icon));
    stdout.writeln('Android: ${out.path} (${icon.width}x${icon.height})');
  }

  // iOS: AppIcon.appiconset（无透明通道，合成白底）
  const iosSizes = {
    'Icon-App-20x20@1x.png': 20,
    'Icon-App-20x20@2x.png': 40,
    'Icon-App-20x20@3x.png': 60,
    'Icon-App-29x29@1x.png': 29,
    'Icon-App-29x29@2x.png': 58,
    'Icon-App-29x29@3x.png': 87,
    'Icon-App-40x40@1x.png': 40,
    'Icon-App-40x40@2x.png': 80,
    'Icon-App-40x40@3x.png': 120,
    'Icon-App-60x60@2x.png': 120,
    'Icon-App-60x60@3x.png': 180,
    'Icon-App-76x76@1x.png': 76,
    'Icon-App-76x76@2x.png': 152,
    'Icon-App-83.5x83.5@2x.png': 167,
    'Icon-App-1024x1024@1x.png': 1024,
  };
  const iosDir =
      r'E:\AI\ai食谱\code\apps\mobile\ios\Runner\Assets.xcassets\AppIcon.appiconset';
  for (final entry in iosSizes.entries) {
    // 缩放到目标尺寸后，在白底画布上合成，彻底去掉 alpha 通道
    final resized = resizeSquare(square, entry.value);
    final opaque = img.Image(width: entry.value, height: entry.value, numChannels: 3);
    img.fill(opaque, color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(opaque, resized);
    final out = File('$iosDir\\${entry.key}');
    out.writeAsBytesSync(img.encodePng(opaque));
    stdout.writeln('iOS: ${out.path} (${opaque.width}x${opaque.height})');
  }
  stdout.writeln('完成：共生成 ${androidSizes.length + iosSizes.length} 个图标文件');
}

/// 把正方形源图缩放到 [size]x[size]（cubic 插值）。
img.Image resizeSquare(img.Image square, int size) =>
    img.resize(square, width: size, height: size, interpolation: img.Interpolation.cubic);
