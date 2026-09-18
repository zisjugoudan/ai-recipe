import '../../domain/importing/import_cancellation_token.dart';
import '../../domain/ocr/ocr_models.dart';
import '../../domain/ocr/ocr_remote_image_stager.dart';

/// 任务级图片缓存（解决方案 P0-1：消除重复下载）。
///
/// 一次导入中，同一张远程图片只需要下载一次：多模态识别阶段下载后，
/// 封面保存阶段复用同一份临时文件，避免对同一 URL 二次下载。
///
/// 实现上包装一个底层 [OcrRemoteImageStager]，按“升级后的 https URL”做缓存：
/// - 首次命中：委托底层下载并持有文件，返回一个 dispose 为 no-op 的副本；
/// - 重复命中：直接返回指向同一文件的 dispose 为 no-op 的副本；
/// - 本地文件（无 remoteUrl）：不缓存，直接透传底层。
///
/// 所有缓存文件的生命周期由 [disposeAll] 统一管理，通常由处理器链在执行
/// 结束后（finally）调用一次，彻底释放临时文件。
class TaskScopedImageCache implements OcrRemoteImageStager {
  TaskScopedImageCache(this._inner);

  final OcrRemoteImageStager _inner;

  /// 已下载的共享文件，key 为规范化后的 remoteUrl。
  final Map<String, StagedOcrImage> _shared = <String, StagedOcrImage>{};

  /// 记录下载顺序，用于 [disposeAll] 时按序清理。
  final List<String> _order = <String>[];

  @override
  Future<StagedOcrImage> stage(
    OcrImageInput input, {
    ImportCancellationToken? cancellationToken,
  }) async {
    final remoteUrl = input.remoteUrl;
    // 本地文件（浏览器会话已下载）不重复下载，直接透传底层进一步校验。
    if (remoteUrl == null || remoteUrl.isEmpty) {
      return _inner.stage(input, cancellationToken: cancellationToken);
    }
    final key = remoteUrl;
    final shared = _shared[key];
    if (shared != null) {
      // 命中缓存：返回同一文件的 no-op 副本，不重复下载、不提前删除。
      return _copy(shared);
    }
    // 首次下载：底层负责下载与校验，缓存持有真实生命周期。
    final staged = await _inner.stage(
      input,
      cancellationToken: cancellationToken,
    );
    _shared[key] = staged;
    _order.add(key);
    return _copy(staged);
  }

  /// 返回一个指向同一文件的副本；其 dispose 为 no-op，避免消费方提前删除
  /// 共享文件，真正的清理统一由 [disposeAll] 完成。
  StagedOcrImage _copy(StagedOcrImage shared) {
    return StagedOcrImage(
      input: shared.input,
      byteLength: shared.byteLength,
      width: shared.width,
      height: shared.height,
      dispose: () async {},
    );
  }

  /// 释放本次任务缓存的所有临时文件。处理器链执行结束后调用一次即可。
  Future<void> disposeAll() async {
    for (final key in _order) {
      final staged = _shared[key];
      if (staged != null) {
        await staged.dispose();
      }
    }
    _shared.clear();
    _order.clear();
  }
}