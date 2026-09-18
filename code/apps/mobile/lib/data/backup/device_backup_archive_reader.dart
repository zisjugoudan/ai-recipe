import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../domain/backup/backup_archive_constants.dart';
import '../../domain/backup/backup_cancellation_token.dart';
import '../../domain/backup/backup_errors.dart';
import '../../domain/backup/backup_import_repository.dart';
import '../../domain/backup/backup_manifest.dart';
import '../../domain/backup/backup_records.dart';

/// ZIP 安全读取实现（BACKUP-004）。
///
/// 导入包视为不可信输入，按架构 13 章逐项防御：
/// - Zip Slip：只接受备份格式白名单路径，拒绝绝对路径、盘符、`..`、
///   反斜杠变体与任意未知路径；
/// - Zip Bomb：限制单文件、总解压字节与条目数（见 [BackupImportLimits]）；
/// - 重复/大小写冲突路径：按规范化路径拒绝重复；
/// - 哈希不一致：任何必需文件（manifest 声明）失败都停止导入；
/// - JSON 资源消耗：限制单行长度与记录数；
/// - 错误信息不泄露设备绝对路径或包内敏感原文。
///
/// 解压产物落在 `<stagingDirectory>/<sessionId>/`；任一步失败清理本次
/// 会话目录并抛 [BackupException]。
class DeviceBackupArchiveReader implements BackupArchiveReader {
  DeviceBackupArchiveReader();

  @override
  Future<BackupStagedArchive> stage(BackupArchiveStageRequest request) async {
    final sessionRoot = Directory(
      p.join(request.stagingDirectory, request.sessionId),
    );
    try {
      if (await sessionRoot.exists()) {
        await sessionRoot.delete(recursive: true);
      }
      await sessionRoot.create(recursive: true);

      final source = File(request.sourcePath);
      if (!await source.exists()) {
        throw BackupException(
          BackupErrorCode.mediaMissing,
          '备份文件不存在或已被移动。',
        );
      }
      final bytes = await source.readAsBytes();
      if (bytes.isEmpty) {
        throw const BackupException(
          BackupErrorCode.archiveVerificationFailed,
          '备份文件为空。',
        );
      }

      // 1. 解析 ZIP（只读目录结构；内容按需解压）。
      final Archive archive;
      try {
        archive = ZipDecoder().decodeBytes(bytes);
      } catch (_) {
        throw const BackupException(
          BackupErrorCode.archiveVerificationFailed,
          '备份文件无法解析（不是有效的 .airecipe-backup 文件）。',
        );
      }
      if (archive.files.isEmpty) {
        throw const BackupException(
          BackupErrorCode.archiveVerificationFailed,
          '备份文件不包含任何内容。',
        );
      }
      if (archive.files.length > BackupImportLimits.maxEntryCount) {
        throw const BackupException(
          BackupErrorCode.archiveSecurityViolation,
          '备份文件条目过多，已拒绝导入。',
        );
      }

      // 2. 路径安全校验 + 收集白名单条目。
      final entries = _collectSafeEntries(archive);

      // 3. 读取并校验 manifest。
      final manifestFile = entries[BackupArchivePaths.manifestFile];
      if (manifestFile == null) {
        throw const BackupException(
          BackupErrorCode.missingDataset,
          '备份缺少清单文件 manifest.json。',
        );
      }
      final manifest = _decodeManifest(manifestFile);
      _assertRequiredDatasets(manifest, entries);

      // 4. 解压数据集到内存（按 manifest 校验 SHA-256 与行数）。
      //    进度总量 = 菜谱记录数 + 分类记录数 + 媒体条目数，逐条上报。
      int datasetRecordCount(String name) => manifest.datasets
          .firstWhere((dataset) => dataset.name == name)
          .recordCount;
      final totalRecords =
          datasetRecordCount(BackupDatasetName.recipes) +
          datasetRecordCount(BackupDatasetName.categories) +
          manifest.media.count;
      final recipes = _decodeRecipeDatasetFromArchive(
        manifest,
        BackupArchivePaths.recipesDataset,
        entries,
        token: request.token,
        startProcessed: 0,
        totalProgress: totalRecords,
        onProgress: request.onProgress,
      );
      final categories = _decodeCategoryDatasetFromArchive(
        manifest,
        BackupArchivePaths.categoriesDataset,
        entries,
        token: request.token,
        startProcessed: recipes.length,
        totalProgress: totalRecords,
        onProgress: request.onProgress,
      );

      // 5. 媒体索引 + 媒体文件校验与落盘。
      final mediaEntries = await _stageMedia(
        entries,
        manifest,
        sessionRoot,
        token: request.token,
        startProcessed: recipes.length + categories.length,
        totalProgress: totalRecords,
        onProgress: request.onProgress,
      );

      final totalBytes = _totalStagedBytes(entries, mediaEntries);
      return BackupStagedArchive(
        sessionId: request.sessionId,
        stagingRoot: sessionRoot.path,
        manifest: manifest,
        recipes: recipes,
        categories: categories,
        mediaEntries: mediaEntries,
        totalBytes: totalBytes,
      );
    } catch (_) {
      // 任一步失败清理本次会话目录，避免遗留不可信/不完整数据。
      await _deleteBestEffort(sessionRoot);
      rethrow;
    }
  }

