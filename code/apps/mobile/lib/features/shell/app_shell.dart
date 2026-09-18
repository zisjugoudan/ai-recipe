import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../application/backend/ai_recipe_backend_facade.dart';
import '../../domain/access/app_session.dart';
import '../../domain/importing/import_task.dart';
import '../../domain/recipe/recipe.dart';
import '../../shared/widgets/pixel_ui.dart';
import '../home/home_page.dart';
import '../fridge/fridge_page.dart';
import '../importing/add_recipe_page.dart';
import '../importing/import_image_picker.dart';
import '../importing/import_progress_page.dart';
import '../importing/import_tasks_page.dart';
import '../library/recipe_library_page.dart';
import '../profile/profile_page.dart';
import '../recipe/recipe_detail_page.dart';
import '../recipe/recipe_edit_page.dart';
import '../trash/recipe_trash_page.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.backend,
    required this.session,
    required this.onSignedOut,
  });

  final AiRecipeBackendFacade backend;
  final AppSession session;
  final ValueChanged<AppSession> onSignedOut;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  var _selectedIndex = 0;
  var _refreshToken = 0;
  final _imagePicker = DeviceImportImagePicker();

  void _select(int index) => setState(() => _selectedIndex = index);
  void _dataChanged() => setState(() => _refreshToken += 1);

  Future<void> _openRecipe(Recipe recipe) async {
    await _openRecipeById(recipe.id);
  }

  /// 按 id 打开菜谱详情（列表页/首页只持有摘要，详情页内部按需加载完整聚合）。
  Future<void> _openRecipeById(String recipeId) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (context) => RecipeDetailPage(
          backend: widget.backend,
          recipeId: recipeId,
          onDataChanged: _dataChanged,
        ),
      ),
    );
    if (changed == true && mounted) _dataChanged();
  }

  Future<void> _openRecipeEditor() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (context) => RecipeEditPage(backend: widget.backend),
      ),
    );
    if (changed == true && mounted) {
      _dataChanged();
      _select(1);
    }
  }

  Future<void> _openImportTask(
    ImportTask task, {
    PickedImportImage? initialImage,
    String? initialText,
  }) async {
    final recipe = await Navigator.of(context).push<Recipe>(
      MaterialPageRoute<Recipe>(
        builder: (context) => ImportProgressPage(
          backend: widget.backend,
          taskId: task.id,
          onDataChanged: _dataChanged,
          onOpenManualEditor: _openRecipeEditor,
          initialImage: initialImage,
          initialText: initialText,
        ),
      ),
    );
    if (!mounted) return;
    _dataChanged();
    if (recipe != null) {
      _select(1);
      await _openRecipe(recipe);
    }
  }

  /// 打开未完成导入任务列表（IMPORT-009）。
  Future<void> _openImportTasks() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => ImportTasksPage(
          backend: widget.backend,
          onDataChanged: _dataChanged,
          onOpenImportTask: _openImportTask,
        ),
      ),
    );
    if (mounted) _dataChanged();
  }

  /// 快速导入：粘贴链接（打开添加页链接 tab）。
  Future<void> _openLinkImport() => _openAddRecipe();

  /// 快速导入：剪贴板（弹出文本输入框，输入/粘贴正文后由 AI 整理成菜谱）。
  Future<void> _openClipboardImport() async {
    final text = await _promptPasteText();
    if (text == null || text.trim().isEmpty) return;
    try {
      final task = await widget.backend.createLocalTextImportTask();
      if (!mounted) return;
      _dataChanged();
      await _openImportTask(task, initialText: text);
    } on AiRecipeBackendException catch (error) {
      _showMessage(error.message);
    } catch (_) {
      _showMessage('文本暂时无法处理，请重新输入。');
    }
  }

  /// 弹出像素风文本输入框：返回用户输入的正文（取消返回 null）。
  ///
  /// 用独立 StatefulWidget 管理输入 controller，保证其与弹窗生命周期一致，
  /// 避免在弹窗退出动画期间 dispose 导致 overlay 树断言失败。
  Future<String?> _promptPasteText() {
    return showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (_) => const _PasteTextDialog(),
    );
  }

  /// 快速导入：拍照选图（本地 OCR 图片导入，IMPORT-009）。
  Future<void> _openImageImport() async {
    final PickedImportImage image;
    try {
      final picked = await _imagePicker.pickImage();
      if (picked == null) return;
      image = picked;
    } on ImportImagePickerException catch (error) {
      _showMessage(error.message);
      return;
    }
    try {
      final task = await widget.backend.createLocalImageImportTask();
      if (!mounted) return;
      _dataChanged();
      await _openImportTask(task, initialImage: image);
    } on AiRecipeBackendException catch (error) {
      _showMessage(error.message);
    } catch (_) {
      _showMessage('图片暂时无法处理，请重新选择。');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _openAddRecipe({String initialLink = ''}) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (routeContext) => AddRecipePage(
          backend: widget.backend,
          onDataChanged: _dataChanged,
          onOpenLibrary: () {
            Navigator.of(routeContext).pop();
            _select(1);
          },
          onOpenManualEditor: _openRecipeEditor,
          onOpenImportTask: _openImportTask,
          onOpenImportTasks: _openImportTasks,
          initialLink: initialLink,
        ),
      ),
    );
    if (mounted) _dataChanged();
  }

  Future<void> _openTrash() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => RecipeTrashPage(
          backend: widget.backend,
          onDataChanged: _dataChanged,
        ),
      ),
    );
    if (mounted) _dataChanged();
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      HomePage(
        backend: widget.backend,
        refreshToken: _refreshToken,
        onOpenLibrary: () => _select(1),
        onOpenImportTask: _openImportTask,
        onOpenImportTasks: _openImportTasks,
        onQuickLinkImport: _openLinkImport,
        onQuickClipboardImport: _openClipboardImport,
        onQuickImageImport: _openImageImport,
        onQuickManualCreate: _openRecipeEditor,
        onOpenRecipe: _openRecipeById,
      ),
      RecipeLibraryPage(
        backend: widget.backend,
        refreshToken: _refreshToken,
        onAddRecipe: _openAddRecipe,
        onOpenRecipeId: _openRecipeById,
        onDataChanged: _dataChanged,
        onOpenTrash: _openTrash,
      ),
      FridgePage(
        backend: widget.backend,
        refreshToken: _refreshToken,
        onDataChanged: _dataChanged,
        onOpenRecipe: _openRecipe,
      ),
      ProfilePage(
        backend: widget.backend,
        session: widget.session,
        onSignedOut: widget.onSignedOut,
        onOpenTrash: _openTrash,
        onDataChanged: _dataChanged,
      ),
    ];
    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: pages),
      // 全局「添加菜谱」FAB 只在首页(0)与菜谱库(1)显示；冰箱与我的页不显示，
      // 避免与各自的操作入口（添加食材等）争抢右下角（项目负责人要求）。
      floatingActionButton: _selectedIndex <= 1
          ? FloatingActionButton(
              key: const Key('addRecipeFab'),
              tooltip: '添加菜谱',
              onPressed: _openAddRecipe,
              child: const Icon(Icons.add_rounded, size: 30),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      // 1:1 复刻 prototype.css .tabbar：虚线分隔 + 等分 tab + 选中绿底描边。
      // 底部导航图标改用设计素材（HOME-001），nav.png 已切分为
      // inactive/active 两套并按统一主题色处理。
      bottomNavigationBar: PixelTabBar(
        selectedIndex: _selectedIndex,
        onSelect: _select,
        tabs: const <PixelTab>[
          (
            key: 'homeTab',
            icon: _NavIcon('assets/icon/home/nav/home_inactive.png'),
            selectedIcon: _NavIcon('assets/icon/home/nav/home_active.png'),
            label: '首页',
          ),
          (
            key: 'libraryTab',
            icon: _NavIcon('assets/icon/home/nav/library_inactive.png'),
            selectedIcon: _NavIcon('assets/icon/home/nav/library_active.png'),
            label: '菜谱库',
          ),
          (
            key: 'fridgeTab',
            icon: _NavIcon('assets/icon/home/nav/fridge_inactive.png'),
            selectedIcon: _NavIcon('assets/icon/home/nav/fridge_active.png'),
            label: '冰箱',
          ),
          (
            key: 'profileTab',
            icon: _NavIcon('assets/icon/home/nav/profile_inactive.png'),
            selectedIcon: _NavIcon('assets/icon/home/nav/profile_active.png'),
            label: '我的',
          ),
        ],
      ),
    );
  }
}

