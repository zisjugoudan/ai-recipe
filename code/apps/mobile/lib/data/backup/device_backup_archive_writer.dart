import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:ai_recipe/domain/backup/backup_archive_constants.dart';
import 'package:ai_recipe/domain/backup/backup_errors.dart';
import 'package:ai_recipe/domain/backup/backup_repository.dart';
import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart' show ZipFileEncoder;
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// 设备归档写入器（BACKUP-002/003）。
///
/// 职责：
/// 1. 在 [outputDirectory] 下以 `<文件名>.partial` 为临时文件组装标准 ZIP：
///    manifest.json + data/*.ndjson（Dataset）+ media/index.v1.ndjson +
///    media/sha256/ 内容寻址媒体文件（按 sha256 去重，同哈希只写一次）。
/// 2. 写完后重读归档复核：必需条目齐全、Dataset 与媒体 SHA-256 与
///    manifest / 媒体索引一致、无多余条目。
/// 3. 复核通过后原子重命名为最终文件；任一步骤失败删除半成品。
///
/// ZIP 组装与复核在后台 [Isolate.run] 中同步执行，避免大数据量时
/// 阻塞 UI；取消在调用侧通过令牌检查，写入阶段结束后统一清理。
class DeviceBackupArchiveWriter implements BackupArchiveWriter {
  @override
  Future<BackupWriteReceipt> write(BackupWriteRequest request) async {
    final result = await Isolate.run(
      () => _writeInIsolate(
        manifestJson: request.manifest.encode(),
        datasets: request.datasets,
        mediaIndexBytes: request.mediaIndexBytes,
        mediaFiles: request.mediaFiles
            .map(
              (media) => <String, String>{
                'sha256': media.sha256,
                'extension': media.extension,
                'sourcePath': media.sourcePath,
              },
            )
            .toList(),
        outputDirectory: request.outputDirectory,
        outputFileName: request.outputFileName,
      ),
    );
    if (result.errorCode != null) {
      throw BackupException(
        result.errorCode!,
        result.errorMessage ?? '归档写入失败。',
      );
    }
    return BackupWriteReceipt(
      filePath: result.filePath!,
      byteSize: result.byteSize!,
    );
  }

  /// 在后台 isolate 中执行完整的组装、复核与原子发布。
  static Future<_IsolateWriteResult> _writeInIsolate({
    required String manifestJson,
    required Map<String, List<int>> datasets,
    required List<int> mediaIndexBytes,
    required List<Map<String, String>> mediaFiles,
    required String outputDirectory,
    required String outputFileName,
  }) async {
    final partialPath = p.join(outputDirectory, '$outputFileName.partial');
    final finalPath = p.join(outputDirectory, outputFileName);
    try {
      final directory = Directory(outputDirectory);
      await directory.create(recursive: true);

      // 清理上次遗留的半成品，避免写入冲突。
      final partialFile = File(partialPath);
      if (await partialFile.exists()) {
        await partialFile.delete();
      }

      // 1. 组装 ZIP。
      // 内存字节（manifest/NDJSON/媒体索引）用 addArchiveFile；磁盘文件
      // 用 addFile（第二个位置参数为归档内文件名）。
      final encoder = ZipFileEncoder();
      encoder.create(partialPath);
      encoder.addArchiveFile(
        ArchiveFile.bytes(
          BackupArchivePaths.manifestFile,
          utf8.encode(manifestJson),
        ),
      );
      for (final entry in datasets.entries) {
        encoder.addArchiveFile(ArchiveFile.bytes(entry.key, entry.value));
      }
      encoder.addArchiveFile(
        ArchiveFile.bytes(BackupArchivePaths.mediaIndexFile, mediaIndexBytes),
      );
      for (final media in mediaFiles) {
        final source = File(media['sourcePath']!);
        if (!await source.exists()) {
          throw _IsoFailure(
            BackupErrorCode.mediaMissing,
            '必需图片不存在：${media['sourcePath']}',
          );
        }
        // 必须 await：ZipFileEncoder.addFile 是异步流式写入，未 await 会与
        // 后续 close() 产生竞态，媒体条目写入不完整导致归档复核失败。
        await encoder.addFile(
          source,
          BackupArchivePaths.mediaEntryPath(
            media['sha256']!,
            media['extension']!,
          ),
        );
      }
      await encoder.close();

      // 2. 重读归档复核（条目齐全 + Dataset/媒体哈希一致 + 无多余条目）。
      final verification = await _verifyArchive(
        partialPath,
        manifestJson: manifestJson,
        datasets: datasets,
        mediaIndexBytes: mediaIndexBytes,
        mediaFiles: mediaFiles,
      );
      if (verification != null) throw verification;

      // 3. 原子发布：先清掉同名旧文件再重命名。
      final finalFile = File(finalPath);
      if (await finalFile.exists()) {
        await finalFile.delete();
      }
      await partialFile.rename(finalPath);
      return _IsolateWriteResult(
        filePath: finalPath,
        byteSize: await finalFile.length(),
      );
    } on _IsoFailure catch (failure) {
      await _cleanupBestEffort(partialPath);
      return _IsolateWriteResult(
        errorCode: failure.code,
        errorMessage: failure.message,
      );
    } on FileSystemException {
      await _cleanupBestEffort(partialPath);
      return const _IsolateWriteResult(
        errorCode: BackupErrorCode.archiveWriteFailed,
        errorMessage: '备份写入失败，请检查设备剩余空间。',
      );
    } catch (_) {
      await _cleanupBestEffort(partialPath);
      return const _IsolateWriteResult(
        errorCode: BackupErrorCode.archiveWriteFailed,
        errorMessage: '备份写入失败，请稍后重试。',
      );
    }
  }

