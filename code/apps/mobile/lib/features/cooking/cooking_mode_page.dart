import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../application/backend/ai_recipe_backend_facade.dart';
import '../../domain/cooking/cooking_session.dart';
import '../../domain/recipe/recipe.dart';
import '../../shared/widgets/pixel_dialogs.dart';
import '../../shared/widgets/pixel_ui.dart';
import '../fridge/inventory_deduction_page.dart';

class CookingModePage extends StatefulWidget {
  const CookingModePage({
    super.key,
    required this.backend,
    required this.recipeId,
    required this.sessionId,
    this.clock,
  });

  final AiRecipeBackendFacade backend;
  final String recipeId;
  final String sessionId;
  final DateTime Function()? clock;

  @override
  State<CookingModePage> createState() => _CookingModePageState();
}

class _CookingModePageState extends State<CookingModePage> {
  static const _background = Color(0xFF2D3D33);

  /// 次级/图标按钮的不透明底色（深绿，比背景亮一档）。
  ///
  /// 实色才能遮住像素阴影——半透明主体会让阴影透出，导致按钮整体发暗、
  /// 看起来「亮色部分比暗色（阴影）部分短」（项目负责人要求亮色与暗色同宽）。
  static const _panelSolid = Color(0xFF41584C);
  static const _primary = Color(0xFF5F8F6E);
  static const _cream = Color(0xFFEDEAE0);
  static const _muted = Color(0xFF9FAFA2);
  static const _accent = Color(0xFFF0C875);
  static const _danger = Color(0xFFF2A18F);

  Recipe? _recipe;
  CookingSession? _session;
  Object? _loadError;
  Timer? _ticker;
  DateTime _displayNow = DateTime.now();
  var _loading = true;
  var _actionBusy = false;
  var _reconcilingExpiredTimers = false;

