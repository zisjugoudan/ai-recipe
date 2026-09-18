import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../application/backend/ai_recipe_backend_facade.dart';
import '../../domain/recipe/recipe.dart';
import '../../shared/widgets/app_states.dart';
import '../../shared/widgets/pixel_dialogs.dart';
import '../../shared/widgets/pixel_ui.dart';

class RecipeTrashPage extends StatefulWidget {
  const RecipeTrashPage({
    super.key,
    required this.backend,
    required this.onDataChanged,
  });

  final AiRecipeBackendFacade backend;
  final VoidCallback onDataChanged;

  @override
  State<RecipeTrashPage> createState() => _RecipeTrashPageState();
}

class _RecipeTrashPageState extends State<RecipeTrashPage> {
  late Future<List<TrashRecipeSummary>> _recipes;
  final Set<String> _busyRecipeIds = <String>{};
  var _emptying = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      // 回收站列表只读标题与删除时间，走轻量摘要接口，
      // 避免 listRecipes 逐条全量加载（N+1）导致大库卡顿。
      _recipes = widget.backend.listTrashSummaries();
    });
  }

  Future<void> _restore(TrashRecipeSummary recipe) async {
    await _runFor(recipe.id, () async {
      await widget.backend.restoreRecipe(recipe.id);
      widget.onDataChanged();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('“${recipe.title}”已恢复。')));
      }
      _reload();
    });
  }

  Future<void> _deletePermanently(TrashRecipeSummary recipe) async {
    final confirmed = await showPixelConfirm(
      context: context,
      title: '永久删除？',
      message: '“${recipe.title}”删除后无法恢复。',
      confirmLabel: '永久删除',
      confirmColor: AppColors.red,
      confirmKey: const Key('confirmPermanentDeleteRecipe'),
    );
    if (confirmed != true) return;
    await _runFor(recipe.id, () async {
      await widget.backend.permanentlyDeleteRecipe(recipe.id);
      widget.onDataChanged();
      _reload();
    });
  }

  Future<void> _emptyTrash(int count) async {
    final confirmed = await showPixelConfirm(
      context: context,
      title: '清空回收站？',
      message: '将永久删除 $count 道菜谱，此操作无法撤销。',
      confirmLabel: '确认清空',
      confirmColor: AppColors.red,
      confirmKey: const Key('confirmEmptyRecipeTrash'),
    );
    if (confirmed != true || _emptying) return;
    setState(() => _emptying = true);
    try {
      final removed = await widget.backend.emptyRecipeTrash();
      widget.onDataChanged();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('已永久删除 $removed 道菜谱。')));
      }
      _reload();
    } on AiRecipeBackendException catch (error) {
      _showError(error.message);
    } catch (_) {
      _showError('回收站清空失败，请稍后重试。');
    } finally {
      if (mounted) setState(() => _emptying = false);
    }
  }

  Future<void> _runFor(String id, Future<void> Function() action) async {
    if (_busyRecipeIds.contains(id)) return;
    setState(() => _busyRecipeIds.add(id));
    try {
      await action();
    } on AiRecipeBackendException catch (error) {
      _showError(error.message);
    } catch (_) {
      _showError('操作失败，请稍后重试。');
    } finally {
      if (mounted) setState(() => _busyRecipeIds.remove(id));
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const PixelPageAppBar(
        title: '回收站',
        eyebrow: '回收站 · 本机暂存',
      ),
      body: FutureBuilder<List<TrashRecipeSummary>>(
        future: _recipes,
        builder: (context, state) {
          if (state.connectionState == ConnectionState.waiting) {
            return const AppLoadingState(label: '正在读取回收站…');
          }
          if (state.hasError) {
            return Padding(
              padding: const EdgeInsets.all(18),
              child: AppErrorState(message: '回收站暂时无法读取。', onRetry: _reload),
            );
          }
          final recipes = state.requireData;
          if (recipes.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(18),
              child: AppEmptyState(
                icon: Icons.delete_sweep_outlined,
                title: '回收站是空的',
                message: '从菜谱详情删除的菜谱会暂存在这里。',
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 32),
            children: <Widget>[
              PixelNotice(
                title: '已删除 ${recipes.length} 道菜谱',
                message: '删除内容只保留在本机，直到你恢复或永久删除。永久删除后无法撤销。',
                tone: PixelNoticeTone.red,
                icon: Icons.delete_outline_rounded,
                trailing: TextButton(
                  key: const Key('emptyRecipeTrashButton'),
                  onPressed: _emptying
                      ? null
                      : () => _emptyTrash(recipes.length),
                  style: TextButton.styleFrom(foregroundColor: AppColors.red),
                  child: Text(_emptying ? '清空中…' : '清空'),
                ),
              ),
              const SizedBox(height: 16),
              const PxLabel('已删除菜谱'),
              const SizedBox(height: 8),
              ...recipes.map(
                (recipe) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _TrashRecipeCard(
                    recipe: recipe,
                    busy: _busyRecipeIds.contains(recipe.id),
                    onRestore: () => _restore(recipe),
                    onDelete: () => _deletePermanently(recipe),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TrashRecipeCard extends StatelessWidget {
  const _TrashRecipeCard({
    required this.recipe,
    required this.busy,
    required this.onRestore,
    required this.onDelete,
  });

  final TrashRecipeSummary recipe;
  final bool busy;
  final VoidCallback onRestore;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return PixelSurface(
      cut: 6,
      padding: const EdgeInsets.fromLTRB(15, 14, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const PixelBadge(
                label: 'DELETED',
                icon: Icons.delete_outline_rounded,
                tone: PixelNoticeTone.red,
              ),
              const Spacer(),
              if (busy) const PixelLoader(size: 5, color: AppColors.red),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            recipe.title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            '删除时间：${_dateLabel(recipe.deletedAt)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          const Divider(height: 1, color: AppColors.line2),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              TextButton.icon(
                key: ValueKey('restoreRecipe-${recipe.id}'),
                onPressed: busy ? null : onRestore,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.greenDeep,
                ),
                icon: const Icon(Icons.restore_rounded),
                label: const Text('恢复'),
              ),
              TextButton.icon(
                key: ValueKey('permanentlyDeleteRecipe-${recipe.id}'),
                onPressed: busy ? null : onDelete,
                icon: const Icon(Icons.delete_forever_outlined),
                label: const Text('永久删除'),
                style: TextButton.styleFrom(foregroundColor: AppColors.red),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _dateLabel(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)} ${two(value.hour)}:${two(value.minute)}';
}
