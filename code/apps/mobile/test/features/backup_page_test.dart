import 'package:ai_recipe/app/app_theme.dart';
import 'package:ai_recipe/application/backup/backup_export_use_cases.dart';
import 'package:ai_recipe/domain/backup/backup_manifest.dart';
import 'package:ai_recipe/features/backup/backup_import_page.dart';
import 'package:ai_recipe/features/backup/backup_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/test_backend_harness.dart';

void main() {
  // TestBackendHarness 构造组合根时会通过全局 databaseFactory 创建
  // AppDatabase，并构造 DeviceMultimodalLlmConfigRepository（依赖
  // SharedPreferencesAsync），因此先初始化 sqlite FFI 与内存偏好存储。
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  /// 构造一个最近的备份结果（页面「另存为」入口依赖它显示）。
  BackupExportResult fakeResult() => BackupExportResult(
        filePath:
            '/data/app_flutter/backups/ai-recipe-20260807-010203040.airecipe-backup',
        fileName: 'ai-recipe-20260807-010203040.airecipe-backup',
        byteSize: 4096,
        statistics: const BackupContentStatistics(
          recipeTotal: 2,
          recipeByStatus: <String, int>{'published': 2},
          categoryTotal: 1,
          categoryEmpty: 0,
          mediaTotal: 0,
          mediaBytes: 0,
          totalBytes: 4096,
        ),
      );

  /// 注入的预估回调：避免 widget 测试触发真实 SQLite（AppDatabase 懒加载
  /// open 在 FakeAsync 下无法完成，会让 teardown 的 close 挂起）。
  Future<BackupEstimate> fakeEstimate() async => const BackupEstimate(
        recipeTotal: 2,
        categoryTotal: 1,
        categoryEmpty: 0,
        mediaTotal: 0,
        mediaBytes: 0,
        estimatedTotalBytes: 4096,
      );

  Future<TestBackendHarness> createHarness(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    // 系统"减少动态"（PixelFloat 等装饰动画静止直达终态），
    // 避免加载态浮动动画让 pumpAndSettle 永不结束。
    tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    final harness = TestBackendHarness();
    addTearDown(() async {
      await harness.close();
      await tester.binding.setSurfaceSize(null);
    });
    return harness;
  }

  Widget wrap(Widget page) {
    return MaterialApp(theme: buildAiRecipeTheme(), home: page);
  }

  /// 成功摘要与另存为按钮位于 ListView 底部，可能超出 900px 视口
  /// （ListView 懒加载，不可见内容不渲染），先滚动到按钮。
  Future<void> scrollToSaveAs(WidgetTester tester) async {
    await tester.scrollUntilVisible(
      find.byKey(const Key('saveBackupAsButton')),
      120,
      scrollable: find.byType(Scrollable).first,
    );
  }

  testWidgets('没有最近备份时不显示另存为入口', (tester) async {
    final harness = await createHarness(tester);
    await tester.pumpWidget(
      wrap(
        BackupPage(
          backend: harness.root.backend,
          estimateBackup: fakeEstimate,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('上次备份已创建'), findsNothing);
    expect(find.byKey(const Key('saveBackupAsButton')), findsNothing);
  });

  testWidgets('另存为把最近备份复制到用户选择的位置', (tester) async {
    final harness = await createHarness(tester);
    final result = fakeResult();
    String? receivedSource;
    String? receivedFileName;
    const savedTo = 'D:/downloads/backup.airecipe-backup';

    await tester.pumpWidget(
      wrap(
        BackupPage(
          backend: harness.root.backend,
          estimateBackup: fakeEstimate,
          initialResult: result,
          saveBackupFile: ({
            required String sourcePath,
            required String fileName,
          }) async {
            receivedSource = sourcePath;
            receivedFileName = fileName;
            return savedTo;
          },
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    // 成功摘要可能位于视口外（ListView 懒加载），先滚动到另存为按钮。
    await scrollToSaveAs(tester);

    // 成功摘要展示文件名与完整路径，另存为按钮可用。
    // （message 为多行拼接文本，用 textContaining 匹配片段。）
    expect(find.textContaining(result.fileName), findsOneWidget);
    expect(find.textContaining(result.filePath), findsOneWidget);
    expect(find.byKey(const Key('saveBackupAsButton')), findsOneWidget);

    await tester.tap(find.byKey(const Key('saveBackupAsButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    // 回调收到源文件与文件名，并提示已另存位置。
    expect(receivedSource, result.filePath);
    expect(receivedFileName, result.fileName);
    expect(find.text('备份已另存到：$savedTo'), findsOneWidget);
  });

  testWidgets('用户在文件选择器中取消另存时不提示', (tester) async {
    final harness = await createHarness(tester);
    final result = fakeResult();

    await tester.pumpWidget(
      wrap(
        BackupPage(
          backend: harness.root.backend,
          estimateBackup: fakeEstimate,
          initialResult: result,
          saveBackupFile: ({
            required String sourcePath,
            required String fileName,
          }) async => null, // 用户取消
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    await scrollToSaveAs(tester);
    await tester.tap(find.byKey(const Key('saveBackupAsButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    expect(find.textContaining('备份已另存到'), findsNothing);
    expect(find.text('另存失败，请重试。'), findsNothing);
  });

  testWidgets('另存复制失败时给出中文错误提示', (tester) async {
    final harness = await createHarness(tester);
    final result = fakeResult();

    await tester.pumpWidget(
      wrap(
        BackupPage(
          backend: harness.root.backend,
          estimateBackup: fakeEstimate,
          initialResult: result,
          saveBackupFile: ({
            required String sourcePath,
            required String fileName,
          }) async {
            throw StateError('disk full');
          },
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    await scrollToSaveAs(tester);
    await tester.tap(find.byKey(const Key('saveBackupAsButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    expect(find.text('另存失败，请重试。'), findsOneWidget);
  });

  testWidgets('从备份导入返回后触发 onDataChanged 并重新预估', (tester) async {
    final harness = await createHarness(tester);
    var dataChangedCalls = 0;
    var estimateCalls = 0;

    await tester.pumpWidget(
      wrap(
        BackupPage(
          backend: harness.root.backend,
          // 计数注入：验证导入页返回后确实重新预估。
          estimateBackup: () async {
            estimateCalls += 1;
            return fakeEstimate();
          },
          // 计数注入：验证导入写入数据后通知上层（主界面/菜谱库）刷新，
          // 否则用户回主界面仍看到旧数据，误以为导入没有成功。
          onDataChanged: () => dataChangedCalls += 1,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    expect(estimateCalls, 1);

    // 进入「从备份导入」页（默认选择文件阶段）。
    await tester.tap(find.byKey(const Key('openImportButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(BackupImportPage), findsOneWidget);

    // 返回备份页：应触发 onDataChanged（主界面/菜谱库刷新）并重新预估。
    // 底层备份页 AppBar 也可能仍在树中，取最后一个（导入页顶部的返回钮）。
    await tester.tap(find.byTooltip('返回').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(BackupImportPage), findsNothing);
    expect(dataChangedCalls, 1);
    // 初始 1 次 + 导入返回后 1 次。
    expect(estimateCalls, 2);
  });
}
