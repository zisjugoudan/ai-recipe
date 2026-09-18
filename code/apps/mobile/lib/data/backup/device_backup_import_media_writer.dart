import 'dart:io';

import 'package:ai_recipe/domain/backup/backup_cancellation_token.dart';
import 'package:ai_recipe/domain/backup/backup_import_repository.dart';
import 'package:ai_recipe/domain/backup/backup_records.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// 设备媒体落盘实现（BACKUP-004）。
///
/// 把 staging 中已验证的媒体文件（sha256 → 内容）按菜谱/分类容器复制到
/// `<documents>/recipe_covers/<id>/`：
/// - 菜谱：封面 → `0.<ext>`，画廊图按序 → `1..n.<ext>`；
/// - 分类：封面 → `cat-<id>/0.<ext>`；
/// - 同一容器内相同 sha256 只写一次（内容寻址去重），不同容器各写一份。
///
/// 回滚语义：只删除本次**新建**（之前不存在）的文件，已存在文件被覆盖
/// 时不计入 createdFiles，避免 rollback 误删导入前就存在的媒体。
class DeviceBackupImportMediaWriter implements BackupImportMediaWriter {
  DeviceBackupImportMediaWriter({
    Future<Directory> Function()? coverRootProvider,
  }) : _coverRootProvider = coverRootProvider ?? _defaultCoverRoot;

  final Future<Directory> Function() _coverRootProvider;

  static Future<Directory> _defaultCoverRoot() async {
    final documents = await getApplicationDocumentsDirectory();
    return Directory(path.join(documents.path, 'recipe_covers'));
  }

  /// 与既有菜谱封面目录一致的白名单扩展名（未知类型回退 .jpg）。
  static const List<String> _allowedExtensions = <String>[
    'jpg',
    'jpeg',
    'png',
    'webp',
    'gif',
  ];

  @override
  Future<BackupMediaWriteResult> stageMediaToCoverStorage({
    required List<RecipeBackupRecord> recipes,
    required List<CategoryBackupRecord> categories,
    required List<BackupStagedMedia> stagedMedia,
    BackupCancellationToken? token,
    void Function(int processed, int total)? onProgress,
  }) async {
    token?.throwIfCancelled();
    final bySha = <String, BackupStagedMedia>{
      for (final media in stagedMedia) media.sha256: media,
    };
    final root = await _coverRootProvider();
    final recipeMediaPaths = <String, BackupRecipeMediaPaths>{};
    final categoryCoverPaths = <String, String>{};
    final createdFiles = <String>[];

    // 进度总量 = 菜谱封面/画廊引用数 + 分类封面引用数，每写一个上报一次。
    var totalReferences = 0;
    for (final recipe in recipes) {
      if (recipe.coverImage != null) totalReferences += 1;
      totalReferences += recipe.images.length;
    }
    for (final category in categories) {
      if (category.coverImage != null) totalReferences += 1;
    }
    var processedReferences = 0;
    void report() {
      processedReferences += 1;
      onProgress?.call(processedReferences, totalReferences);
    }

    for (final recipe in recipes) {
      token?.throwIfCancelled();
      final container = Directory(
        path.join(root.path, _safeContainerId(recipe.id)),
      );
      final local = <String, String>{}; // sha256 → 本地路径（容器内去重）。
      final cover = await _writeReference(
        container: container,
        reference: recipe.coverImage,
        index: 0,
        bySha: bySha,
        local: local,
        createdFiles: createdFiles,
      );
      if (recipe.coverImage != null) report();
      final images = <String>[];
      for (final entry in recipe.images.indexed) {
        token?.throwIfCancelled();
        final image = await _writeReference(
          container: container,
          reference: entry.$2,
          index: entry.$1 + 1,
          bySha: bySha,
          local: local,
          createdFiles: createdFiles,
        );
        report();
        if (image != null) {
          images.add(image);
        }
      }
      if (cover != null || images.isNotEmpty) {
        recipeMediaPaths[recipe.id] = BackupRecipeMediaPaths(
          coverImage: cover,
          images: images,
        );
      }
    }

    for (final category in categories) {
      token?.throwIfCancelled();
      final cover = category.coverImage;
      if (cover == null) continue;
      // 分类容器加 cat- 前缀，与菜谱容器互不干扰。
      final container = Directory(
        path.join(root.path, 'cat-${_safeContainerId(category.id)}'),
      );
      final local = <String, String>{};
      final written = await _writeReference(
        container: container,
        reference: cover,
        index: 0,
        bySha: bySha,
        local: local,
        createdFiles: createdFiles,
      );
      report();
      if (written != null) {
        categoryCoverPaths[category.id] = written;
      }
    }

    return BackupMediaWriteResult(
      recipeMediaPaths: recipeMediaPaths,
      categoryCoverPaths: categoryCoverPaths,
      createdFiles: createdFiles,
    );
  }

  /// 写单个媒体引用：容器内按 sha256 去重，返回本地绝对路径。
  static Future<String?> _writeReference({
    required Directory container,
    required BackupMediaReference? reference,
    required int index,
    required Map<String, BackupStagedMedia> bySha,
    required Map<String, String> local,
    required List<String> createdFiles,
  }) async {
    if (reference == null) return null;
    final existing = local[reference.sha256];
    if (existing != null) return existing;
    final staged = bySha[reference.sha256];
    // 包内缺失的媒体已在 stage() 阶段整体失败，此处正常应命中；
    // 防御性返回 null，不写入悬空路径。
    if (staged == null) return null;

    final extension = _normalizeExtension(staged.relativeKey);
    final target = File(path.join(container.path, '$index$extension'));
    final created = await _copyIfNeeded(staged.stagingPath, target);
    if (created) {
      createdFiles.add(target.path);
    }
    local[reference.sha256] = target.path;
    return target.path;
  }

  /// 复制 staging 文件到目标；仅当目标之前不存在时返回 true（计入回滚清单）。
  static Future<bool> _copyIfNeeded(String sourcePath, File target) async {
    final existed = await target.exists();
    final source = File(sourcePath);
    if (!await source.exists()) return false;
    await target.parent.create(recursive: true);
    await source.copy(target.path);
    return !existed;
  }

  @override
  Future<void> rollbackMedia(List<String> createdFiles) async {
    final parentDirs = <String>{};
    for (final filePath in createdFiles) {
      try {
        final file = File(filePath);
        if (await file.exists()) {
          await file.delete();
        }
        parentDirs.add(path.dirname(filePath));
      } catch (_) {
        // best-effort。
      }
    }
    // 删除因此变空的容器目录（递归向上，仅删空目录）。
    for (final dirPath in parentDirs) {
      try {
        var current = Directory(dirPath);
        while (await current.exists()) {
          final isEmpty = await current.list().isEmpty;
          if (!isEmpty) break;
          await current.delete();
          current = current.parent;
        }
      } catch (_) {
        // best-effort。
      }
    }
  }

  /// 从内容寻址相对键提取扩展名并做白名单归一化。
  static String _normalizeExtension(String relativeKey) {
    final raw = path.extension(relativeKey).toLowerCase();
    final ext = raw.startsWith('.') ? raw.substring(1) : raw;
    return _allowedExtensions.contains(ext) ? ext : 'jpg';
  }

  /// 容器 ID 只允许安全字符，防止路径注入。
  static String _safeContainerId(String id) {
    final sanitized = id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return sanitized.isEmpty ? 'recipe' : sanitized;
  }
}
