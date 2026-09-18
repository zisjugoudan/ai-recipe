import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../application/backend/ai_recipe_backend_facade.dart';
import '../../application/settings/local_app_settings_use_cases.dart';
import '../../domain/settings/local_app_settings.dart';
import '../../shared/widgets/app_states.dart';
import '../../shared/widgets/pixel_dialogs.dart';
import '../../shared/widgets/pixel_ui.dart';

class PrivacySettingsPage extends StatefulWidget {
  const PrivacySettingsPage({super.key, required this.backend});

  final AiRecipeBackendFacade backend;

  @override
  State<PrivacySettingsPage> createState() => _PrivacySettingsPageState();
}

class _PrivacySettingsPageState extends State<PrivacySettingsPage> {
  LocalAppSettings? _settings;
  bool _loading = true;
  bool _busy = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      final settings = await widget.backend.loadLocalSettings();
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = '隐私设置暂时无法读取，请稍后重试。';
      });
    }
  }

  Future<void> _update({
    bool? recordRecipeHistory,
    bool? allowTextUpload,
    bool? allowImageUpload,
    bool? allowVideoUpload,
  }) async {
    final current = _settings;
    if (current == null || _busy) return;
    final input = LocalAppSettingsInput(
      recordRecipeHistory: recordRecipeHistory ?? current.recordRecipeHistory,
      allowTextUpload: allowTextUpload ?? current.allowTextUpload,
      allowImageUpload: allowImageUpload ?? current.allowImageUpload,
      allowVideoUpload: allowVideoUpload ?? current.allowVideoUpload,
    );
    setState(() {
      _busy = true;
      _errorMessage = null;
    });
    try {
      final saved = await widget.backend.saveLocalSettings(input);
      if (!mounted) return;
      setState(() => _settings = saved);
      _showMessage('设置已保存到本机。');
    } on AiRecipeBackendException catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorMessage = '隐私设置暂时无法保存，请稍后重试。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clearHistory() async {
    final confirmed = await showPixelConfirm(
      context: context,
      title: '清空最近浏览？',
      message: '只会删除本机的最近浏览记录，不会删除菜谱。',
      confirmLabel: '清空',
      confirmColor: AppColors.red,
      confirmKey: const Key('confirmClearHistoryButton'),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _errorMessage = null;
    });
    try {
      await widget.backend.clearRecipeHistory();
      if (!mounted) return;
      _showMessage('最近浏览记录已清空。');
    } on AiRecipeBackendException catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorMessage = '最近浏览记录暂时无法清空。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    return Scaffold(
      appBar: const PixelPageAppBar(
        title: '隐私与上传权限',
      ),
      body: _loading
          ? const AppLoadingState(label: '正在读取本机隐私设置…')
          : settings == null
          ? Padding(
              padding: const EdgeInsets.all(18),
              child: AppErrorState(
                message: _errorMessage ?? '隐私设置暂时无法读取。',
                onRetry: _load,
                retryLabel: '\u91cd\u8bd5',
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
              children: <Widget>[
                const PixelNotice(
                  title: '默认留在本机',
                  message:
                      '这些开关只表示是否允许应用在你主动操作时上传对应内容，不代表云解析、云 OCR 或云同步已经接入。关闭后，本地菜谱与本地 AI 仍可继续使用。',
                  tone: PixelNoticeTone.green,
                  icon: Icons.shield_outlined,
                ),
                if (_errorMessage != null) ...<Widget>[
                  const SizedBox(height: 12),
                  PixelNotice(
                    key: const Key('privacyErrorMessage'),
                    title: '设置未保存',
                    message: _errorMessage,
                    tone: PixelNoticeTone.red,
                    icon: Icons.error_outline_rounded,
                  ),
                ],
                const SizedBox(height: 16),
                const PxLabel('本地历史'),
                const SizedBox(height: 8),
                PixelSurface(
                  padding: EdgeInsets.zero,
                  child: SwitchListTile(
                    key: const Key('recordRecipeHistorySwitch'),
                    value: settings.recordRecipeHistory,
                    onChanged: _busy
                        ? null
                        : (value) => _update(recordRecipeHistory: value),
                    title: const Text(
                      '记录最近浏览',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    subtitle: Text(
                      settings.recordRecipeHistory
                          ? '仅保存在本机，用于首页继续浏览。'
                          : '已关闭；现有浏览历史会被清空。',
                    ),
                    secondary: const Icon(
                      Icons.history_rounded,
                      color: AppColors.greenDeep,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const PxLabel('上传权限'),
                const SizedBox(height: 8),
                _PermissionSwitch(
                  switchKey: const Key('allowTextUploadSwitch'),
                  value: settings.allowTextUpload,
                  enabled: !_busy,
                  icon: Icons.text_snippet_outlined,
                  title: '允许上传文本',
                  enabledDescription: '已允许：仅用于你主动选择的云端 AI 请求。',
                  disabledDescription: '已禁止：文本不会发送到平台云端 AI。',
                  onChanged: (value) => _update(allowTextUpload: value),
                ),
                const SizedBox(height: 8),
                _PermissionSwitch(
                  switchKey: const Key('allowImageUploadSwitch'),
                  value: settings.allowImageUpload,
                  enabled: !_busy,
                  icon: Icons.image_outlined,
                  title: '允许上传图片',
                  enabledDescription: '已允许：未来可用于你主动发起的云 OCR 或图片分析。',
                  disabledDescription: '已禁止：图片保持在本机，本地 OCR 不受影响。',
                  onChanged: (value) => _update(allowImageUpload: value),
                ),
                const SizedBox(height: 8),
                _PermissionSwitch(
                  switchKey: const Key('allowVideoUploadSwitch'),
                  value: settings.allowVideoUpload,
                  enabled: !_busy,
                  icon: Icons.video_file_outlined,
                  title: '允许上传视频',
                  enabledDescription: '已允许：未来可用于你主动发起的云端媒体处理。',
                  disabledDescription: '已禁止：视频不会发送到服务器。',
                  onChanged: (value) => _update(allowVideoUpload: value),
                ),
                const SizedBox(height: 16),
                const PxLabel('本地数据操作'),
                const SizedBox(height: 8),
                PixelSurface(
                  cut: 5,
                  color: AppColors.redSoft,
                  borderColor: AppColors.red.withValues(alpha: .42),
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      const Text(
                        '清空最近浏览记录',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color: AppColors.red,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        '不会删除菜谱、分类、导入草稿或模型配置。',
                        style: TextStyle(color: AppColors.ink2),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        key: const Key('clearRecipeHistoryButton'),
                        onPressed: _busy ? null : _clearHistory,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.red,
                        ),
                        icon: const Icon(Icons.delete_sweep_outlined),
                        label: const Text('清空最近浏览记录'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _PermissionSwitch extends StatelessWidget {
  const _PermissionSwitch({
    required this.switchKey,
    required this.value,
    required this.enabled,
    required this.icon,
    required this.title,
    required this.enabledDescription,
    required this.disabledDescription,
    required this.onChanged,
  });

  final Key switchKey;
  final bool value;
  final bool enabled;
  final IconData icon;
  final String title;
  final String enabledDescription;
  final String disabledDescription;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return PixelSurface(
      padding: EdgeInsets.zero,
      color: value ? AppColors.card : AppColors.card2,
      child: SwitchListTile(
        key: switchKey,
        value: value,
        onChanged: enabled ? onChanged : null,
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
        subtitle: Text(value ? enabledDescription : disabledDescription),
        secondary: Icon(
          icon,
          color: value ? AppColors.greenDeep : AppColors.ink3,
        ),
      ),
    );
  }
}
