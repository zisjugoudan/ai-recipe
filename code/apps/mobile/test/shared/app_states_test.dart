import 'package:ai_recipe/app/app_theme.dart';
import 'package:ai_recipe/shared/widgets/app_states.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap(Widget child) {
    return MaterialApp(
      theme: buildAiRecipeTheme(),
      home: Scaffold(body: Center(child: child)),
    );
  }

  testWidgets('empty state exposes its call to action', (tester) async {
    var actionCount = 0;

    await tester.pumpWidget(
      wrap(
        AppEmptyState(
          icon: Icons.menu_book_outlined,
          title: '\u8fd8\u6ca1\u6709\u83dc\u8c31',
          message:
              '\u5148\u8bb0\u5f55\u7b2c\u4e00\u9053\u559c\u6b22\u7684\u83dc\u3002',
          actionLabel: '\u6dfb\u52a0\u83dc\u8c31',
          onAction: () => actionCount++,
        ),
      ),
    );

    expect(find.text('\u8fd8\u6ca1\u6709\u83dc\u8c31'), findsOneWidget);
    await tester.tap(find.text('\u6dfb\u52a0\u83dc\u8c31'));
    await tester.pump();

    expect(actionCount, 1);
  });

  testWidgets('error state exposes retry action', (tester) async {
    var retryCount = 0;

    await tester.pumpWidget(
      wrap(
        AppErrorState(
          message: '\u83dc\u8c31\u52a0\u8f7d\u5931\u8d25',
          onRetry: () => retryCount++,
        ),
      ),
    );

    expect(find.text('\u83dc\u8c31\u52a0\u8f7d\u5931\u8d25'), findsOneWidget);
    await tester.tap(find.text('\u91cd\u65b0\u52a0\u8f7d'));
    await tester.pump();

    expect(retryCount, 1);
  });
}