/// 底部导航 asset 图标：统一 21×21 尺寸，加载失败回退空容器。
class _NavIcon extends StatelessWidget {
  const _NavIcon(this.asset);

  final String asset;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      asset,
      width: 21,
      height: 21,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
    );
  }
}

/// 像素风文本输入弹窗：粘贴/输入正文后由 AI 整理成菜谱。
///
/// 输入 controller 由本 State 持有并在 dispose 中释放，与弹窗生命周期一致，
/// 避免在退出动画期间释放 controller 导致 overlay 树断言失败。
class _PasteTextDialog extends StatefulWidget {
  const _PasteTextDialog();

  @override
  State<_PasteTextDialog> createState() => _PasteTextDialogState();
}

class _PasteTextDialogState extends State<_PasteTextDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 弹窗容器用 PixelSurface（切角 + 墨色描边 + 硬投影），标题/输入框/
    // 按钮均沿用全局像素主题，与整个 UI 风格一致。
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: PixelSurface(
        cut: PixelCut.lg,
        elevation: 2,
        color: AppColors.card,
        borderColor: AppColors.ink,
        borderWidth: 1.5,
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Text(
              '粘贴文本导入',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              '粘贴或输入菜谱正文，AI 将整理成结构化菜谱',
              style: TextStyle(fontSize: 11, color: AppColors.ink3),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('pasteTextImportField'),
              controller: _controller,
              autofocus: true,
              minLines: 4,
              maxLines: 8,
              decoration: const InputDecoration(
                hintText: '例如：番茄炒蛋的做法…',
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () =>
                      Navigator.of(context).pop(_controller.text.trim()),
                  child: const Text('开始导入'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
