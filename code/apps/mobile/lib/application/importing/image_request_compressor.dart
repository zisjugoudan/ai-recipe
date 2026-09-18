import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// 识别前图片压缩结果。
///
/// [bytes] 为压缩后的字节，[mimeType] 固定为 `image/jpeg`，[width]/[height]
/// 为压缩后的尺寸。若压缩失败或没收益，处理器应保留原图，不替换。
class CompressedImage {
  const CompressedImage({
    required this.bytes,
    required this.mimeType,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
  final String mimeType;
  final int width;
  final int height;
}

/// 识别前图片压缩/重编码器（解决方案 P0-3）。
///
/// 上传给多模态识别的图片在交给 Provider 前先缩边并重编码为 JPEG，降低
/// 上传体积与 Provider 端解码开销：
/// - 普通照片：长边超过 [maxPhotoLongSide]（默认 2048）时等比缩小；
/// - 文字密集的菜谱截图（长宽比悬殊，通常为竖屏截图）：保留更高分辨率，
///   长边上限放宽到 [maxScreenshotLongSide]（默认 4096），避免文字糊掉；
/// - 统一重编码为 JPEG，质量 [jpgQuality]（默认 85）。
///
/// 压缩本身不修改磁盘上的原图（原图仍用于封面保存），只影响上传给识别
/// 引擎的字节。若解码失败或压缩后体积不小于原图，返回 null 表示“保留原图”。
class ImageRequestCompressor {
  const ImageRequestCompressor({
    this.maxPhotoLongSide = 2048,
    this.maxScreenshotLongSide = 4096,
    this.screenshotAspectRatio = 2.5,
    this.jpgQuality = 85,
  });

  /// 普通照片的长边上限（px）。
  final int maxPhotoLongSide;

  /// 文字密集截图（竖屏长图）的长边上限（px）。
  final int maxScreenshotLongSide;

  /// 判定为“截图/长图”的长宽比阈值，超过即视为文字密集截图。
  final double screenshotAspectRatio;

  /// JPEG 质量（1-100）。
  final int jpgQuality;

  /// 压缩 [bytes]；无需压缩或压缩失败时返回 null。
  ///
  /// [byteLength] 用于在压缩没有体积收益时提前放弃，避免无谓的解码开销。
  CompressedImage? compress({
    required Uint8List bytes,
    required int byteLength,
  }) {
    // 解码失败（或格式不支持）时保留原图，不阻塞识别。
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;

    // 修正 EXIF 旋转，避免手机竖拍照片在识别前横置。
    final oriented = img.bakeOrientation(decoded);

    // 依据长宽比选择长边上限：竖屏长图多为文字密集的菜谱截图。
    final longSide = oriented.width >= oriented.height ? oriented.width : oriented.height;
    final shortSide = oriented.width < oriented.height ? oriented.width : oriented.height;
    final ratio = shortSide == 0 ? 1.0 : longSide / shortSide;
    final isScreenshot = ratio >= screenshotAspectRatio;
    final maxLongSide = isScreenshot ? maxScreenshotLongSide : maxPhotoLongSide;

    img.Image result = oriented;
    if (longSide > maxLongSide && shortSide > 0) {
      // 等比缩放：以长边对齐上限，保持宽高比。
      final scale = maxLongSide / longSide;
      final targetWidth = (oriented.width * scale).round().clamp(1, maxLongSide);
      final targetHeight = (oriented.height * scale).round().clamp(1, maxLongSide);
      result = img.copyResize(
        oriented,
        width: targetWidth,
        height: targetHeight,
        interpolation: img.Interpolation.average,
      );
    }

    // 重编码为 JPEG。
    final encoded = img.encodeJpg(result, quality: jpgQuality);
    if (encoded.isEmpty) return null;

    // 没有体积收益时保留原图，避免因重编码反而变大。
    if (encoded.length >= byteLength) return null;

    return CompressedImage(
      bytes: encoded,
      mimeType: 'image/jpeg',
      width: result.width,
      height: result.height,
    );
  }
}