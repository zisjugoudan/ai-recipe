import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../app/ocr_model_catalog.dart';
import '../../application/backend/ai_recipe_backend_facade.dart';
import '../../application/recipe/recipe_library_commands.dart';
import '../../domain/access/app_capability.dart';
import '../../domain/access/app_session.dart';
import '../../domain/recipe/recipe.dart';
import '../../shared/widgets/app_page_header.dart';
import '../../shared/widgets/app_states.dart';
import '../../shared/widgets/pixel_dialogs.dart';
import '../../shared/widgets/pixel_ui.dart';
import '../backup/backup_page.dart';
import '../llm_settings/llm_settings_page.dart';
import '../settings/ocr_settings_page.dart';
import '../settings/privacy_settings_page.dart';
import '../update/update_page.dart';
import 'community_page.dart';
import 'support_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({
    super.key,
    required this.backend,
    required this.session,
    required this.onSignedOut,
    required this.onOpenTrash,
    required this.onDataChanged,
  });

  final AiRecipeBackendFacade backend;
  final AppSession session;
  final ValueChanged<AppSession> onSignedOut;
  final VoidCallback onOpenTrash;

  /// 数据变化通知（生成/清空测试数据后触发菜谱库刷新）。
  final VoidCallback onDataChanged;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late Future<AppCapabilitySnapshot> _capabilities;
  var _signingOut = false;

  /// 开发者工具是否显示：默认隐藏，连续点击头像 6 次后切换显示/隐藏。
  var _devToolsVisible = false;

  /// 头像连击计数（1.5 秒内无新点击则重置）。
  var _avatarTaps = 0;
  Timer? _avatarTapTimer;

  /// 连续点击头像达到 6 次时切换开发者工具显示状态。
  void _onAvatarTap() {
    _avatarTaps++;
    // 重新计时：每次点击重置窗口，避免慢速点击也被累计。
    _avatarTapTimer?.cancel();
    _avatarTapTimer = Timer(const Duration(milliseconds: 1500), () {
      _avatarTaps = 0;
    });
    if (_avatarTaps < 6) return;
    _avatarTaps = 0;
    _avatarTapTimer?.cancel();
    setState(() => _devToolsVisible = !_devToolsVisible);
    _showMessage(_devToolsVisible ? '开发者工具已显示' : '开发者工具已隐藏');
  }

  @override
  void dispose() {
    _avatarTapTimer?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _capabilities = widget.backend.loadCapabilities();
  }

  void _reload() =>
      setState(() => _capabilities = widget.backend.loadCapabilities());

  Future<void> _signOut() async {
    setState(() => _signingOut = true);
    try {
      final session = await widget.backend.returnToWelcome();
      if (!mounted) return;
      widget.onSignedOut(session);
    } on AiRecipeBackendException catch (error) {
      if (!mounted) return;
      setState(() => _signingOut = false);
      _showMessage(error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _signingOut = false);
      _showMessage('退出失败，请稍后重试。');
    }
  }

  Future<void> _openLlmSettings() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => LlmSettingsPage(backend: widget.backend),
      ),
    );
    if (mounted) _reload();
  }

  Future<void> _openOcrSettings() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => OcrSettingsPage(
          backend: widget.backend,
          session: widget.session,
          // 正式 PP-OCRv5 mobile 模型清单（真实下载地址与校验值）。
          installManifest: ocrPpocrV5MobileZhManifest,
        ),
      ),
    );
    if (mounted) _reload();
  }

  Future<void> _openPrivacySettings() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => PrivacySettingsPage(backend: widget.backend),
      ),
    );
    if (mounted) _reload();
  }

  Future<void> _openBackupPage() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => BackupPage(
          backend: widget.backend,
          // 导入写入数据后立即通知 shell 刷新主界面/菜谱库，
          // 避免用户回主界面仍看到旧数据。
          onDataChanged: widget.onDataChanged,
        ),
      ),
    );
    if (mounted) _reload();
  }

  /// 加入交流群（COMMUNITY-001）：展示群二维码海报。
  Future<void> _openCommunityPage() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const CommunityPage()),
    );
  }

  /// 在线更新（UPDATE-001）：检查 Gitee Release 是否有新版本。
  Future<void> _openUpdatePage() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const UpdatePage()),
    );
  }

  Future<void> _openSupportPage() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const SupportPage()),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// 开发者工具：生成 1000 条测试菜谱（菜谱库读取效率测试用）。
  Future<void> _generateTestRecipes() async {
    final confirmed = await showPixelConfirm(
      context: context,
      title: '生成 1000 条测试菜谱？',
      message: '将插入 1000 条标题带"性能测试菜谱"前缀的菜谱，'
          '用于菜谱库读取效率测试。生成需要一点时间。',
      confirmLabel: '开始生成',
    );
    if (confirmed != true || !mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _GenerateTestDataDialog(
        backend: widget.backend,
      ),
    );
    widget.onDataChanged();
  }

  /// 开发者工具：软删除所有标题以"性能测试菜谱"开头的菜谱。
  ///
  /// 用轻量摘要分页（单条 SQL）收集目标 id，再走批量软删除
  /// （一次事务），避免原先"全量加载 + 逐条独立事务"在大量测试
  /// 数据下（如 1000 条）需要上千次查询与提交而明显卡顿。
  Future<void> _clearTestRecipes() async {
    final confirmed = await showPixelConfirm(
      context: context,
      title: '清空测试菜谱？',
      message: '将把标题以"性能测试菜谱"开头的菜谱全部移入回收站。',
      confirmLabel: '清空',
      confirmColor: AppColors.red,
    );
    if (confirmed != true || !mounted) return;
    try {
      // 轻量摘要分页收集匹配 id（keyset pagination，每页单条 SQL）。
      final ids = <String>[];
      RecipeCursor? after;
      while (true) {
        final page = await widget.backend.listRecipeSummaries(
          limit: 1000,
          after: after,
        );
        for (final item in page.items) {
          if (item.title.startsWith('性能测试菜谱')) ids.add(item.id);
        }
        if (!page.hasMore) break;
        after = page.nextCursor;
      }
      if (ids.isNotEmpty) {
        await widget.backend.softDeleteRecipesByIds(ids);
      }
      widget.onDataChanged();
      if (mounted) _showMessage('已清空 ${ids.length} 条测试菜谱。');
    } on AiRecipeBackendException catch (error) {
      if (mounted) _showMessage(error.message);
    } catch (_) {
      if (mounted) _showMessage('清空失败，请稍后重试。');
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final displayName = session.isAuthenticated
        ? (session.displayName ?? '已登录用户')
        : '游客';
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 112),
        children: <Widget>[
          const AppPageHeader(
            eyebrow: '账号与本地数据',
            title: '我的',
            subtitle: '管理本地能力、隐私和账号状态。',
          ),
          const SizedBox(height: 16),
          // 顶部身份卡：CSS .card.card-pad —— 米白背景 + pxc-lg 缺角 +
          // inset 1.5px 描边（不再是浅绿背景）。
          PixelSurface(
            cut: PixelCut.lg,
            color: AppColors.card,
            padding: const EdgeInsets.all(16),
            child: Row(
              children: <Widget>[
                // CSS .avatar：52×52 浅绿块 + pxc-sm 缺角 + inset 描边。
                // 头像显示程序图标（assets/brand/app_icon.png，与启动图标同源）；
                // 连续点击 6 次可切换显示/隐藏开发者工具。
                PixelSurface(
                  cut: PixelCut.sm,
                  elevation: 0,
                  color: AppColors.greenSoft,
                  borderColor: AppColors.greenDeep.withValues(alpha: .4),
                  child: InkWell(
                    key: const Key('profileAvatar'),
                    onTap: _onAvatarTap,
                    child: SizedBox.square(
                      dimension: 52,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Image.asset(
                          'assets/brand/app_icon.png',
                          fit: BoxFit.cover,
                          // 资产加载失败时回退为默认人形图标。
                          errorBuilder: (_, _, _) => Icon(
                            session.isAuthenticated
                                ? Icons.person_rounded
                                : Icons.person_outline_rounded,
                            size: 26,
                            color: AppColors.greenDeep,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        displayName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        session.isAuthenticated ? '云端能力以服务器状态为准' : '本地数据仅保存在本机',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.ink2,
                        ),
                      ),
                    ],
                  ),
                ),
                // CSS .btn.btn-sm.btn-primary：绿色小按钮（原型 UI-011）。
                FilledButton(
                  key: const Key('profileLoginButton'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  onPressed: () => _showMessage(
                    session.isAuthenticated
                        ? '登录账号能力暂未接入，可继续使用本地功能。'
                        : '登录暂未开放，可先使用游客模式。',
                  ),
                  child: Text(session.isAuthenticated ? '已登录' : '登录 / 注册'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // 能力配置：只有分区标题，下面直接是带边框的平直条目
          // （CSS .sec-title + .row-item，无“当前能力”标题卡片）。
          const AppSectionTitle(title: '能力配置'),
          const SizedBox(height: 9),
          FutureBuilder<AppCapabilitySnapshot>(
            future: _capabilities,
            builder: (context, state) {
              if (state.hasError) {
                return AppErrorState(
                  message: '能力状态暂时无法读取。',
                  onRetry: _reload,
                );
              }
              final snapshot = state.data;
              return Column(
                children: <Widget>[
                  PixelRowTile(
                    key: const Key('openLlmSettingsTile'),
                    icon: Icons.key_rounded,
                    title: 'LLM 模型',
                    subtitle: snapshot == null
                        ? '正在检查…'
                        : snapshot
                              .decisionFor(AppCapability.customLlm)
                              .isAvailable
                          ? 'OpenAI-compatible · 已连接可用服务'
                          : 'OpenAI-compatible · 尚未配置可用服务',
                    trailing: snapshot == null
                        ? const PixelBadge(label: '检查中')
                        : PixelBadge(
                            label: snapshot
                                    .decisionFor(AppCapability.customLlm)
                                    .isAvailable
                                ? '已配置'
                                : '未配置',
                            tone: snapshot
                                    .decisionFor(AppCapability.customLlm)
                                    .isAvailable
                                ? PixelNoticeTone.green
                                : PixelNoticeTone.blue,
                          ),
                    onTap: _openLlmSettings,
                  ),
                  const SizedBox(height: 10),
                  PixelRowTile(
                    key: const Key('openOcrSettingsTile'),
                    icon: Icons.document_scanner_outlined,
                    title: '识图引擎',
                    subtitle: snapshot == null
                        ? '正在检查…'
                        : snapshot
                                  .decisionFor(AppCapability.localOcr)
                                  .isAvailable
                              ? '本地识别能力已就绪'
                              : '本地识别能力待启用',
                    trailing: snapshot == null
                        ? const PixelBadge(label: '检查中')
                        : PixelBadge(
                            label: snapshot
                                    .decisionFor(AppCapability.localOcr)
                                    .isAvailable
                                ? '已就绪'
                                : '待启用',
                            tone: snapshot
                                    .decisionFor(AppCapability.localOcr)
                                    .isAvailable
                                ? PixelNoticeTone.green
                                : PixelNoticeTone.amber,
                          ),
                    onTap: _openOcrSettings,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          const AppSectionTitle(title: '隐私与数据'),
          const SizedBox(height: 9),
          PixelRowTile(
            key: const Key('openPrivacySettingsTile'),
            icon: Icons.shield_outlined,
            title: '隐私与上传设置',
            subtitle: '分别控制文本、图片和视频上传',
            trailing: const PixelBadge(label: '本地'),
            onTap: _openPrivacySettings,
          ),
          const SizedBox(height: 10),
          PixelRowTile(
            key: const Key('openTrashTile'),
            icon: Icons.delete_outline_rounded,
            iconColor: AppColors.red,
            iconBackground: AppColors.redSoft,
            title: '回收站',
            subtitle: '恢复或永久删除菜谱',
            onTap: widget.onOpenTrash,
          ),
          const SizedBox(height: 10),
          PixelRowTile(
            key: const Key('openBackupTile'),
            icon: Icons.archive_outlined,
            title: '数据与存储',
            subtitle: '创建全量备份（.airecipe-backup）',
            onTap: _openBackupPage,
          ),
          const SizedBox(height: 10),
          // 在线更新（UPDATE-001）：检查 Gitee Release 新版本。
          PixelRowTile(
            key: const Key('openUpdateTile'),
            icon: Icons.system_update_alt_rounded,
            title: '检查更新',
            subtitle: '查看当前版本与最新版本',
            onTap: _openUpdatePage,
          ),
          const SizedBox(height: 10),
          // 「支持我们」赞赏入口：感谢语 + 微信/支付宝收款码。
          PixelRowTile(
            key: const Key('openSupportTile'),
            icon: Icons.favorite_border_rounded,
            iconColor: AppColors.red,
            iconBackground: AppColors.redSoft,
            title: '支持我们',
            subtitle: '扫码赞赏，感谢你的鼓励',
            onTap: _openSupportPage,
          ),
          const SizedBox(height: 10),
          // 「加入交流群」入口（COMMUNITY-001）：群二维码海报 + 进群引导。
          PixelRowTile(
            key: const Key('openCommunityTile'),
            icon: Icons.forum_outlined,
            iconColor: AppColors.greenDeep,
            iconBackground: AppColors.greenSofter,
            title: '加入交流群',
            subtitle: '交流菜谱、反馈建议、获取新版本动态',
            onTap: _openCommunityPage,
          ),
          const SizedBox(height: 20),
          // 开发者工具：默认隐藏，连续点击头像 6 次后切换显示/隐藏。
          if (_devToolsVisible) ...[
            const AppSectionTitle(title: '开发者工具'),
            const SizedBox(height: 9),
            PixelRowTile(
              key: const Key('generateTestRecipesTile'),
              icon: Icons.science_outlined,
              title: '生成 1000 条测试菜谱',
              subtitle: '用于菜谱库读取效率测试（标题带"性能测试"前缀）',
              onTap: _generateTestRecipes,
            ),
            const SizedBox(height: 10),
            PixelRowTile(
              key: const Key('clearTestRecipesTile'),
              icon: Icons.delete_sweep_outlined,
              iconColor: AppColors.red,
              iconBackground: AppColors.redSoft,
              title: '清空测试菜谱',
              subtitle: '软删除标题以"性能测试菜谱"开头的菜谱',
              onTap: _clearTestRecipes,
            ),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 18),
          OutlinedButton.icon(
            key: const Key('profileSessionActionButton'),
            onPressed: _signingOut ? null : _signOut,
            icon: _signingOut
                ? const PixelLoader(size: 5)
                : const Icon(Icons.logout_rounded),
            label: Text(session.isAuthenticated ? '退出登录' : '返回欢迎页'),
          ),
        ],
      ),
    );
  }
}

/// 生成 1000 条测试菜谱的进度弹窗：逐条插入并实时显示进度。
class _GenerateTestDataDialog extends StatefulWidget {
  const _GenerateTestDataDialog({required this.backend});

  final AiRecipeBackendFacade backend;

  @override
  State<_GenerateTestDataDialog> createState() =>
      _GenerateTestDataDialogState();
}

class _GenerateTestDataDialogState extends State<_GenerateTestDataDialog> {
  static const int _total = 1000;
  var _done = 0;
  String? _error;
  var _finished = false;
  var _cancelled = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void dispose() {
    _cancelled = true;
    super.dispose();
  }

  Future<void> _run() async {
    try {
      for (var index = 0; index < _total; index++) {
        if (_cancelled) return;
        await widget.backend.createRecipe(_testDraft(index));
        if (index % 50 == 49 && mounted) {
          setState(() => _done = index + 1);
        }
      }
      if (mounted) {
        setState(() {
          _finished = true;
          _done = _total;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = '生成测试数据失败，请稍后重试。');
      }
    }
  }

  /// 构造一条 mock 菜谱（偶数条收藏，便于后续过滤测试）。
  static RecipeDraftInput _testDraft(int index) {
    return RecipeDraftInput(
      title: '性能测试菜谱 $index',
      description: '用于菜谱库读取效率测试的第 $index 道菜谱',
      notes: '开发者工具生成的测试数据',
      favorite: index.isEven,
      status: RecipeStatus.published,
      categoryIds: const <String>[],
      tags: const <String>['perf'],
      ingredients: <RecipeIngredientInput>[
        RecipeIngredientInput(
          name: '食材$index',
          quantity: '$index',
          unit: '克',
          groupName: '主料',
          preparation: '洗净',
          substitutes: const <String>[],
        ),
      ],
      steps: const <RecipeStepInput>[
        RecipeStepInput(
          description: '步骤一',
          durationSeconds: 60,
          heatLevel: '中火',
          cookware: '炒锅',
        ),
        RecipeStepInput(
          description: '步骤二',
          durationSeconds: 120,
          heatLevel: '小火',
          cookware: '炒锅',
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
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
            Text(
              _finished ? '生成完成' : '正在生成测试菜谱',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 8),
            if (_error != null)
              Text(
                _error!,
                style: const TextStyle(fontSize: 12, color: AppColors.red),
              )
            else if (_finished)
              Text(
                '已插入 $_total 条菜谱。',
                style: const TextStyle(fontSize: 12, color: AppColors.ink2),
              )
            else ...<Widget>[
              Text(
                '已生成 $_done / $_total',
                style: const TextStyle(fontSize: 12, color: AppColors.ink2),
              ),
              const SizedBox(height: 8),
              PixelProgressBar(value: _done / _total),
            ],
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                FilledButton(
                  onPressed: _finished || _error != null
                      ? () => Navigator.of(context).pop()
                      : null,
                  child: Text(_finished || _error != null ? '完成' : '生成中…'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