  @override
  Future<void> cleanupSession(String stagingDirectory, String sessionId) async {
    // 删除单个会话目录：成功 finalize 或失败 rollback 后由用例调用。
    await _deleteBestEffort(Directory(p.join(stagingDirectory, sessionId)));
  }

  @override
  Future<int> cleanupAbandonedSessions(String stagingDirectory) async {
    // staging 是瞬时数据：启动时仍存在的会话目录都来自崩溃中断，直接删除。
    final root = Directory(stagingDirectory);
    var removed = 0;
    try {
      if (!await root.exists()) return 0;
      await for (final entity in root.list()) {
        if (entity is Directory) {
          await _deleteBestEffort(entity);
          removed += 1;
        } else {
          // 意外的零散文件（如半写标记）一并清理。
          try {
            await entity.delete();
          } catch (_) {
            // best-effort。
          }
        }
      }
    } catch (_) {
      // best-effort：扫描失败不阻断启动。
    }
    return removed;
  }

  /// 收集归档条目并按备份格式白名单校验路径。
  ///
  /// 返回规范化路径 → 条目映射；任何非法/重复/超限条目立即拒绝。
  static Map<String, ArchiveFile> _collectSafeEntries(Archive archive) {
    final result = <String, ArchiveFile>{};
    for (final file in archive.files) {
      if (file.isDirectory) continue;
      final rawName = file.name;
      final normalized = _normalizeEntryPath(rawName);
      if (!_isAllowedEntryPath(normalized)) {
        throw const BackupException(
          BackupErrorCode.archiveSecurityViolation,
          '备份文件包含非法路径，已拒绝导入。',
        );
      }
      if (result.containsKey(normalized)) {
        throw const BackupException(
          BackupErrorCode.archiveSecurityViolation,
          '备份文件包含重复路径，已拒绝导入。',
        );
      }
      final size = file.size;
      if (size > BackupImportLimits.maxEntryBytes) {
        throw const BackupException(
          BackupErrorCode.archiveSecurityViolation,
          '备份文件包含超过大小限制的内容，已拒绝导入。',
        );
      }
      result[normalized] = file;
    }
    return result;
  }

  /// 规范化条目路径：反斜杠转正斜杠、去前导 `./`、拒绝危险段。
  static String _normalizeEntryPath(String raw) {
    var name = raw.replaceAll('\\', '/');
    while (name.startsWith('./')) {
      name = name.substring(2);
    }
    final segments = name.split('/').where((segment) => segment.isNotEmpty);
    var normalized = segments.join('/');
    // 绝对路径或含盘符/`..` 一律拒绝。
    if (normalized.startsWith('/') ||
        normalized.contains('..') ||
        RegExp(r'^[A-Za-z]:').hasMatch(normalized)) {
      return '';
    }
    return normalized;
  }

