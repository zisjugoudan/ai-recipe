import 'package:ai_recipe/app/app_theme.dart';
import 'package:ai_recipe/features/session/welcome_page.dart';
import 'package:ai_recipe/shared/widgets/pixel_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const floatingAssets = <String>[
    'assets/welcome/float_leaf.png',
    'assets/welcome/float_hat.png',
    'assets/welcome/float_tomato.png',
    'assets/welcome/float_carrot.png',
    'assets/welcome/float_chili.png',
  ];

  Widget buildPage({
    Future<void> Function()? onContinueAsGuest,
    VoidCallback? onLogin,
    VoidCallback? onRetry,
    bool busy = false,
    bool disableAnimations = false,
    String? errorMessage,
  }) {
    return MaterialApp(
      theme: buildAiRecipeTheme(),
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(disableAnimations: disableAnimations),
          child: child!,
        );
      },
      home: WelcomePage(
        onContinueAsGuest: onContinueAsGuest ?? () async {},
        onLogin: onLogin ?? () {},
        onRetry: onRetry ?? () {},
        busy: busy,
        errorMessage: errorMessage,
      ),
    );
  }

  testWidgets('shows responsive hero and pixel-font brand title', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(buildPage());

    expect(find.byKey(const Key('welcomeTitle')), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label == '\u5df4\u98df' &&
            widget.properties.image == true,
      ),
      findsOneWidget,
    );
    // 品牌字现用像素字体 Text 渲染，应能找到「巴食」文本
    expect(find.text('\u5df4\u98df'), findsOneWidget);
    expect(
      find.text(
        '\u628a\u5c0f\u7ea2\u4e66 / \u6296\u97f3\u4e0a\u7684\u83dc\u8c31\uff0c\u6536\u8fdb\u4f60\u7684\u53e3\u888b\u53a8\u623f',
      ),
      findsOneWidget,
    );

    expect(
      find.image(const AssetImage('assets/welcome/cover.png')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('welcomeCoverFrame')), findsOneWidget);
    expect(find.byKey(const Key('welcomeSubtitleBubble')), findsOneWidget);

    for (final asset in floatingAssets) {
      expect(find.image(AssetImage(asset)), findsOneWidget);
    }
  });

  testWidgets('keeps floating assets adaptive at 320, 430 and 600 px', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final hatWidths = <double>[];

    for (final width in <double>[320, 430, 600]) {
      await tester.binding.setSurfaceSize(Size(width, 1000));
      await tester.pumpWidget(buildPage(disableAnimations: true));
      await tester.pump();

      expect(tester.takeException(), isNull, reason: 'width=$width');
      final titleRect = tester.getRect(
        find.byKey(const Key('welcomeTitle')),
      );
      expect(titleRect.left, greaterThanOrEqualTo(0));
      expect(titleRect.right, lessThanOrEqualTo(width));

      for (final asset in floatingAssets) {
        final rect = tester.getRect(find.image(AssetImage(asset)));
        expect(rect.width, greaterThan(0), reason: '$asset at width=$width');
        expect(rect.left, greaterThanOrEqualTo(0), reason: asset);
        expect(rect.right, lessThanOrEqualTo(width), reason: asset);
        expect(rect.overlaps(titleRect), isFalse, reason: asset);
      }

      hatWidths.add(
        tester
            .getSize(
              find.image(
                const AssetImage('assets/welcome/float_hat.png'),
              ),
            )
            .width,
      );
    }

    expect(hatWidths[1], greaterThan(hatWidths[0]));
    expect(hatWidths[2], greaterThan(hatWidths[1]));
  });

  testWidgets('stops floating motion when reduced motion is enabled', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(buildPage(disableAnimations: true));
    final hat = find.image(
      const AssetImage('assets/welcome/float_hat.png'),
    );
    final before = tester.getTopLeft(hat);

    await tester.pump(const Duration(seconds: 3));

    expect(tester.getTopLeft(hat), before);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows guest entry and invokes callback', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var continueCount = 0;

    await tester.pumpWidget(
      buildPage(onContinueAsGuest: () async => continueCount++),
    );

    expect(
      find.text('\u6e38\u5ba2\u7ee7\u7eed\uff0c\u5148\u901b\u901b'),
      findsOneWidget,
    );
    expect(find.text('\u94fe\u63a5\u4e00\u952e\u5bfc\u5165'), findsOneWidget);

    await tester.tap(
      find.text('\u6e38\u5ba2\u7ee7\u7eed\uff0c\u5148\u901b\u901b'),
    );
    await tester.pump();

    expect(continueCount, 1);
  });

  testWidgets('disables session actions while busy', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(buildPage(busy: true));

    final login = tester.widget<ButtonStyleButton>(
      find.byKey(const Key('welcomeLoginButton')),
    );
    final guest = tester.widget<ButtonStyleButton>(
      find.byKey(const Key('welcomeGuestButton')),
    );

    expect(login.onPressed, isNull);
    expect(guest.onPressed, isNull);
    expect(find.byType(PixelLoader), findsOneWidget);
  });

  testWidgets('shows startup error and retries', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var retryCount = 0;

    await tester.pumpWidget(
      buildPage(
        errorMessage: '\u672c\u5730\u4f1a\u8bdd\u52a0\u8f7d\u5931\u8d25',
        onRetry: () => retryCount++,
      ),
    );

    expect(
      find.text('\u672c\u5730\u4f1a\u8bdd\u52a0\u8f7d\u5931\u8d25'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('welcomeRetryButton')));
    await tester.pump();

    expect(retryCount, 1);
  });
}
