import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../domain/recipe/recipe_cover_image_storer.dart';

/// 菜谱封面图片暂存异常。
class RecipeCoverImageException implements Exception {
  const RecipeCoverImageException(this.message);

  final String message;

  @override
  String toString() => 'RecipeCoverImageException: $message';
}

/// 菜谱封面图片暂存器。
///
/// 把用户从系统相册选择的图片复制到应用私有文档目录
/// `<documents>/recipe_covers/<containerId>/<index>.<ext>`，保证图片在应用
/// 重启、相册图片删除或权限变化后仍可用；同时负责删除封面文件与整组清理。
///
/// 复制前校验来源文件存在、非空且不超过大小上限；容器 ID 只允许安全字符，
/// 扩展名按白名单归一化，防止路径注入。
class DeviceRecipeCoverImageStager implements RecipeCoverImageStorer {
  DeviceRecipeCoverImageStager({
    this.maxBytes = _defaultMaxBytes,
    Future<Directory> Function()? baseDirectory,
  }) : _baseDirectory = baseDirectory ?? _defaultBaseDirectory;

  static const int _defaultMaxBytes = 20 * 1024 * 1024;

  final int maxBytes;
  final Future<Directory> Function() _baseDirectory;

  /// 默认根目录：应用文档目录下的 recipe_covers。
  static Future<Directory> _defaultBaseDirectory() async {
    final documents = await getApplicationDocumentsDirectory();
    return Directory(path.join(documents.path, 'recipe_covers'));
  }

  static const List<String> _allowedExtensions = <String>[
    'jpg',
    'jpeg',
    'png',
    'webp',
    'gif',
  ];

  /// 复制来源图片到菜谱封面目录，返回目标绝对路径。
  Future<String> copyIn({
    required String sourcePath,
    required String containerId,
    required int index,
  }) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw const RecipeCoverImageException('图片文件不存在，请重新选择。');
    }
    final size = await source.length();
    if (size <= 0) {
      throw const RecipeCoverImageException('图片内容为空，请重新选择。');
    }
    if (size > maxBytes) {
      throw const RecipeCoverImageException(
        '图片超过 20MB，请重新选择。',
      );
    }
    final extension = _normalizeExtension(sourcePath);
    final container = Directory(
      path.join((await _root()).path, _safeContainerId(containerId)),
    );
    await container.create(recursive: true);
    final target = File(path.join(container.path, '$index$extension'));
    await source.copy(target.path);
    return target.path;
  }

  /// 删除单个封面文件；文件不存在或删除失败时静默忽略。
  Future<void> deleteFile(String imagePath) async {
    try {
      final file = File(imagePath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // best-effort：清理失败不阻断主流程。
    }
  }

  /// 删除某个容器（菜谱）的全部封面文件；不存在时静默忽略。
  Future<void> deleteContainer(String containerId) async {
    try {
      final dir = Directory(
        path.join((await _root()).path, _safeContainerId(containerId)),
      );
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (_) {
      // best-effort：清理失败不阻断主流程。
    }
  }

  Future<Directory> _root() {
    return _baseDirectory();
  }

  /// 按白名单归一化扩展名，未知类型默认 .jpg。
  static String _normalizeExtension(String sourcePath) {
    final name = path.basename(sourcePath).toLowerCase();
    for (final ext in _allowedExtensions) {
      if (name.endsWith('.$ext')) {
        return '.$ext';
      }
    }
    return '.jpg';
  }

  /// 容器 ID 只允许字母、数字、下划线和短横线，防止路径注入。
  static String _safeContainerId(String id) {
    final sanitized = id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return sanitized.isEmpty ? 'recipe' : sanitized;
  }
}
