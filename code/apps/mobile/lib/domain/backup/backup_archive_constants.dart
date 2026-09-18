/// 备份归档格式常量（BACKUP-002，ADR-0034）。
///
/// `.airecipe-backup` 只是用户可见的文件扩展名，归档内部为标准 ZIP。
/// 归档格式版本、各 Dataset 的 schemaVersion 与 SQLite schemaVersion
/// 三者相互独立，避免备份格式与当前表结构、设备路径和平台实现绑定。
///
/// 版本兼容规则（方案走查细化建议 c）：
/// - 主版本（formatVersion）不兼容：reader 无法理解时必须拒绝。
/// - 次版本向后兼容：reader 仅支持不低于备份的 minimumReaderVersion 时
///   允许继续；optionalFeatures 未声明时保守拒绝。
library;

/// 备份文件扩展名（用户可见）。
const String backupFileExtension = '.airecipe-backup';

/// 归档格式名（manifest 顶层标识，防误认其他 ZIP）。
const String backupFormatName = 'airecipe-backup';

/// 当前备份容器格式版本（主版本）。
const int backupFormatVersion = 1;

/// 能读取本备份的最小 reader 版本。
///
/// 当前与 formatVersion 一致；未来主版本升级时，旧 reader 依据
/// `formatVersion > backupFormatVersion` 或
/// `minimumReaderVersion > backupFormatVersion` 拒绝读取。
const int backupMinimumReaderVersion = 1;

/// 归档内部固定路径（防 Zip Slip 与路径注入，导入端只接受这些路径）。
class BackupArchivePaths {
  BackupArchivePaths._();

  static const String manifestFile = 'manifest.json';
  static const String recipesDataset = 'data/recipes.v1.ndjson';
  static const String categoriesDataset = 'data/categories.v1.ndjson';
  static const String mediaIndexFile = 'media/index.v1.ndjson';
  static const String mediaRoot = 'media/sha256/';

  /// 由 SHA-256 派生内容寻址存储键：`media/sha256/<前两位>/<hash>.<ext>`。
  ///
  /// 同一图片内容在任何设备上得到相同键，天然跨设备稳定并支持去重；
  /// 哈希即媒体资产的稳定 ID（mediaAssetId），不依赖设备绝对路径。
  /// 哈希必须是 64 位十六进制（小写化后校验），否则抛 [FormatException]：
  /// 防止把不可信哈希拼进归档路径造成路径注入（Zip Slip / 目录穿越）。
  static String mediaEntryPath(String sha256, String extension) {
    final normalized = sha256.toLowerCase();
    if (normalized.length != 64 ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(normalized)) {
      throw const FormatException('媒体 SHA-256 非法');
    }
    return '$mediaRoot${normalized.substring(0, 2)}/$normalized.$extension';
  }
}

/// 各 Dataset 在归档中的固定名称（导入端按名称分发）。
class BackupDatasetName {
  BackupDatasetName._();

  static const String recipes = 'recipes';
  static const String categories = 'categories';

  /// 本版本支持的全部 Dataset 名称（未来按需追加，不破坏既有格式）。
  static const Set<String> all = <String>{recipes, categories};
}
