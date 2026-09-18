import 'package:ai_recipe/app/app_theme.dart';
import 'package:ai_recipe/domain/importing/import_task.dart';
import 'package:ai_recipe/features/importing/add_recipe_page.dart';
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
    required Future<void> Function(ImportTask task) onOpenImportTask,
    VoidCallback? onOpenManualEditor,
    VoidCallback? onDataChanged,
  }) {
    return MaterialApp(
      theme: buildAiRecipeTheme(),
      home: AddRecipePage(
        backend: harness.root.backend,
        onDataChanged: onDataChanged ?? () {},
        onOpenLibrary: () {},
        onOpenManualEditor: onOpenManualEditor ?? () {},
        onOpenImportTask: onOpenImportTask,
      ),
    );
  }

  testWidgets('supported link creates a task and opens import progress', (
    tester,
  ) async {
    final harness = await createHarness(tester);
    ImportTask? openedTask;
    var dataChangedCount = 0;

    await tester.pumpWidget(
      wrap(
        harness,
        onDataChanged: () => dataChangedCount += 1,
        onOpenImportTask: (task) async => openedTask = task,
      ),
    );
    await tester.enterText(
      find.byKey(const Key('importLinkField')),
      'https://www.xiaohongshu.com/explore/add-page',
    );
    await tester.tap(find.byKey(const Key('addRecipePrimaryButton')));
    await tester.pumpAndSettle();

    expect(openedTask, isNotNull);
    expect(openedTask!.status, ImportTaskStatus.queued);
    expect(openedTask!.sourcePlatform, ImportSourcePlatform.xiaohongshu);
    expect(
      openedTask!.normalizedUrl,
      'https://www.xiaohongshu.com/explore/add-page',
    );
    expect(dataChangedCount, 1);
    expect(
      await harness.root.backend.getImportTask(openedTask!.id),
      openedTask,
    );
  });

  testWidgets('empty link stays on page and does not create a task', (
    tester,
  ) async {
    final harness = await createHarness(tester);
    var openCount = 0;

    await tester.pumpWidget(
      wrap(harness, onOpenImportTask: (_) async => openCount += 1),
    );
    await tester.tap(find.byKey(const Key('addRecipePrimaryButton')));
    await tester.pumpAndSettle();

    expect(openCount, 0);
    expect(find.textContaining('\u8bf7\u7c98\u8d34'), findsOneWidget);
  });

  testWidgets('multiple links create multiple tasks and open task list', (
    tester,
  ) async {
    final harness = await createHarness(tester);
    ImportTask? openedTask;
    var listOpened = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAiRecipeTheme(),
        home: AddRecipePage(
          backend: harness.root.backend,
          onDataChanged: () {},
          onOpenLibrary: () {},
          onOpenManualEditor: () {},
          onOpenImportTask: (task) async => openedTask = task,
          onOpenImportTasks: () => listOpened += 1,
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const Key('importLinkField')),
      'https://www.xiaohongshu.com/explore/a\n'
      'https://v.douyin.com/b/',
    );
    await tester.tap(find.byKey(const Key('addRecipePrimaryButton')));
    await tester.pumpAndSettle();

    // 批量创建两个任务，不打开单个进度页而是打开任务列表。
    expect(listOpened, 1);
    expect(openedTask, isNull);
    final tasks = await harness.root.backend.listImportTasks(
      statuses: <ImportTaskStatus>{ImportTaskStatus.queued},
    );
    expect(tasks.length, 2);
    expect(find.textContaining('\u5df2\u521b\u5efa 2'), findsOneWidget);
  });
}
