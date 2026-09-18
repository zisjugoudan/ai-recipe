import 'package:ai_recipe/app/app_theme.dart';
import 'package:ai_recipe/application/backend/ai_recipe_backend_facade.dart';
import 'package:ai_recipe/domain/importing/import_task.dart';
import 'package:ai_recipe/features/importing/import_tasks_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_backend_harness.dart';

void main() {
  Future<TestBackendHarness> createHarness(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 1000));
    final harness = TestBackendHarness();
    addTearDown(() async {
      await harness.close();
      await tester.binding.setSurfaceSize(null);
    });
    return harness;
  }

  Widget wrap(
    TestBackendHarness harness, {
    Future<void> Function(ImportTask task)? onOpenImportTask,
  }) {
    return MaterialApp(
      theme: buildAiRecipeTheme(),
      home: ImportTasksPage(
        backend: harness.root.backend,
        onDataChanged: () {},
        onOpenImportTask: onOpenImportTask ?? (_) async {},
      ),
    );
  }

  testWidgets('lists unfinished tasks and opens progress on tap', (
    tester,
  ) async {
    final harness = await createHarness(tester);
    final task = await harness.root.backend.createImportTask(
      'https://www.xiaohongshu.com/explore/list-1',
    );
    ImportTask? opened;

    await tester.pumpWidget(wrap(harness, onOpenImportTask: (t) async => opened = t));
    await tester.pumpAndSettle();

    expect(
      find.text('https://www.xiaohongshu.com/explore/list-1'),
      findsOneWidget,
    );
    await tester.tap(
      find.text('https://www.xiaohongshu.com/explore/list-1'),
    );
    await tester.pumpAndSettle();
    expect(opened?.id, task.id);
  });

  testWidgets('cancels a queued task from the list', (tester) async {
    final harness = await createHarness(tester);
    final task = await harness.root.backend.createImportTask(
      'https://v.douyin.com/list-cancel/',
    );

    await tester.pumpWidget(wrap(harness));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('cancelImportTask_${task.id}')));
    await tester.pumpAndSettle();

    final updated = await harness.root.backend.getImportTask(task.id);
    expect(updated.status, ImportTaskStatus.cancelled);
    expect(find.text('已取消'), findsOneWidget);
  });

  testWidgets('deletes a finished task after confirmation', (tester) async {
    final harness = await createHarness(tester);
    final task = await harness.root.backend.createImportTask(
      'https://www.xiaohongshu.com/explore/delete-1',
    );
    await harness.root.backend.cancelImportTask(task.id);

    await tester.pumpWidget(wrap(harness));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('deleteImportTask_${task.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();

    await expectLater(
      harness.root.backend.getImportTask(task.id),
      throwsA(isA<AiRecipeBackendException>()),
    );
  });

  testWidgets('clears all finished tasks at once', (tester) async {
    final harness = await createHarness(tester);
    final task1 = await harness.root.backend.createImportTask(
      'https://www.xiaohongshu.com/explore/clear-1',
    );
    final task2 = await harness.root.backend.createImportTask(
      'https://v.douyin.com/clear-2/',
    );
    await harness.root.backend.cancelImportTask(task1.id);
    await harness.root.backend.cancelImportTask(task2.id);

    await tester.pumpWidget(wrap(harness));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('clearFinishedImportTasksButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();

    expect(find.textContaining('没有未完成的导入'), findsOneWidget);
  });

  testWidgets('long press enters selection mode and selects the task', (
    tester,
  ) async {
    final harness = await createHarness(tester);
    final task = await harness.root.backend.createImportTask(
      'https://www.xiaohongshu.com/explore/select-1',
    );

    await tester.pumpWidget(wrap(harness));
    await tester.pumpAndSettle();
    // 长按任务卡片进入选择模式并选中该项。
    await tester.longPress(
      find.text('https://www.xiaohongshu.com/explore/select-1'),
    );
    await tester.pumpAndSettle();

    expect(find.text('已选择 1 项'), findsOneWidget);
    expect(find.text('全选'), findsOneWidget);
    expect(find.byKey(const Key('deleteSelectedImportTasksButton')), findsOneWidget);
    // 选择模式下隐藏单个取消/删除按钮。
    expect(find.byKey(Key('cancelImportTask_${task.id}')), findsNothing);
    expect(find.byKey(Key('deleteImportTask_${task.id}')), findsNothing);
  });

  testWidgets('tap toggles selection and empty selection exits mode', (
    tester,
  ) async {
    final harness = await createHarness(tester);
    final task1 = await harness.root.backend.createImportTask(
      'https://www.xiaohongshu.com/explore/toggle-1',
    );
    await harness.root.backend.createImportTask(
      'https://v.douyin.com/toggle-2/',
    );

    await tester.pumpWidget(wrap(harness));
    await tester.pumpAndSettle();
    await tester.longPress(
      find.text('https://www.xiaohongshu.com/explore/toggle-1'),
    );
    await tester.pumpAndSettle();
    expect(find.text('已选择 1 项'), findsOneWidget);

    // 点按另一项切换选中：1 → 2 项。
    await tester.tap(find.text('https://v.douyin.com/toggle-2/'));
    await tester.pumpAndSettle();
    expect(find.text('已选择 2 项'), findsOneWidget);

    // 逐个取消选中：2 → 1 → 0，全部取消后自动退出选择模式。
    await tester.tap(find.text('https://www.xiaohongshu.com/explore/toggle-1'));
    await tester.pumpAndSettle();
    expect(find.text('已选择 1 项'), findsOneWidget);
    await tester.tap(find.text('https://v.douyin.com/toggle-2/'));
    await tester.pumpAndSettle();
    expect(find.text('已选择 1 项'), findsNothing);
    expect(find.text('共 2 条未完成'), findsOneWidget);
  });

  testWidgets('select all then cancel all exits selection mode', (tester) async {
    final harness = await createHarness(tester);
    await harness.root.backend.createImportTask(
      'https://www.xiaohongshu.com/explore/all-1',
    );
    await harness.root.backend.createImportTask(
      'https://v.douyin.com/all-2/',
    );

    await tester.pumpWidget(wrap(harness));
    await tester.pumpAndSettle();
    await tester.longPress(
      find.text('https://www.xiaohongshu.com/explore/all-1'),
    );
    await tester.pumpAndSettle();

    // 全选：选中列表全部任务，按钮变为"取消全选"。
    await tester.tap(find.byKey(const Key('selectAllImportTasksButton')));
    await tester.pumpAndSettle();
    expect(find.text('已选择 2 项'), findsOneWidget);
    expect(find.text('取消全选'), findsOneWidget);
    expect(find.text('删除所选 (2)'), findsOneWidget);

    // 取消全选：退出选择模式，回到普通列表。
    await tester.tap(find.byKey(const Key('selectAllImportTasksButton')));
    await tester.pumpAndSettle();
    expect(find.text('共 2 条未完成'), findsOneWidget);
    expect(find.text('取消全选'), findsNothing);
  });

  testWidgets('batch deletes selected finished tasks only', (tester) async {
    final harness = await createHarness(tester);
    final task1 = await harness.root.backend.createImportTask(
      'https://www.xiaohongshu.com/explore/batch-1',
    );
    final task2 = await harness.root.backend.createImportTask(
      'https://v.douyin.com/batch-2/',
    );
    await harness.root.backend.cancelImportTask(task1.id);

    await tester.pumpWidget(wrap(harness));
    await tester.pumpAndSettle();
    // 长按已取消任务进入选择模式。
    await tester.longPress(
      find.text('https://www.xiaohongshu.com/explore/batch-1'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('deleteSelectedImportTasksButton')));
    await tester.pumpAndSettle();
    // 确认对话框提示已结束数量。
    expect(find.text('删除所选 1 条导入记录？'), findsOneWidget);
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();

    // 已取消任务被删除，仍处列表的排队任务保留。
    await expectLater(
      harness.root.backend.getImportTask(task1.id),
      throwsA(isA<AiRecipeBackendException>()),
    );
    expect(
      (await harness.root.backend.getImportTask(task2.id)).status,
      ImportTaskStatus.queued,
    );
  });

  testWidgets('batch delete also removes active tasks and warns in dialog', (
    tester,
  ) async {
    final harness = await createHarness(tester);
    final active = await harness.root.backend.createImportTask(
      'https://www.xiaohongshu.com/explore/active-1',
    );
    final finished = await harness.root.backend.createImportTask(
      'https://v.douyin.com/finished-2/',
    );
    await harness.root.backend.cancelImportTask(finished.id);

    await tester.pumpWidget(wrap(harness));
    await tester.pumpAndSettle();
    // 长按排队任务进入选择模式，再全选把已取消任务一起选中。
    await tester.longPress(
      find.text('https://www.xiaohongshu.com/explore/active-1'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('selectAllImportTasksButton')));
    await tester.pumpAndSettle();
    expect(find.text('删除所选 (2)'), findsOneWidget);

    await tester.tap(find.byKey(const Key('deleteSelectedImportTasksButton')));
    await tester.pumpAndSettle();
    // 进行中任务也会被删除，但确认弹窗提示中断解析与草稿丢失的后果。
    expect(find.text('删除所选 2 条导入记录？'), findsOneWidget);
    expect(find.textContaining('其中 1 条正在进行或待确认'), findsOneWidget);
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();

    // 排队任务与已取消任务都被删除。
    await expectLater(
      harness.root.backend.getImportTask(active.id),
      throwsA(isA<AiRecipeBackendException>()),
    );
    await expectLater(
      harness.root.backend.getImportTask(finished.id),
      throwsA(isA<AiRecipeBackendException>()),
    );
  });

  testWidgets('cancel all selection via exit button', (tester) async {
    final harness = await createHarness(tester);
    await harness.root.backend.createImportTask(
      'https://www.xiaohongshu.com/explore/exit-1',
    );

    await tester.pumpWidget(wrap(harness));
    await tester.pumpAndSettle();
    await tester.longPress(
      find.text('https://www.xiaohongshu.com/explore/exit-1'),
    );
    await tester.pumpAndSettle();
    expect(find.text('已选择 1 项'), findsOneWidget);

    await tester.tap(find.byKey(const Key('exitImportSelectionButton')));
    await tester.pumpAndSettle();
    expect(find.text('已选择 1 项'), findsNothing);
    expect(find.text('共 1 条未完成'), findsOneWidget);
  });
}