  /// 重读归档并复核；通过返回 null，否则返回失败详情。
  static Future<_IsoFailure?> _verifyArchive(
    String zipPath, {
    required String manifestJson,
    required Map<String, List<int>> datasets,
    required List<int> mediaIndexBytes,
    required List<Map<String, String>> mediaFiles,
  }) async {
    try {
      final bytes = await File(zipPath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      final byName = <String, ArchiveFile>{
        for (final file in archive.files) file.name: file,
      };

      // 必需条目齐全。
      const requiredEntries = <String>[
        BackupArchivePaths.manifestFile,
        BackupArchivePaths.recipesDataset,
        BackupArchivePaths.categoriesDataset,
        BackupArchivePaths.mediaIndexFile,
      ];
      for (final entry in requiredEntries) {
        if (!byName.containsKey(entry)) {
          return const _IsoFailure(
            BackupErrorCode.archiveVerificationFailed,
            '归档复核失败：缺少必需文件。',
          );
        }
      }

      // Dataset 内容哈希与 manifest 描述一致（manifest 本身以字节参与，
      // 防止篡改后仍通过）。
      // 注意：不能直接比较 List 实例（Dart 的 List 未重写 ==，比较的是
      // 对象身份，两个内容相同但实例不同的列表永远不等），必须逐字节比较。
      final storedManifest =
          _unsigned(byName[BackupArchivePaths.manifestFile]!.content);
      final expectedManifest = _unsigned(utf8.encode(manifestJson));
      if (!_bytesEqual(storedManifest, expectedManifest)) {
        return const _IsoFailure(
          BackupErrorCode.archiveVerificationFailed,
          '归档复核失败：清单内容不一致。',
        );
      }
      for (final entry in datasets.entries) {
        final stored = byName[entry.key];
        if (stored == null ||
            _sha256Of(stored.content) !=
                _sha256Of(entry.value)) {
          return const _IsoFailure(
            BackupErrorCode.archiveVerificationFailed,
            '归档复核失败：数据集内容不一致。',
          );
        }
      }
      if (_sha256Of(byName[BackupArchivePaths.mediaIndexFile]!.content) !=
          _sha256Of(mediaIndexBytes)) {
        return const _IsoFailure(
          BackupErrorCode.archiveVerificationFailed,
          '归档复核失败：媒体索引不一致。',
        );
      }

      // 媒体文件逐一哈希复核。
      for (final media in mediaFiles) {
        final entryPath = BackupArchivePaths.mediaEntryPath(
          media['sha256']!,
          media['extension']!,
        );
        final stored = byName[entryPath];
        if (stored == null ||
            _sha256Of(stored.content) != media['sha256']) {
          return const _IsoFailure(
            BackupErrorCode.archiveVerificationFailed,
            '归档复核失败：媒体文件内容不一致。',
          );
        }
      }

      // 无多余条目（防止把无关文件混入备份包）。
      // requiredEntries 已包含 manifest、全部 dataset 与媒体索引，
      // 因此条目总数 = requiredEntries + 媒体文件（勿重复累计 datasets）。
      final expectedCount = requiredEntries.length + mediaFiles.length;
      if (archive.files.length != expectedCount) {
        return const _IsoFailure(
          BackupErrorCode.archiveVerificationFailed,
          '归档复核失败：包含未知条目。',
        );
      }
      return null;
    } catch (error) {
      return const _IsoFailure(
        BackupErrorCode.archiveVerificationFailed,
        '归档复核失败：无法读取归档。',
      );
    }
  }

  static Future<void> _cleanupBestEffort(String partialPath) async {
    try {
      final file = File(partialPath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // best-effort：清理失败不阻塞错误上抛。
    }
  }

  static String _sha256Of(List<int> bytes) =>
      sha256.convert(bytes).toString();

  /// 归一化为无符号字节列表（archive 可能返回 signed 字节表示）。
  static List<int> _unsigned(List<int> bytes) =>
      bytes.map((byte) => byte.toUnsigned(8)).toList();

  /// 逐字节比较两个字节列表。
  ///
  /// 不能直接使用 `!=`：Dart 的 List 未重写 ==，两个内容相同但实例
  /// 不同的列表用 `!=` 比较永远为 true。
  static bool _bytesEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// isolate 内部失败（含稳定错误码，回主 isolate 后映射为 [BackupException]）。
class _IsoFailure implements Exception {
  const _IsoFailure(this.code, this.message);

  final BackupErrorCode code;
  final String message;
}

/// isolate 写入结果（错误时仅携带错误码与信息）。
class _IsolateWriteResult {
  const _IsolateWriteResult({
    this.filePath,
    this.byteSize,
    this.errorCode,
    this.errorMessage,
  });

  final String? filePath;
  final int? byteSize;
  final BackupErrorCode? errorCode;
  final String? errorMessage;
}
