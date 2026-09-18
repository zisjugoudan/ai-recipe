import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../application/backend/ai_recipe_backend_facade.dart';
import '../../domain/importing/import_task.dart';
import '../../shared/widgets/app_page_header.dart';
import '../../shared/widgets/pixel_ui.dart';

class AddRecipePage extends StatefulWidget {
  const AddRecipePage({
    super.key,
    required this.backend,
    required this.onDataChanged,
    required this.onOpenLibrary,
    required this.onOpenManualEditor,
    required this.onOpenImportTask,
    this.onOpenImportTasks,
    this.initialLink = '',
  });

  final AiRecipeBackendFacade backend;
  final VoidCallback onDataChanged;
  final VoidCallback onOpenLibrary;
  final VoidCallback onOpenManualEditor;
  final Future<void> Function(ImportTask task) onOpenImportTask;
  /// 批量创建成功（≥2 个任务）后打开未完成导入列表统一管理。
  final VoidCallback? onOpenImportTasks;
  /// 剪贴板等入口带入的初始链接文本。
  final String initialLink;

  @override
  State<AddRecipePage> createState() => _AddRecipePageState();
}

class _AddRecipePageState extends State<AddRecipePage> {
  late final TextEditingController _linkController;
  var _mode = 0;
  var _busy = false;
  String? _successMessage;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _linkController = TextEditingController(text: widget.initialLink);
  }

  @override
  void dispose() {
    _linkController.dispose();
    super.dispose();
  }

  /// 从输入中提取全部 http(s) 链接（支持一行一个或多个链接批量导入）。
  static List<String> _extractLinks(String raw) {
    final matches = RegExp(r'https?://[^\s，。；,;]+').allMatches(raw);
    return matches.map((m) => m.group(0)!.trim()).toList(growable: false);
  }

  Future<void> _createImportTasks() async {
    final links = _extractLinks(_linkController.text);
    if (links.isEmpty) {
      setState(() => _errorMessage = '请粘贴至少一个公开内容链接。');
      return;
    }
    setState(() {
      _busy = true;
      _errorMessage = null;
      _successMessage = null;
    });
    final tasks = <ImportTask>[];
    final failed = <String>[];
    // 批量创建：单个失败不中断其余链接，最后统一提示。
    for (final link in links) {
      try {
        tasks.add(await widget.backend.createImportTask(link));
      } on AiRecipeBackendException catch (error) {
        failed.add(error.message);
      } catch (_) {
        failed.add('链接暂时无法创建任务。');
      }
      if (!mounted) return;
    }
    if (tasks.isEmpty) {
      setState(() {
        _busy = false;
        _errorMessage = failed.first;
      });
      return;
    }
    _linkController.clear();
    widget.onDataChanged();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _successMessage = failed.isEmpty
          ? '已创建 ${tasks.length} 个导入任务。'
          : '已创建 ${tasks.length} 个，${failed.length} 个失败（${failed.first}）。';
    });
    if (tasks.length == 1) {
      await widget.onOpenImportTask(tasks.first);
    } else {
      // 多个任务：打开未完成导入列表统一查看与管理。
      widget.onOpenImportTasks?.call();
    }
  }

  void _submit() {
    if (_mode == 0) {
      _createImportTasks();
    } else {
      widget.onOpenManualEditor();
    }
  }

  void _selectMode(int mode) {
    if (_busy) return;
    setState(() {
      _mode = mode;
      _errorMessage = null;
      _successMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const PixelPageAppBar(title: '添加菜谱', eyebrow: '新建菜谱'),
      body: SafeArea(
        top: false,
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
          children: <Widget>[
            const AppPageHeader(
              eyebrow: 'AI 菜谱导入',
              title: '把灵感收进菜谱库',
              subtitle: '公开链接交给 AI 整理，也可以从零完整记录。',
            ),
            const SizedBox(height: 16),
            _ImportModeTabs(
              selected: _mode,
              enabled: !_busy,
              onSelected: _selectMode,
            ),
            const SizedBox(height: 14),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: _mode == 0
                  ? _LinkImportForm(controller: _linkController)
                  : const _ManualRecipeEntry(),
            ),
            if (_errorMessage != null || _successMessage != null) ...<Widget>[
              const SizedBox(height: 12),
              PixelNotice(
                title: _errorMessage == null ? '操作成功' : '暂时无法继续',
                message: _errorMessage ?? _successMessage!,
                icon: _errorMessage == null
                    ? Icons.check_rounded
                    : Icons.warning_amber_rounded,
                tone: _errorMessage == null
                    ? PixelNoticeTone.green
                    : PixelNoticeTone.red,
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const Key('addRecipePrimaryButton'),
              onPressed: _busy ? null : _submit,
              icon: _busy
                  ? const PixelLoader(size: 5, color: Colors.white)
                  : Icon(
                      _mode == 0
                          ? Icons.play_arrow_rounded
                          : Icons.edit_rounded,
                    ),
              label: Text(_mode == 0 ? '开始解析' : '打开完整编辑器'),
            ),
            const SizedBox(height: 9),
            OutlinedButton.icon(
              onPressed: widget.onOpenLibrary,
              icon: const Icon(Icons.menu_book_outlined),
              label: const Text('查看菜谱库'),
            ),
            // const SizedBox(height: 16),
            // const PixelNotice(
            //   title: '只导入你有权使用的公开内容',
            //   message: '剪贴板内容只在你主动粘贴后使用；AI 结果会先进入确认页，不会直接保存。',
            //   icon: Icons.shield_outlined,
            //   tone: PixelNoticeTone.amber,
            // ),
          ],
        ),
      ),
    );
  }
}