  DateTime _now() => widget.clock?.call() ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    _displayNow = _now();
    _load();
    _ticker = Timer.periodic(const Duration(seconds: 1), _onClockTick);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }
    try {
      final values = await Future.wait<Object>(<Future<Object>>[
        widget.backend.getRecipe(widget.recipeId),
        widget.backend.getCookingSession(widget.sessionId),
      ]);
      if (!mounted) return;
      setState(() {
        _recipe = values[0] as Recipe;
        _session = values[1] as CookingSession;
        _displayNow = _now();
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error;
        _loading = false;
      });
    }
  }

  void _onClockTick(Timer timer) {
    if (!mounted) return;
    final now = _now();
    setState(() => _displayNow = now);
    unawaited(_reconcileExpiredTimers(now));
  }

  Future<void> _reconcileExpiredTimers(DateTime now) async {
    if (_reconcilingExpiredTimers || _actionBusy) return;
    final session = _session;
    if (session == null || session.status != CookingSessionStatus.active) {
      return;
    }
    final expiredIds = session.timers
        .where(
          (timer) =>
              timer.state == CookingTimerState.running &&
              timer.remainingSecondsAt(now) == 0,
        )
        .map((timer) => timer.id)
        .toList(growable: false);
    if (expiredIds.isEmpty) return;

    _reconcilingExpiredTimers = true;
    final completedLabels = <String>[];
    try {
      var latest = session;
      for (final timerId in expiredIds) {
        final timer = latest.timers
            .where((item) => item.id == timerId)
            .firstOrNull;
        if (timer == null || timer.state != CookingTimerState.running) continue;
        latest = await widget.backend.completeCookingTimer(latest.id, timerId);
        completedLabels.add(timer.label);
      }
      if (!mounted) return;
      setState(() => _session = latest);
      for (final label in completedLabels) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('计时结束：$label')));
      }
    } on AiRecipeBackendException catch (error) {
      _showError(error.message);
    } catch (_) {
      _showError('计时器状态更新失败，请稍后重试。');
    } finally {
      _reconcilingExpiredTimers = false;
    }
  }

  Future<void> _changeStep(int targetIndex) async {
    final session = _session;
    final recipe = _recipe;
    if (session == null || recipe == null || _actionBusy) return;
    if (targetIndex < 0 || targetIndex >= recipe.steps.length) return;
    await _runSessionAction(
      () => widget.backend.setCookingStep(session.id, targetIndex),
    );
  }

  Future<void> _startCurrentStepTimer() async {
    final session = _session;
    final step = _currentStep;
    final durationSeconds = step?.durationSeconds;
    if (session == null || step == null || durationSeconds == null) return;
    if (durationSeconds <= 0) return;
    await _runSessionAction(
      () => widget.backend.addCookingTimer(
        session.id,
        label: _stepTimerLabel(step),
        durationSeconds: durationSeconds,
      ),
    );
  }

  /// 无时长步骤的「自定义本步计时」入口（COOK-001）。
  ///
  /// 弹出像素风输入框（分钟 + 秒），确认后创建计时器并把时长同步到菜谱。
  Future<void> _promptCustomStepDuration() async {
    final step = _currentStep;
    final session = _session;
    if (session == null || step == null || _actionBusy) return;
    final seconds = await showDialog<int>(
      context: context,
      builder: (context) => const _CustomTimerDialog(),
    );
    if (seconds == null || seconds <= 0 || !mounted) return;
    await _applyCustomStepDuration(step, seconds);
  }

  /// 用自定义时长创建计时器，并同步更新菜谱步骤的 [RecipeStep.durationSeconds]，
  /// 使该时长持久化到菜谱（下次烹饪可直接一键启动）。
  Future<void> _applyCustomStepDuration(RecipeStep step, int seconds) async {
    if (_actionBusy) return;
    setState(() => _actionBusy = true);
    try {
      final updatedRecipe = await widget.backend.updateRecipeStepDuration(
        widget.recipeId,
        step.id,
        seconds,
      );
      final session = await widget.backend.addCookingTimer(
        _session!.id,
        label: _stepTimerLabel(step),
        durationSeconds: seconds,
      );
      if (!mounted) return;
      setState(() {
        _recipe = updatedRecipe;
        _session = session;
        _displayNow = _now();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已创建计时器，并将时长同步到菜谱。')),
      );
    } on AiRecipeBackendException catch (error) {
      _showError(error.message);
    } catch (_) {
      _showError('操作失败，请稍后重试。');
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<void> _pauseTimer(CookingTimer timer) async {
    final session = _session;
    if (session == null) return;
    await _runSessionAction(
      () => widget.backend.pauseCookingTimer(session.id, timer.id),
    );
  }

  Future<void> _resumeTimer(CookingTimer timer) async {
    final session = _session;
    if (session == null) return;
    await _runSessionAction(
      () => widget.backend.resumeCookingTimer(session.id, timer.id),
    );
  }

  Future<void> _completeTimer(CookingTimer timer) async {
    final session = _session;
    if (session == null) return;
    await _runSessionAction(
      () => widget.backend.completeCookingTimer(session.id, timer.id),
    );
  }

  Future<void> _deleteTimer(CookingTimer timer) async {
    final session = _session;
    if (session == null) return;
    await _runSessionAction(
      () => widget.backend.deleteCookingTimer(session.id, timer.id),
    );
  }

  Future<void> _runSessionAction(
    Future<CookingSession> Function() operation,
  ) async {
    if (_actionBusy) return;
    setState(() => _actionBusy = true);
    try {
      final session = await operation();
      if (!mounted) return;
      setState(() {
        _session = session;
        _displayNow = _now();
      });
    } on AiRecipeBackendException catch (error) {
      _showError(error.message);
    } catch (_) {
      _showError('操作失败，请稍后重试。');
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _requestExit() async {
    if (!mounted) return;
    final shouldExit = await showPixelConfirm(
      context: context,
      title: '退出烹饪模式？',
      message: '进行中的计时器会继续保存在后台，下次进入可继续查看。',
      confirmLabel: '确认退出',
      cancelLabel: '继续烹饪',
      confirmKey: const Key('confirmExitCookingButton'),
      cancelKey: const Key('cancelExitCookingButton'),
    );
    if (shouldExit == true && mounted) Navigator.of(context).pop(false);
  }

  Future<void> _finishCooking() async {
    final session = _session;
    if (session == null || _actionBusy) return;
    final confirmed = await showPixelConfirm(
      context: context,
      title: '完成烹饪？',
      message: '完成后本次烹饪会话会结束，计时器记录仍会保留。',
      confirmLabel: '完成烹饪',
      confirmKey: const Key('confirmFinishCookingSessionButton'),
    );
    if (confirmed != true) return;

    setState(() => _actionBusy = true);
    try {
      await widget.backend.completeCookingSession(session.id);
      if (!mounted) return;
      // 烹饪完成 → 进入库存扣减确认（FRIDGE-003）。扣减页的结果作为本次
      // 烹饪流程的返回值返回给详情页；不因“暂不更新”而把烹饪视为失败。
      await Navigator.of(context).pushReplacement<bool, bool>(
        MaterialPageRoute<bool>(
          builder: (_) => InventoryDeductionPage(
            backend: widget.backend,
            recipeId: session.recipeId,
            onDataChanged: () {},
          ),
        ),
      );
    } on AiRecipeBackendException catch (error) {
      _showError(error.message);
    } catch (_) {
      _showError('结束烹饪失败，请稍后重试。');
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  RecipeStep? get _currentStep {
    final recipe = _recipe;
    final session = _session;
    if (recipe == null || session == null || recipe.steps.isEmpty) return null;
    final index = session.currentStepIndex.clamp(0, recipe.steps.length - 1);
    return recipe.steps[index];
  }

  List<Ingredient> get _mentionedIngredients {
    final recipe = _recipe;
    final step = _currentStep;
    if (recipe == null || step == null) return const <Ingredient>[];
    return recipe.ingredients
        .where((ingredient) => step.description.contains(ingredient.name))
        .toList(growable: false);
  }

  bool _hasTimerForStep(RecipeStep step) {
    final expectedLabel = _stepTimerLabel(step);
    return _session?.timers.any((timer) => timer.label == expectedLabel) ??
        false;
  }

  String _stepTimerLabel(RecipeStep step) => '步骤 ${step.stepNumber}';

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_requestExit());
      },
      child: Scaffold(
        backgroundColor: _background,
        body: _CookingBackdrop(
          child: SafeArea(
            child: _loading
                ? const _CookingLoadingState()
                : _loadError != null
                ? _CookingErrorState(onRetry: _load, onExit: _requestExit)
                : _buildContent(),
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    final recipe = _recipe!;
    final session = _session!;
    final step = _currentStep;
    if (step == null) {
      return _CookingEmptyState(
        recipeTitle: recipe.title,
        onExit: _requestExit,
      );
    }

    final stepIndex = session.currentStepIndex.clamp(
      0,
      recipe.steps.length - 1,
    );
    final isFirst = stepIndex == 0;
    final isLast = stepIndex == recipe.steps.length - 1;
    final ingredients = _mentionedIngredients;
    final hasDuration = (step.durationSeconds ?? 0) > 0;
    final hasTimer = _hasTimerForStep(step);

    return Column(
      children: <Widget>[
        _CookingHeader(
          recipeTitle: recipe.title,
          onExit: _requestExit,
          busy: _actionBusy,
          currentStep: stepIndex + 1,
          totalSteps: recipe.steps.length,
        ),
        Expanded(
          child: ListView(
            key: const Key('cookingModeScrollView'),
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
            children: <Widget>[
              // 分组面板：详细步骤 + 所需信息 + 分割线 + 所需食材。
              _CookingStepGroup(step: step, ingredients: ingredients),
              const SizedBox(height: 22),
              const _CookingSectionTitle(label: 'TIMERS · 计时器'),
              const SizedBox(height: 9),
              ...session.timers.map(
                  (timer) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _TimerCard(
                      timer: timer,
                      now: _displayNow,
                      busy: _actionBusy,
                      onPause: () => _pauseTimer(timer),
                      onResume: () => _resumeTimer(timer),
                      onComplete: () => _completeTimer(timer),
                      onDelete: () => _deleteTimer(timer),
                    ),
                  ),
                ),
              if (hasDuration && !hasTimer) ...<Widget>[
                const SizedBox(height: 2),
                _CookingNavButton(
                  buttonKey: const Key('startStepTimerButton'),
                  onPressed: _actionBusy ? null : _startCurrentStepTimer,
                  icon: Icons.play_arrow_rounded,
                  label: '启动本步计时 · ${_formatDuration(step.durationSeconds!)}',
                  outlined: true,
                  compact: true,
                ),
              ],
              if (!hasDuration) ...<Widget>[
                const SizedBox(height: 2),
                _CookingNavButton(
                  buttonKey: const Key('customStepTimerButton'),
                  onPressed: _actionBusy ? null : _promptCustomStepDuration,
                  icon: Icons.timer_outlined,
                  label: '自定义本步计时',
                  outlined: true,
                  compact: true,
                ),
              ],
            ],
          ),
        ),
        _CookingNavigation(
          isFirst: isFirst,
          isLast: isLast,
          busy: _actionBusy,
          onPrevious: () => _changeStep(stepIndex - 1),
          onNext: isLast ? _finishCooking : () => _changeStep(stepIndex + 1),
        ),
      ],
    );
  }
}

/// 当前步骤的分组面板：详细步骤 + 所需信息 + 分割线 + 所需食材。
class _CookingStepGroup extends StatelessWidget {
  const _CookingStepGroup({required this.step, required this.ingredients});

  final RecipeStep step;
  final List<Ingredient> ingredients;

  @override
  Widget build(BuildContext context) {
    // 所需信息 chips：所需时间 / 火候 / 温度 / 炊具。
    final details = <Widget>[
      if ((step.durationSeconds ?? 0) > 0)
        _CookingChip(
          icon: Icons.schedule_rounded,
          label: _formatDuration(step.durationSeconds!),
        ),
      if (_hasText(step.heatLevel))
        _CookingChip(
          icon: Icons.local_fire_department_rounded,
          label: step.heatLevel!,
        ),
      if (_hasText(step.temperature))
        _CookingChip(icon: Icons.thermostat_rounded, label: step.temperature!),
      if (_hasText(step.cookware))
        _CookingChip(icon: Icons.soup_kitchen_rounded, label: step.cookware!),
    ];
    return _CookingPixelSurface(
      key: const Key('currentCookingStepPanel'),
      // 面板带像素阴影，必须用不透明实色，否则半透明底会让阴影透出、
      // 视觉上暗色比亮色主体长（项目负责人要求亮色与暗色同宽）。
      color: _CookingModePageState._panelSolid,
      borderColor: const Color(0x1FFFFFFF),
      cut: 10,
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
      // ListView item 高度无限，必须让内容收缩，否则 Column 会撑满无限高度而报错。
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // 详细步骤。
          Text(
            step.description,
            key: const Key('currentCookingStepText'),
            style: const TextStyle(
              color: Color(0xFFF5F3EA),
              fontSize: 21,
              height: 1.8,
              fontWeight: FontWeight.w900,
              letterSpacing: .5,
            ),
          ),
          if (details.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: details),
          ],
          if (_hasText(step.tips)) ...<Widget>[
            const SizedBox(height: 14),
            Text(
              '提示：${step.tips}',
              style: const TextStyle(
                color: _CookingModePageState._muted,
                fontSize: 12,
                height: 1.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          // 分割线。
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Divider(height: 1, color: Color(0x22FFFFFF)),
          ),
          // 所需食材。
          const _CookingSectionTitle(label: '所需食材'),
          const SizedBox(height: 9),
          if (ingredients.isEmpty)
            const _CookingNotice(
              text: '当前数据尚未建立步骤与食材的独立关联，请结合完整食材清单操作。',
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ingredients
                  .map(
                    (ingredient) =>
                        _CookingChip(label: _ingredientLabel(ingredient)),
                  )
                  .toList(growable: false),
            ),
        ],
      ),
    );
  }
}

class _CookingBackdrop extends StatelessWidget {
  const _CookingBackdrop({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: <Color>[Color(0xFF35463B), Color(0xFF2D3D33)],
        ),
      ),
      child: CustomPaint(painter: const _CookingDotPainter(), child: child),
    );
  }
}

class _CookingDotPainter extends CustomPainter {
  const _CookingDotPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0x0CFFFFFF);
    const spacing = 7.0;
    for (var y = spacing / 2; y < size.height; y += spacing) {
      for (var x = spacing / 2; x < size.width; x += spacing) {
        canvas.drawRect(Rect.fromLTWH(x, y, 1, 1), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_CookingDotPainter oldDelegate) => false;
}

enum _CookingDividerEdge { top, bottom }

class _CookingDottedDivider extends StatelessWidget {
  const _CookingDottedDivider({required this.edge, required this.child});

  final _CookingDividerEdge edge;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: _CookingDottedDividerPainter(edge: edge),
      child: child,
    );
  }
}

class _CookingDottedDividerPainter extends CustomPainter {
  const _CookingDottedDividerPainter({required this.edge});

  final _CookingDividerEdge edge;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x2EFFFFFF)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.square;
    final y = edge == _CookingDividerEdge.top ? 1.0 : size.height - 1;
    for (var x = 0.0; x < size.width; x += 8) {
      canvas.drawLine(
        Offset(x, y),
        Offset((x + 4).clamp(0, size.width), y),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_CookingDottedDividerPainter oldDelegate) =>
      oldDelegate.edge != edge;
}

class _CookingPixelSurface extends StatelessWidget {
  const _CookingPixelSurface({
    super.key,
    required this.child,
    required this.color,
    this.borderColor = const Color(0x1FFFFFFF),
    this.cut = 8,
    this.padding = EdgeInsets.zero,
    this.shadowOffset = const Offset(4, 4),
  });

  final Widget child;
  final Color color;
  final Color borderColor;
  final double cut;
  final EdgeInsetsGeometry padding;
  final Offset shadowOffset;

  @override
  Widget build(BuildContext context) {
    final front = ClipPath(
      clipper: PixelCutClipper(cut: cut),
      child: CustomPaint(
        foregroundPainter: _CookingPixelBorderPainter(
          cut: cut,
          color: borderColor,
        ),
        child: ColoredBox(
          color: color,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
    if (shadowOffset == Offset.zero) return front;
    return LayoutBuilder(
      builder: (context, constraints) {
        // 垂直滚动容器（如烹饪模式步骤 ListView）给 item 的高度是无限的，
        // StackFit.expand 会试图撑满无限高度而抛「infinite height」，导致整页空白。
        // 检测到高度无限时改用 StackFit.loose，让面板随内容收缩、阴影仍跟随面板。
        final unboundedHeight = constraints.maxHeight.isInfinite;
        return Padding(
          padding: EdgeInsets.only(
            right: shadowOffset.dx.abs(),
            bottom: shadowOffset.dy.abs(),
          ),
          child: Stack(
            // fit: StackFit.expand 让亮色主体填满整个面板区域——否则当外部约束为
            // tight（如底部导航 Expanded 整行宽）时，Stack 被撑满整行、而主体只按
            // 内容（Row mainAxisSize.min）收缩并贴左上角，阴影（Positioned.fill
            // 跟随 Stack 尺寸）就会比亮色主体宽很多。expand 后主体 = Stack = 阴影
            // 同尺寸，阴影只在右下露 2px 边。无限高度场景用 loose 避免崩溃。
            fit: unboundedHeight ? StackFit.loose : StackFit.expand,
            clipBehavior: Clip.none,
            children: <Widget>[
              Positioned.fill(
                child: Transform.translate(
                  offset: shadowOffset,
                  child: ClipPath(
                    clipper: PixelCutClipper(cut: cut),
                    child: const ColoredBox(color: Color(0x38000000)),
                  ),
                ),
              ),
              front,
            ],
          ),
        );
      },
    );
  }
}

class _CookingPixelBorderPainter extends CustomPainter {
  const _CookingPixelBorderPainter({required this.cut, required this.color});

  final double cut;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      PixelCutClipper(cut: cut).getClip(size),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_CookingPixelBorderPainter oldDelegate) =>
      oldDelegate.cut != cut || oldDelegate.color != color;
}

class _CookingHeader extends StatelessWidget {
  const _CookingHeader({
    required this.recipeTitle,
    required this.onExit,
    required this.busy,
    required this.currentStep,
    required this.totalSteps,
  });

  final String recipeTitle;
  final VoidCallback onExit;
  final bool busy;

  /// 当前步骤号（1 起）与总步骤数，用于头部中间的方块进度。
  final int currentStep;
  final int totalSteps;

  @override
  Widget build(BuildContext context) {
    return _CookingDottedDivider(
      edge: _CookingDividerEdge.bottom,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 9, 16, 13),
        // 三列 1:2:1 布局：左列关闭按钮靠左、中列进度整行居中、右列菜谱名靠右。
        child: Row(
          children: <Widget>[
            // 左列：关闭按钮。
            Expanded(
              flex: 1,
              child: Align(
                alignment: Alignment.centerLeft,
                child: _CookingIconAction(
                  key: const Key('exitCookingButton'),
                  tooltip: '退出烹饪模式',
                  onPressed: busy ? null : onExit,
                  icon: Icons.close_rounded,
                ),
              ),
            ),
            // 中列：进度，小方块（最多 5 个）+ 上方详细步骤顺序，水平居中。
            Expanded(
              flex: 2,
              child: Center(
                child: _CookingStepProgress(
                  current: currentStep,
                  total: totalSteps,
                ),
              ),
            ),
            // 右列：菜谱名称，右对齐，超长省略。
            Expanded(
              flex: 1,
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  recipeTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                    color: _CookingModePageState._cream,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 头部进度：上方显示详细步骤顺序（如 STEP 3 / 10），
/// 下方一排小方块（最多 5 个）表示步骤进度（项目负责人要求）。
class _CookingStepProgress extends StatelessWidget {
  const _CookingStepProgress({required this.current, required this.total});

  /// 当前步骤号（1 起）。
  final int current;

  /// 总步骤数。
  final int total;

  @override
  Widget build(BuildContext context) {
    // 显示的小方块对应的步骤号（滑动窗口，跟随当前步骤移动）。
    final window = _windowBlocks();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          'STEP $current / $total',
          key: const Key('cookingStepProgress'),
          style: const TextStyle(
            color: _CookingModePageState._muted,
            fontFamily: 'monospace',
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 5),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (var i = 0; i < window.length; i++) ...<Widget>[
              _stepBlock(
                filled: window[i] <= current,
                active: window[i] == current,
              ),
              if (i != window.length - 1) const SizedBox(width: 5),
            ],
          ],
        ),
      ],
    );
  }

  /// 计算要显示的小方块对应的连续步骤号。
  ///
  /// 总数不超过 5 时全部显示；超过 5 时用最多 5 格的滑动窗口，
  /// 窗口跟随当前步骤移动（当前步尽量落在第 3 格），
  /// 既满足「最多显示五个方块」，也保证当前进度始终可见（项目负责人要求）。
  List<int> _windowBlocks() {
    const maxBlocks = 5;
    if (total <= maxBlocks) {
      return List<int>.generate(total, (i) => i + 1);
    }
    // 窗口起点：让当前步尽量居中（第 3 格），但不越出 [0, total-5]。
    final start = (current - 3).clamp(0, total - maxBlocks);
    return List<int>.generate(maxBlocks, (i) => start + i + 1);
  }

  /// 单个进度小方块：已完成的填主色、当前步琥珀描边、未来步半透明。
  Widget _stepBlock({required bool filled, required bool active}) {
    return Container(
      width: 13,
      height: 8,
      decoration: BoxDecoration(
        color: filled
            ? _CookingModePageState._primary
            : const Color(0x26FFFFFF),
        border: Border.all(
          color: active
              ? _CookingModePageState._accent
              : const Color(0x40FFFFFF),
          width: 1.5,
        ),
      ),
    );
  }
}

class _TimerCard extends StatelessWidget {
  const _TimerCard({
    required this.timer,
    required this.now,
    required this.busy,
    required this.onPause,
    required this.onResume,
    required this.onComplete,
    required this.onDelete,
  });

  final CookingTimer timer;
  final DateTime now;
  final bool busy;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onComplete;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final remaining = timer.remainingSecondsAt(now);
    final completed = timer.state == CookingTimerState.completed;
    final paused = timer.state == CookingTimerState.paused;
    return _CookingPixelSurface(
      key: Key('cookingTimer-${timer.id}'),
      // 计时器卡片同样带阴影，用不透明实色保证亮色主体与暗色阴影同宽。
      color: completed
          ? const Color(0xFF6E5B2E)
          : _CookingModePageState._panelSolid,
      borderColor: const Color(0x24FFFFFF),
      cut: 6,
      padding: const EdgeInsets.fromLTRB(13, 9, 9, 9),
      shadowOffset: const Offset(2, 2),
      child: Row(
        children: <Widget>[
          Icon(
            completed ? Icons.check_rounded : Icons.timer_outlined,
            size: 19,
            color: completed
                ? _CookingModePageState._cream
                : _CookingModePageState._accent,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  timer.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _CookingModePageState._cream,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  completed
                      ? '已完成'
                      : '${_formatClock(remaining)}${paused ? ' · 已暂停' : ''}',
                  key: Key('cookingTimerRemaining-${timer.id}'),
                  style: TextStyle(
                    color: completed
                        ? _CookingModePageState._cream
                        : const Color(0xFFF5F3EA),
                    fontFamily: 'monospace',
                    fontSize: 17,
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          if (completed)
            _CookingMiniButton(
              key: Key('deleteCookingTimer-${timer.id}'),
              onPressed: busy ? null : onDelete,
              label: '清除',
            )
          else ...<Widget>[
            _CookingIconAction(
              key: Key(
                paused
                    ? 'resumeCookingTimer-${timer.id}'
                    : 'pauseCookingTimer-${timer.id}',
              ),
              tooltip: paused ? '继续' : '暂停',
              onPressed: busy ? null : (paused ? onResume : onPause),
              icon: paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
              compact: true,
            ),
            const SizedBox(width: 5),
            _CookingIconAction(
              key: Key('completeCookingTimer-${timer.id}'),
              tooltip: '完成计时',
              onPressed: busy ? null : onComplete,
              icon: Icons.check_rounded,
              compact: true,
              muted: true,
            ),
          ],
        ],
      ),
    );
  }
}

class _CookingNavigation extends StatelessWidget {
  const _CookingNavigation({
    required this.isFirst,
    required this.isLast,
    required this.busy,
    required this.onPrevious,
    required this.onNext,
  });

  final bool isFirst;
  final bool isLast;
  final bool busy;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return _CookingDottedDivider(
      edge: _CookingDividerEdge.top,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 18),
        child: Row(
          children: <Widget>[
            Expanded(
              // 按钮保持整行宽度（与阴影同宽），阴影随按钮尺寸（项目负责人要求）。
              child: _CookingNavButton(
                buttonKey: const Key('previousCookingStepButton'),
                onPressed: busy || isFirst ? null : onPrevious,
                icon: Icons.chevron_left_rounded,
                label: '上一步',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _CookingNavButton(
                buttonKey: Key(
                  isLast
                      ? 'finishCookingSessionButton'
                      : 'nextCookingStepButton',
                ),
                onPressed: busy ? null : onNext,
                trailingIcon: isLast
                    ? Icons.check_rounded
                    : Icons.chevron_right_rounded,
                label: isLast ? '完成烹饪' : '下一步',
                primary: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 烹饪模式的像素风操作按钮（上一步/下一步、启动/自定义本步计时、重试/退出/返回菜谱等）。
///
/// 实际用途：本页所有「点击后执行一个动作」的主按钮都复用本组件，按参数组合出
/// 不同形态——底部导航的「上一步」「下一步/完成烹饪」、步骤区的「启动本步计时」
/// 「自定义本步计时」、加载失败态的「重试」「退出」、空步骤态的「返回菜谱」。
///
/// 渲染方式：外层 [Opacity] 在禁用态（[onPressed] 为 null）整体压到 38% 透明度；
/// 主体是 [_CookingPixelSurface] 像素面板（阶梯切角 + 右下 2px 硬阴影 + 描边），
/// 内层 [Material]+[InkWell] 提供点击水波纹，内容为「图标 + 文字 + 尾部图标」
/// 的水平居中 Row。主体颜色：[primary] 用主色绿 [_CookingModePageState._primary]，
/// 其余用不透明深绿 [_CookingModePageState._panelSolid]（实色才能遮住像素阴影，
/// 保证亮色主体与暗色阴影同宽）；[outlined] 时描边换成琥珀色 [_CookingModePageState._accent]
/// 作高亮提示（用于启动计时按钮）；[compact] 为紧凑小按钮（切角更小、内边距更小、
/// 字号 13），用于步骤区计时按钮与错误/空状态的整页操作按钮。
class _CookingNavButton extends StatelessWidget {
  const _CookingNavButton({
    required this.onPressed,
    this.buttonKey,
    required this.label,
    this.icon,
    this.trailingIcon,
    this.primary = false,
    this.outlined = false,
    this.compact = false,
  });

  /// 点击回调；为 null 表示禁用（按钮变灰且不可点）。
  final VoidCallback? onPressed;

  /// 测试/自动化定位用的 Key（如 previousCookingStepButton、startStepTimerButton）。
  final Key? buttonKey;

  /// 按钮文字（如「上一步」「下一步」「完成烹饪」）。
  final String label;

  /// 可选的前导图标（显示在文字左侧，如左箭头、播放、计时器图标）。
  final IconData? icon;

  /// 可选的尾部图标（显示在文字右侧，如右箭头、完成对勾）。
  final IconData? trailingIcon;

  /// 是否为主按钮：true 用主色绿背景（下一步/完成烹饪/重试/返回菜谱），
  /// false 用深绿次级背景（上一步/退出）。
  final bool primary;

  /// 是否用琥珀色描边作高亮提示（用于「启动本步计时」「自定义本步计时」）。
  final bool outlined;

  /// 是否紧凑小按钮：更小切角/内边距/字号（步骤区计时按钮、错误/空状态操作按钮）。
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Opacity(
      opacity: enabled ? 1 : .38,
      child: _CookingPixelSurface(
        // 次级按钮用不透明实色遮住像素阴影，保证亮色主体与暗色阴影同宽
        // （半透明底色会让阴影从主体区域透出，视觉上暗色比亮色长）。
        color: primary
            ? _CookingModePageState._primary
            : _CookingModePageState._panelSolid,
        borderColor: outlined
            ? _CookingModePageState._accent
            : const Color(0x59000000),
        cut: compact ? 5 : 7,
        // 阴影只比主体多出 2px，避免暗色阴影看起来比亮色主体还长（项目负责人要求）。
        shadowOffset: const Offset(2, 2),
        padding: EdgeInsets.zero,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: buttonKey,
            onTap: onPressed,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 13 : 14,
                vertical: compact ? 12 : 17,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (icon != null) ...<Widget>[
                    Icon(
                      icon,
                      size: compact ? 18 : 20,
                      color: _CookingModePageState._cream,
                    ),
                    const SizedBox(width: 7),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _CookingModePageState._cream,
                        fontSize: compact ? 13 : 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  if (trailingIcon != null) ...<Widget>[
                    const SizedBox(width: 7),
                    Icon(
                      trailingIcon,
                      size: compact ? 18 : 20,
                      color: _CookingModePageState._cream,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CookingIconAction extends StatelessWidget {
  const _CookingIconAction({
    super.key,
    required this.tooltip,
    required this.onPressed,
    required this.icon,
    this.compact = false,
    this.muted = false,
  });

  final String tooltip;
  final VoidCallback? onPressed;
  final IconData icon;
  final bool compact;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final dimension = compact ? 32.0 : 38.0;
    return Opacity(
      opacity: onPressed == null ? .4 : 1,
      child: Tooltip(
        message: tooltip,
        child: _CookingPixelSurface(
          // 图标按钮用不透明实色遮住像素阴影，亮色主体与暗色阴影同宽。
          color: _CookingModePageState._panelSolid,
          borderColor: const Color(0x24FFFFFF),
          cut: compact ? 4 : 5,
          shadowOffset: compact ? Offset.zero : const Offset(2, 2),
          padding: EdgeInsets.zero,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onPressed,
              child: SizedBox.square(
                dimension: dimension,
                child: Icon(
                  icon,
                  size: compact ? 18 : 20,
                  color: muted
                      ? _CookingModePageState._muted
                      : _CookingModePageState._cream,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CookingMiniButton extends StatelessWidget {
  const _CookingMiniButton({
    super.key,
    required this.onPressed,
    required this.label,
  });

  final VoidCallback? onPressed;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onPressed == null ? .4 : 1,
      child: ClipPath(
        clipper: const PixelCutClipper(cut: 4),
        child: Material(
          // 与 _CookingNavButton / _CookingIconAction 保持同一套不透明实色。
          color: _CookingModePageState._panelSolid,
          child: InkWell(
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Text(
                label,
                style: const TextStyle(
                  color: _CookingModePageState._cream,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CookingChip extends StatelessWidget {
  const _CookingChip({required this.label, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return ClipPath(
      clipper: const PixelCutClipper(cut: 3),
      child: ColoredBox(
        color: const Color(0x17FFFFFF),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Icon(icon, size: 14, color: _CookingModePageState._cream),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFFE8E5D8),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CookingSectionTitle extends StatelessWidget {
  const _CookingSectionTitle({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        color: _CookingModePageState._muted,
        fontFamily: 'monospace',
        fontSize: 10,
        fontWeight: FontWeight.w900,
        letterSpacing: 2.1,
      ),
    );
  }
}

class _CookingNotice extends StatelessWidget {
  const _CookingNotice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    // 纯文字提示：不带矩形背景/边框/阴影（项目负责人要求：空食材提示不要矩形背景）。
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Icon(
          Icons.info_outline_rounded,
          color: _CookingModePageState._muted,
          size: 14,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: _CookingModePageState._muted,
              fontSize: 12,
              height: 1.55,
            ),
          ),
        ),
      ],
    );
  }
}

class _CookingStateIcon extends StatelessWidget {
  const _CookingStateIcon({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 92,
      child: _CookingPixelSurface(
        // 大图标同样带阴影，使用不透明实色避免暗色阴影显长。
        color: _CookingModePageState._panelSolid,
        borderColor: const Color(0x24FFFFFF),
        cut: 10,
        child: Center(child: Icon(icon, color: color, size: 42)),
      ),
    );
  }
}

class _CookingLoadingState extends StatelessWidget {
  const _CookingLoadingState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          PixelLoader(size: 8, color: _CookingModePageState._accent),
          SizedBox(height: 18),
          Text(
            '正在准备烹饪模式…',
            style: TextStyle(
              color: _CookingModePageState._cream,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _CookingErrorState extends StatelessWidget {
  const _CookingErrorState({required this.onRetry, required this.onExit});

  final VoidCallback onRetry;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const _CookingStateIcon(
              icon: Icons.error_outline_rounded,
              color: _CookingModePageState._danger,
            ),
            const SizedBox(height: 20),
            const Text(
              '烹饪会话暂时无法读取。',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _CookingModePageState._cream,
                fontSize: 17,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: 220,
              child: _CookingNavButton(
                onPressed: onRetry,
                label: '重试',
                primary: true,
                compact: true,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: 220,
              child: _CookingNavButton(
                onPressed: onExit,
                label: '退出',
                compact: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CookingEmptyState extends StatelessWidget {
  const _CookingEmptyState({required this.recipeTitle, required this.onExit});

  final String recipeTitle;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const _CookingStateIcon(
              icon: Icons.menu_book_outlined,
              color: _CookingModePageState._accent,
            ),
            const SizedBox(height: 20),
            Text(
              '“$recipeTitle”尚未添加烹饪步骤。',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _CookingModePageState._cream,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '请先返回菜谱编辑页补充步骤。',
              style: TextStyle(color: _CookingModePageState._muted),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: 220,
              child: _CookingNavButton(
                onPressed: onExit,
                label: '返回菜谱',
                primary: true,
                compact: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

bool _hasText(String? value) => value?.trim().isNotEmpty ?? false;

String _ingredientLabel(Ingredient ingredient) {
  final amount = <String>[
    if (_hasText(ingredient.quantity)) ingredient.quantity!.trim(),
    if (_hasText(ingredient.unit)) ingredient.unit!.trim(),
  ].join(' ');
  return amount.isEmpty ? ingredient.name : '${ingredient.name} $amount';
}

String _formatDuration(int seconds) {
  if (seconds < 60) return '$seconds 秒';
  final minutes = seconds ~/ 60;
  final remainder = seconds % 60;
  return remainder == 0 ? '$minutes 分钟' : '$minutes 分 $remainder 秒';
}

String _formatClock(int seconds) {
  final safe = seconds < 0 ? 0 : seconds;
  final hours = safe ~/ 3600;
  final minutes = (safe % 3600) ~/ 60;
  final remainder = safe % 60;
  if (hours > 0) {
    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${remainder.toString().padLeft(2, '0')}';
  }
  return '${minutes.toString().padLeft(2, '0')}:'
      '${remainder.toString().padLeft(2, '0')}';
}

/// 像素风「自定义本步计时」输入弹窗（COOK-001）。
///
/// 输入分钟与秒，确认时返回总秒数；输入非法或为 0 时提示不关闭弹窗。
/// controller 由本 State 持有并在 dispose 中释放，与弹窗生命周期一致。
class _CustomTimerDialog extends StatefulWidget {
  const _CustomTimerDialog();

  @override
  State<_CustomTimerDialog> createState() => _CustomTimerDialogState();
}

class _CustomTimerDialogState extends State<_CustomTimerDialog> {
  final _minutesController = TextEditingController();
  final _secondsController = TextEditingController();

  @override
  void dispose() {
    _minutesController.dispose();
    _secondsController.dispose();
    super.dispose();
  }

  /// 返回合法总秒数；非法（负数/全为 0/非数字）返回 null。
  int? _totalSeconds() {
    final minutes = int.tryParse(_minutesController.text.trim()) ?? 0;
    final seconds = int.tryParse(_secondsController.text.trim()) ?? 0;
    if (minutes < 0 || seconds < 0) return null;
    final total = minutes * 60 + seconds;
    return total > 0 ? total : null;
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
            const Text(
              '自定义本步计时',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              '设置后时长会同步保存到菜谱，下次烹饪可直接一键启动',
              style: TextStyle(fontSize: 11, color: AppColors.ink3),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    key: const Key('customTimerMinutesField'),
                    controller: _minutesController,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '分钟',
                      hintText: '0',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    key: const Key('customTimerSecondsField'),
                    controller: _secondsController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '秒',
                      hintText: '0',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                OutlinedButton(
                  key: const Key('cancelCustomTimerButton'),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: const Key('confirmCustomTimerButton'),
                  onPressed: () {
                    final total = _totalSeconds();
                    if (total == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('请输入大于 0 的时长')),
                      );
                      return;
                    }
                    Navigator.of(context).pop(total);
                  },
                  child: const Text('开始计时'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
