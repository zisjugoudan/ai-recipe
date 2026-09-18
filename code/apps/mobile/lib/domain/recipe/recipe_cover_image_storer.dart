/// 菜谱封面图片落盘接口。
///
/// 把来源图片持久化到菜谱私有封面目录，供导入流程把公开内容（小红书/抖音）
/// 的配图下载到本地后作为菜谱封面使用；同时负责删除单个文件与整组目录。
abstract interface class RecipeCoverImageStorer {
  /// 复制来源图片到容器目录，返回目标绝对路径。
  Future<String> copyIn({
    required String sourcePath,
    required String containerId,
    required int index,
  });

  /// 删除单个封面文件；文件不存在或删除失败时静默忽略。
  Future<void> deleteFile(String imagePath);

  /// 删除某个容器（菜谱）的全部封面文件；不存在时静默忽略。
  Future<void> deleteContainer(String containerId);
}