class _ImportModeTabs extends StatelessWidget {
  const _ImportModeTabs({
    required this.selected,
    required this.enabled,
    required this.onSelected,
  });

  final int selected;
  final bool enabled;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return PixelSurface(
      cut: 5,
      elevation: 0,
      color: AppColors.card2,
      padding: const EdgeInsets.all(4),
      child: Row(
        children: <Widget>[
          Expanded(
            child: _ModeButton(
              label: '链接导入',
              icon: Icons.link_rounded,
              selected: selected == 0,
              onTap: enabled ? () => onSelected(0) : null,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _ModeButton(
              label: '手动创建',
              icon: Icons.edit_note_rounded,
              selected: selected == 1,
              onTap: enabled ? () => onSelected(1) : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.green : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(
                icon,
                size: 17,
                color: selected ? Colors.white : AppColors.ink2,
              ),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: selected ? Colors.white : AppColors.ink2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LinkImportForm extends StatelessWidget {
  const _LinkImportForm({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return PixelSurface(
      key: const ValueKey('link-import'),
      cut: 7,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Expanded(
                child: Text(
                  '粘贴公开内容链接',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                ),
              ),
              const PixelBadge(
                label: '无需登录',
                icon: Icons.lock_open_rounded,
                tone: PixelNoticeTone.green,
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            '当前支持识别小红书和抖音公开链接。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 14),
          const PixelFieldLabel('链接', required: true),
          TextField(
            key: const Key('importLinkField'),
            controller: controller,
            decoration: const InputDecoration(
              hintText: 'https://…',
              prefixIcon: Icon(Icons.link_rounded),
            ),
            keyboardType: TextInputType.url,
            autocorrect: false,
            minLines: 2,
            maxLines: 3,
          ),
          const SizedBox(height: 14),
          // const PxLabel('本次将使用'),
          // const SizedBox(height: 9),
          // const _CapabilityLine(
          //   icon: Icons.auto_awesome_outlined,
          //   title: 'LLM 结构化',
          //   detail: '使用你配置的本地 API 地址与 Key',
          //   badge: '按设置',
          //   tone: PixelNoticeTone.green,
          // ),
          // const Divider(height: 16),
          // const _CapabilityLine(
          //   icon: Icons.image_outlined,
          //   title: '图片 / OCR',
          //   detail: '识别路线根据 OCR 设置自动选择',
          //   badge: '可降级',
          //   tone: PixelNoticeTone.amber,
          // ),
          // const Divider(height: 16),
          // const _CapabilityLine(
          //   icon: Icons.graphic_eq_rounded,
          //   title: '视频 / ASR',
          //   detail: '内容包含视频时按设备能力处理',
          //   badge: '视内容',
          //   tone: PixelNoticeTone.blue,
          // ),
        ],
      ),
    );
  }
}

class _CapabilityLine extends StatelessWidget {
  const _CapabilityLine({
    required this.icon,
    required this.title,
    required this.detail,
    required this.badge,
    required this.tone,
  });

  final IconData icon;
  final String title;
  final String detail;
  final String badge;
  final PixelNoticeTone tone;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(icon, size: 17, color: AppColors.greenDeep),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(detail, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        PixelBadge(label: badge, tone: tone),
      ],
    );
  }
}

class _ManualRecipeEntry extends StatelessWidget {
  const _ManualRecipeEntry();

  @override
  Widget build(BuildContext context) {
    return PixelSurface(
      key: const ValueKey('manual-recipe'),
      cut: 7,
      color: AppColors.greenSofter,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const PixelBadge(
            label: 'LOCAL FIRST',
            icon: Icons.cloud_off_outlined,
            tone: PixelNoticeTone.green,
          ),
          const SizedBox(height: 12),
          const Text(
            '从零完整记录菜谱',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            '编辑菜名、分类、食材用量、步骤、火候、厨具、时长与备注，保存后立即写入本机。',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 14),
          const _FeatureLine(
            icon: Icons.shopping_basket_outlined,
            text: '动态添加、删除和排序食材',
          ),
          const _FeatureLine(
            icon: Icons.format_list_numbered_rounded,
            text: '记录每一步的时长与关键提示',
          ),
          const _FeatureLine(
            icon: Icons.cloud_off_outlined,
            text: '游客也可离线保存到本机',
          ),
        ],
      ),
    );
  }
}

class _FeatureLine extends StatelessWidget {
  const _FeatureLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: <Widget>[
          SizedBox.square(
            dimension: 24,
            child: ColoredBox(
              color: AppColors.card,
              child: Icon(icon, size: 15, color: AppColors.greenDeep),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