  /// 备份格式白名单：manifest、NDJSON 数据集、媒体索引与
  /// `media/sha256/<ab>/<hash>.<ext>` 内容寻址条目。
  static bool _isAllowedEntryPath(String normalized) {
    if (normalized.isEmpty) return false;
    if (normalized == BackupArchivePaths.manifestFile) return true;
    if (normalized == BackupArchivePaths.recipesDataset) return true;
    if (normalized == BackupArchivePaths.categoriesDataset) return true;
    if (normalized == BackupArchivePaths.mediaIndexFile) return true;
    final mediaPrefix = BackupArchivePaths.mediaRoot;
    if (normalized.startsWith(mediaPrefix)) {
      final relative = normalized.substring(mediaPrefix.length);
      final segments = relative.split('/');
      // media/sha256/<ab>/<hash>.<ext>
      if (segments.length != 2) return false;
      final ab = segments[0];
      final file = segments[1];
      final dot = file.lastIndexOf('.');
      if (dot <= 0 || dot == file.length - 1) return false;
      final hash = file.substring(0, dot);
      final extension = file.substring(dot + 1);
      if (ab.length != 2 || !RegExp(r'^[0-9a-f]{2}$').hasMatch(ab)) {
        return false;
      }
      if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(hash)) return false;
      if (ab != hash.substring(0, 2)) return false;
      if (extension.isEmpty ||
          !RegExp(r'^[a-z0-9]{2,8}$').hasMatch(extension)) {
        return false;
      }
      return true;
    }
    return false;
  }

  /// 解析 manifest.json（严格校验 + 版本兼容）。
  static BackupManifest _decodeManifest(ArchiveFile file) {
    try {
      final raw = utf8.decode(file.readBytes() ?? Uint8List(0));
      final json = jsonDecode(raw);
      if (json is! Map<Object?, Object?>) {
        throw const FormatException('manifest 顶层不是对象');
      }
      return BackupManifest.fromJson(json.cast<String, Object?>());
    } on BackupException {
      rethrow;
    } on FormatException catch (error) {
      throw BackupException(
        BackupErrorCode.formatNotSupported,
        '备份清单无法解析：${error.message}',
      );
    } catch (_) {
      throw const BackupException(
        BackupErrorCode.formatNotSupported,
        '备份清单无法解析。',
      );
    }
  }

  /// 校验必需数据集存在，并拒绝不认识的必需 Dataset。
  static void _assertRequiredDatasets(
    BackupManifest manifest,
    Map<String, ArchiveFile> entries,
  ) {
    final names = manifest.datasets.map((dataset) => dataset.name).toSet();
    if (!names.contains(BackupDatasetName.recipes)) {
      throw const BackupException(
        BackupErrorCode.missingDataset,
        '备份缺少菜谱数据集。',
      );
    }
    if (!names.contains(BackupDatasetName.categories)) {
      throw const BackupException(
        BackupErrorCode.missingDataset,
        '备份缺少分类数据集。',
      );
    }
    for (final dataset in manifest.datasets) {
      if (!BackupDatasetName.all.contains(dataset.name)) {
        throw BackupException(
          BackupErrorCode.formatNotSupported,
          '备份包含当前版本无法识别的数据：${dataset.name}。',
        );
      }
    }
    // 必需数据集在归档中必须真实存在（与 manifest 声明一致）。
    if (!entries.containsKey(BackupArchivePaths.recipesDataset) ||
        !entries.containsKey(BackupArchivePaths.categoriesDataset)) {
      throw const BackupException(
        BackupErrorCode.missingDataset,
        '备份缺少必需的数据文件。',
      );
    }
  }

  /// 按 manifest 校验并逐行解析菜谱数据集。
  static List<RecipeBackupRecord> _decodeRecipeDatasetFromArchive(
    BackupManifest manifest,
    String archivePath,
    Map<String, ArchiveFile> entries, {
    BackupCancellationToken? token,
    int startProcessed = 0,
    int totalProgress = 0,
    void Function(int processed, int total)? onProgress,
  }) {
    token?.throwIfCancelled();
    final content = _readVerifiedDataset(
      manifest,
      BackupDatasetName.recipes,
      archivePath,
      entries,
    );
    final lines = _splitNdjson(content);
    final records = <RecipeBackupRecord>[];
    for (final (i, line) in lines.indexed) {
      try {
        final json = jsonDecode(utf8.decode(line));
        if (json is! Map<Object?, Object?>) {
          throw const FormatException('数据集行不是对象');
        }
        records.add(
          RecipeBackupRecord.fromJson(json.cast<String, Object?>()),
        );
      } on FormatException catch (error) {
        throw BackupException(
          BackupErrorCode.dataValidationFailed,
          '菜谱数据格式错误：${error.message}',
        );
      }
      // 每解析一条上报一次进度（与分类/媒体累计在同一总量上）。
      onProgress?.call(startProcessed + i + 1, totalProgress);
    }
    return records;
  }

  /// 按 manifest 校验并逐行解析分类数据集。
  static List<CategoryBackupRecord> _decodeCategoryDatasetFromArchive(
    BackupManifest manifest,
    String archivePath,
    Map<String, ArchiveFile> entries, {
    BackupCancellationToken? token,
    int startProcessed = 0,
    int totalProgress = 0,
    void Function(int processed, int total)? onProgress,
  }) {
    token?.throwIfCancelled();
    final content = _readVerifiedDataset(
      manifest,
      BackupDatasetName.categories,
      archivePath,
      entries,
    );
    final lines = _splitNdjson(content);
    final records = <CategoryBackupRecord>[];
    for (final (i, line) in lines.indexed) {
      try {
        final json = jsonDecode(utf8.decode(line));
        if (json is! Map<Object?, Object?>) {
          throw const FormatException('数据集行不是对象');
        }
        records.add(
          CategoryBackupRecord.fromJson(json.cast<String, Object?>()),
        );
      } on FormatException catch (error) {
        throw BackupException(
          BackupErrorCode.dataValidationFailed,
          '分类数据格式错误：${error.message}',
        );
      }
      onProgress?.call(startProcessed + i + 1, totalProgress);
    }
    return records;
  }

  /// 读取数据集字节并按 manifest 校验 SHA-256 与记录数。
  static Uint8List _readVerifiedDataset(
    BackupManifest manifest,
    String datasetName,
    String archivePath,
    Map<String, ArchiveFile> entries,
  ) {
    final descriptor = manifest.datasets.firstWhere(
      (dataset) => dataset.name == datasetName,
      orElse: () => throw BackupException(
        BackupErrorCode.missingDataset,
        '备份缺少数据集：$datasetName。',
      ),
    );
    final file = entries[archivePath];
    if (file == null) {
      throw const BackupException(
        BackupErrorCode.missingDataset,
        '备份缺少数据文件。',
      );
    }
    final content = file.readBytes() ?? Uint8List(0);
    // 数据集 SHA-256 必须与 manifest 一致（防篡改/损坏）。
    if (sha256.convert(content).toString() != descriptor.sha256) {
      throw const BackupException(
        BackupErrorCode.archiveVerificationFailed,
        '备份数据校验不一致，已停止导入。',
      );
    }
    final lines = _splitNdjson(content);
    if (lines.length != descriptor.recordCount) {
      throw const BackupException(
        BackupErrorCode.archiveVerificationFailed,
        '备份数据记录数与清单不一致，已停止导入。',
      );
    }
    return content;
  }

  /// 媒体索引与媒体文件：逐条校验 SHA-256 后写入 staging。
  static Future<List<BackupStagedMedia>> _stageMedia(
    Map<String, ArchiveFile> entries,
    BackupManifest manifest,
    Directory sessionRoot, {
    BackupCancellationToken? token,
    int startProcessed = 0,
    int totalProgress = 0,
    void Function(int processed, int total)? onProgress,
  }) async {
    token?.throwIfCancelled();

    // 解析媒体索引（manifest.media.count 兜底校验）。
    final indexFile = entries[BackupArchivePaths.mediaIndexFile];
    if (indexFile == null) {
      throw const BackupException(
        BackupErrorCode.missingDataset,
        '备份缺少媒体索引。',
      );
    }
    final indexEntries = <BackupMediaIndexEntry>[];
    final indexLines = _splitNdjson(
      indexFile.readBytes() ?? Uint8List(0),
    );
    for (final line in indexLines) {
      try {
        final json = jsonDecode(utf8.decode(line));
        if (json is! Map<Object?, Object?>) {
          throw const FormatException('媒体索引行不是对象');
        }
        indexEntries.add(
          BackupMediaIndexEntry.fromJson(json.cast<String, Object?>()),
        );
      } on FormatException catch (error) {
        throw BackupException(
          BackupErrorCode.dataValidationFailed,
          '媒体索引格式错误：${error.message}',
        );
      }
    }
    if (indexEntries.length != manifest.media.count) {
      throw const BackupException(
        BackupErrorCode.archiveVerificationFailed,
        '备份媒体数量与清单不一致，已停止导入。',
      );
    }

    final staged = <BackupStagedMedia>[];
    var totalMediaBytes = 0;
    for (final (i, entry) in indexEntries.indexed) {
      token?.throwIfCancelled();
      final archiveEntry = entries[entry.relativeKey];
      if (archiveEntry == null) {
        throw BackupException(
          BackupErrorCode.mediaMissing,
          '备份缺少必需图片：${entry.sha256.substring(0, 8)}…',
        );
      }
      final bytes = archiveEntry.readBytes() ?? Uint8List(0);
      if (bytes.length != entry.byteSize) {
        throw BackupException(
          BackupErrorCode.mediaHashMismatch,
          '备份图片大小不一致，已停止导入。',
        );
      }
      final actual = sha256.convert(bytes).toString();
      if (actual != entry.sha256) {
        throw BackupException(
          BackupErrorCode.mediaHashMismatch,
          '备份图片校验不一致，已停止导入。',
        );
      }
      // 写入 staging（保持内容寻址相对结构）。
      final target = File(p.join(sessionRoot.path, entry.relativeKey));
      await target.create(recursive: true);
      await target.writeAsBytes(bytes, flush: true);
      staged.add(
        BackupStagedMedia(
          sha256: entry.sha256,
          mime: entry.mime,
          byteSize: entry.byteSize,
          relativeKey: entry.relativeKey,
          stagingPath: target.path,
        ),
      );
      totalMediaBytes += entry.byteSize;
      if (totalMediaBytes > BackupImportLimits.maxTotalBytes) {
        throw const BackupException(
          BackupErrorCode.archiveSecurityViolation,
          '备份解压总大小超过限制，已拒绝导入。',
        );
      }
      // 每校验落盘一张图片上报一次进度。
      onProgress?.call(startProcessed + i + 1, totalProgress);
    }
    return staged;
  }

  /// 把 NDJSON 拆成行（去空行；超长行拒绝，防 JSON 资源消耗）。
  ///
  /// 只做字节切分与行长度限制；真正的 UTF-8 解码与 JSON 解析在各
  /// 数据集的逐行解析阶段进行，那里的 FormatException 会被包装成
  /// 稳定 [BackupException]。
  static List<Uint8List> _splitNdjson(Uint8List content) {
    final lines = <Uint8List>[];
    // 按 \n 切分并保留原始字节行，避免重复解码大文件。
    var start = 0;
    for (var i = 0; i < content.length; i++) {
      if (content[i] != 0x0a) continue;
      if (i - start > BackupImportLimits.maxJsonLineBytes) {
        throw const BackupException(
          BackupErrorCode.jsonResourceLimit,
          '备份数据行过大，已拒绝导入。',
        );
      }
      final line = Uint8List.sublistView(content, start, i);
      if (line.isNotEmpty) {
        lines.add(line);
      }
      start = i + 1;
    }
    if (start < content.length) {
      final line = Uint8List.sublistView(content, start);
      if (line.length > BackupImportLimits.maxJsonLineBytes) {
        throw const BackupException(
          BackupErrorCode.jsonResourceLimit,
          '备份数据行过大，已拒绝导入。',
        );
      }
      if (line.isNotEmpty) {
        lines.add(line);
      }
    }
    return lines;
  }

  static int _totalStagedBytes(
    Map<String, ArchiveFile> entries,
    List<BackupStagedMedia> mediaEntries,
  ) {
    var total = 0;
    for (final entry in entries.values) {
      total += entry.size;
    }
    for (final media in mediaEntries) {
      total += media.byteSize;
    }
    return total;
  }

  static Future<void> _deleteBestEffort(Directory directory) async {
    try {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    } catch (_) {
      // best-effort：清理失败不阻断主流程（启动清理会再次尝试）。
    }
  }
}
