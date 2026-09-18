import 'package:ai_recipe/features/home/home_page.dart';
import 'package:ai_recipe/features/library/recipe_library_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_backend_harness.dart';

void main() {
  Future<TestBackendHarness> createHarness(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    final harness = TestBackendHarness();
    addTearDown(() async {
      await harness.close();
      await tester.binding.setSurfaceSize(null);
    });
    return harness;
  }

  testWidgets(
    'home refresh token reload does not return a Future from setState',
    (tester) async {
      final harness = await createHarness(tester);

      Widget buildPage(int refreshToken) => MaterialApp(
        home: HomePage(
          backend: harness.root.backend,
          refreshToken: refreshToken,
          onOpenLibrary: () {},
          onOpenImportTask: (_) async {},
          onOpenImportTasks: () {},
          onQuickLinkImport: () {},
          onQuickClipboardImport: () {},
          onQuickImageImport: () {},
          onQuickManualCreate: () {},
          onOpenRecipe: (_) {},
        ),
      );

      await tester.pumpWidget(buildPage(0));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(buildPage(1));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('晚上好，今天吃什么？'), findsOneWidget);
    },
  );

  testWidgets(
    'recipe library refresh token reload does not return a Future from setState',
    (tester) async {
      final harness = await createHarness(tester);

      Widget buildPage(int refreshToken) => MaterialApp(
        home: Scaffold(
          body: RecipeLibraryPage(
            backend: harness.root.backend,
            refreshToken: refreshToken,
            onAddRecipe: () {},
            onOpenRecipeId: (_) {},
            onDataChanged: () {},
          ),
        ),
      );

      await tester.pumpWidget(buildPage(0));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(buildPage(1));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('菜谱库'), findsOneWidget);
    },
  );
}
