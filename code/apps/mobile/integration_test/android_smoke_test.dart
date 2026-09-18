import 'package:ai_recipe/app/app.dart';
import 'package:ai_recipe/data/local/app_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(_resetAndroidTestState);

  testWidgets('Android 游客主链可创建、查看、删除恢复并打开设置页', (tester) async {
    debugPrint('[android-smoke] 01 launch app');
    await tester.pumpWidget(const AiRecipeApp());

    await _pumpUntilFound(tester, find.byKey(const Key('welcomeGuestButton')));
    expect(find.text('登录并使用云端能力'), findsOneWidget);
    debugPrint('[android-smoke] 02 continue as guest');
    await tester.tap(find.byKey(const Key('welcomeGuestButton')));

    await _pumpUntilFound(tester, find.byKey(const Key('homeTab')));
    expect(find.text('首页'), findsWidgets);

    debugPrint('[android-smoke] 03 open add tab');
    await tester.tap(find.byKey(const Key('addTab')));
    await _pumpUntilFound(
      tester,
      find.byKey(const Key('addRecipePrimaryButton')),
    );
    await tester.tap(find.text('手动添加'));
    await _settleBriefly(tester);
    expect(find.byKey(const ValueKey('manual-recipe')), findsOneWidget);

    debugPrint('[android-smoke] 04 open manual editor');
    await tester.tap(find.byKey(const Key('addRecipePrimaryButton')));
    await _pumpUntilFound(tester, find.byKey(const Key('recipeTitleField')));
    expect(find.text('新建菜谱'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('recipeTitleField')),
      'Android 冒烟番茄炒蛋',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await _settleBriefly(tester);

    await tester.scrollUntilVisible(
      find.byKey(const Key('ingredientsSectionTitle')),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(
      find.byKey(const ValueKey('recipeIngredientNameField-0')),
      '番茄',
    );
    await tester.enterText(
      find.byKey(const ValueKey('recipeIngredientQuantityField-0')),
      '2',
    );
    await tester.enterText(
      find.byKey(const ValueKey('recipeIngredientUnitField-0')),
      '个',
    );

    await tester.scrollUntilVisible(
      find.byKey(const Key('stepsSectionTitle')),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(
      find.byKey(const ValueKey('recipeStepDescriptionField-0')),
      '鸡蛋炒熟，番茄炒软后混合调味',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await _settleBriefly(tester);

    debugPrint('[android-smoke] 05 recipe form completed');
    debugPrint('[android-smoke] 06 save recipe');
    await tester.tap(find.byKey(const Key('saveRecipeButton')));
    await _pumpUntilFound(tester, find.text('Android 冒烟番茄炒蛋'));
    expect(find.byKey(const Key('libraryTab')), findsOneWidget);

    debugPrint('[android-smoke] 07 open recipe detail');
    await tester.tap(find.text('Android 冒烟番茄炒蛋').first);
    await _pumpUntilFound(tester, find.byKey(const Key('recipeDetailTitle')));
    expect(find.text('番茄'), findsOneWidget);
    expect(find.textContaining('鸡蛋炒熟'), findsOneWidget);

    debugPrint('[android-smoke] 08 favorite recipe');
    await tester.tap(find.byTooltip('收藏'));
    await _pumpUntilFound(tester, find.byTooltip('取消收藏'));

    await tester.scrollUntilVisible(
      find.text('移到回收站'),
      350,
      scrollable: find.byType(Scrollable).first,
    );
    debugPrint('[android-smoke] 09 move recipe to trash');
    await tester.tap(find.text('移到回收站'));
    await _pumpUntilFound(
      tester,
      find.byKey(const Key('confirmSoftDeleteRecipe')),
    );
    await tester.tap(find.byKey(const Key('confirmSoftDeleteRecipe')));
    await _pumpUntilFound(tester, find.text('还没有菜谱'));

    debugPrint('[android-smoke] 10 open profile and settings');
    await tester.tap(find.byKey(const Key('profileTab')));
    await _pumpUntilFound(tester, find.text('GUEST'));

    debugPrint('[android-smoke] 11 verify LLM settings');
    await _openAndVerifyLlmSettings(tester);
    debugPrint('[android-smoke] 12 verify OCR settings');
    await _openAndVerifyOcrSettings(tester);
    debugPrint('[android-smoke] 13 verify privacy persistence');
    await _openAndVerifyPrivacySettings(tester);

    debugPrint('[android-smoke] 14 restore from trash');
    await _ensureVisibleAndTap(tester, find.byKey(const Key('openTrashTile')));
    await _pumpUntilFound(tester, find.text('Android 冒烟番茄炒蛋'));
    await tester.tap(find.text('恢复'));
    await _pumpUntilFound(tester, find.text('回收站是空的'));
    await tester.pageBack();
    await _pumpUntilFound(tester, find.byKey(const Key('profileTab')));
    debugPrint('[android-smoke] 15 recipe restored');

    await tester.tap(find.byKey(const Key('libraryTab')));
    await _pumpUntilFound(tester, find.text('Android 冒烟番茄炒蛋'));
    expect(find.text('1 道菜谱'), findsOneWidget);
    debugPrint('[android-smoke] 16 smoke flow completed');
  });
}

Future<void> _openAndVerifyLlmSettings(WidgetTester tester) async {
  await _ensureVisibleAndTap(
    tester,
    find.byKey(const Key('openLlmSettingsTile')),
  );
  await _pumpUntilFound(tester, find.byKey(const Key('apiKeyField')));
  expect(find.text('自定义 LLM API'), findsOneWidget);
  final apiKeyEditableText = tester.widget<EditableText>(
    find.descendant(
      of: find.byKey(const Key('apiKeyField')),
      matching: find.byType(EditableText),
    ),
  );
  expect(apiKeyEditableText.obscureText, isTrue);
  await tester.pageBack();
  await _pumpUntilFound(tester, find.byKey(const Key('openLlmSettingsTile')));
}

Future<void> _openAndVerifyOcrSettings(WidgetTester tester) async {
  await _ensureVisibleAndTap(
    tester,
    find.byKey(const Key('openOcrSettingsTile')),
  );
  await _pumpUntilFound(tester, find.byKey(const Key('ocrModelStatus')));
  expect(find.text('OCR 引擎'), findsOneWidget);
  expect(
    find.byKey(const Key('ocrManifestUnavailableMessage')),
    findsOneWidget,
  );
  await tester.pageBack();
  await _pumpUntilFound(tester, find.byKey(const Key('openOcrSettingsTile')));
}

Future<void> _openAndVerifyPrivacySettings(WidgetTester tester) async {
  await _ensureVisibleAndTap(
    tester,
    find.byKey(const Key('openPrivacySettingsTile')),
  );
  await _pumpUntilFound(
    tester,
    find.byKey(const Key('allowImageUploadSwitch')),
  );
  expect(find.text('隐私与上传权限'), findsOneWidget);
  expect(
    tester
        .widget<SwitchListTile>(find.byKey(const Key('allowImageUploadSwitch')))
        .value,
    isFalse,
  );
  await tester.tap(find.byKey(const Key('allowImageUploadSwitch')));
  await _settleBriefly(tester);
  expect(
    tester
        .widget<SwitchListTile>(find.byKey(const Key('allowImageUploadSwitch')))
        .value,
    isTrue,
  );
  await tester.pageBack();
  await _pumpUntilFound(
    tester,
    find.byKey(const Key('openPrivacySettingsTile')),
  );

  await _ensureVisibleAndTap(
    tester,
    find.byKey(const Key('openPrivacySettingsTile')),
  );
  await _pumpUntilFound(
    tester,
    find.byKey(const Key('allowImageUploadSwitch')),
  );
  expect(
    tester
        .widget<SwitchListTile>(find.byKey(const Key('allowImageUploadSwitch')))
        .value,
    isTrue,
  );
  await tester.pageBack();
  await _pumpUntilFound(
    tester,
    find.byKey(const Key('openPrivacySettingsTile')),
  );
}

Future<void> _ensureVisibleAndTap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await _settleBriefly(tester);
  await tester.tap(finder);
  await tester.pump();
}

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (finder.evaluate().isEmpty && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(finder, findsWidgets);
  await _settleBriefly(tester);
}

Future<void> _settleBriefly(
  WidgetTester tester, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  final deadline = DateTime.now().add(timeout);
  do {
    await tester.pump(const Duration(milliseconds: 100));
    if (!tester.binding.hasScheduledFrame) {
      return;
    }
  } while (DateTime.now().isBefore(deadline));
}

Future<void> _resetAndroidTestState() async {
  final preferences = SharedPreferencesAsync();
  await preferences.clear();
  await const FlutterSecureStorage().deleteAll();

  final databasePath = path.join(
    await getDatabasesPath(),
    AppDatabase.defaultFileName,
  );
  await deleteDatabase(databasePath);
}
