import 'package:flutter/material.dart';

import 'pixel_ui.dart';

/// 新建分类对话框。
///
/// 设计要点（对应 BUG-001）：
/// 1. 输入控制器由本 State 持有并在 `dispose()` 中释放。`State.dispose()` 在
///    Dialog 退场动画结束后才被调用，避免在“关闭动画仍在进行时”继续访问已释放
///    控制器而抛出 `TextEditingController was used after being disposed`。
/// 2. 提交前做稳定校验：空名称 / 仅空白、超长名称、同名分类均显示内联错误，
///    不产生空分类、重复分类或脏数据。
/// 3. `_submitted` 标记防止快速重复提交（重复点击“创建”或回车 + 按钮竞态）。
class CreateCategoryDialog extends StatefulWidget {
  const CreateCategoryDialog({super.key, required this.existingNames});

  /// 已存在分类名称列表；用于同名校验（忽略首尾空白、大小写不敏感）。
  final List<String> existingNames;

  /// 弹出对话框，返回去除首尾空白后的有效名称；取消或校验失败时返回 null。
  static Future<String?> show(
    BuildContext context, {
    required List<String> existingNames,
  }) {
    return showDialog<String>(
      context: context,
      builder: (_) => CreateCategoryDialog(existingNames: existingNames),
    );
  }

  @override
  State<CreateCategoryDialog> createState() => _CreateCategoryDialogState();
}

class _CreateCategoryDialogState extends State<CreateCategoryDialog> {
  static const int _maxNameLength = 30;

  late final TextEditingController _controller;
  String? _errorText;
  var _submitted = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    // 在 Dialog 完全退出（退场动画结束、路由卸载）后才释放控制器。
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    // 防止快速重复提交：首次提交后立即锁住后续点击与回车。
    if (_submitted) return;

    final name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() => _errorText = '请输入分类名称。');
      return;
    }
    if (name.length > _maxNameLength) {
      setState(() => _errorText = '分类名称不能超过 $_maxNameLength 个字符。');
      return;
    }
    final lowerName = name.toLowerCase();
    final duplicated = widget.existingNames.any(
      (item) => item.trim().toLowerCase() == lowerName,
    );
    if (duplicated) {
      setState(() => _errorText = '已存在同名分类。');
      return;
    }

    _submitted = true;
    Navigator.of(context).pop(name);
  }

  void _cancel() {
    if (_submitted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: PixelSurface(
        cut: 9,
        elevation: 8,
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const PxLabel('新建分类'),
            const SizedBox(height: 8),
            const Text(
              '新建分类',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 14),
            TextField(
              key: const Key('createCategoryNameField'),
              controller: _controller,
              autofocus: true,
              enabled: !_submitted,
              maxLength: _maxNameLength,
              onChanged: (_) {
                // 用户重新输入时清除上一次的错误提示。
                if (_errorText != null) {
                  setState(() => _errorText = null);
                }
              },
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: '分类名称',
                hintText: '例如：快手晚餐',
                errorText: _errorText,
                errorMaxLines: 2,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    key: const Key('cancelCreateCategoryButton'),
                    onPressed: _submitted ? null : _cancel,
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    key: const Key('confirmCreateCategoryButton'),
                    onPressed: _submitted ? null : _submit,
                    child: const Text('创建'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
