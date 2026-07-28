import 'package:ai_recipe/data/llm_config_repository.dart';
import 'package:ai_recipe/domain/llm/llm_connection_config.dart';
import 'package:ai_recipe/domain/llm/llm_models.dart';
import 'package:ai_recipe/domain/llm/llm_provider.dart';
import 'package:ai_recipe/domain/llm/llm_provider_type.dart';
import 'package:ai_recipe/features/llm_settings/llm_settings_page.dart';
import 'package:ai_recipe/domain/llm/llm_cancellation_token.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeLlmConfigRepository implements LlmConfigRepository {
  LlmConnectionConfig? config;
  String apiKey = '';

  @override
  Future<void> clearApiKey(String secretRef) async {
    apiKey = '';
  }

  @override
  Future<LlmConnectionConfig?> load() async => config;

  @override
  Future<String> readApiKey(String secretRef) async => apiKey;

  @override
  Future<void> save(LlmConnectionConfig config, {String? apiKey}) async {
    this.config = config;
    if (apiKey != null) this.apiKey = apiKey;
  }
}

class FakeSuccessfulProvider extends LlmProvider {
  int callCount = 0;
  String? receivedKey;

  @override
  Future<LlmGenerationResult> generate({
    required LlmConnectionConfig config,
    required String apiKey,
    required LlmGenerationRequest request,
    LlmCancellationToken? cancellationToken,
  }) async {
    callCount++;
    receivedKey = apiKey;
    return const LlmGenerationResult(text: 'OK');
  }
}

void main() {
  testWidgets('shows protocol, address, key, model and action controls', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = FakeLlmConfigRepository();

    await tester.pumpWidget(
      MaterialApp(home: LlmSettingsPage(repository: repository)),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('providerTypeField')), findsOneWidget);
    expect(find.byKey(const Key('baseUrlField')), findsOneWidget);
    expect(find.byKey(const Key('apiKeyField')), findsOneWidget);
    expect(find.byKey(const Key('modelField')), findsOneWidget);
    expect(find.byKey(const Key('testConnectionButton')), findsOneWidget);
    expect(find.byKey(const Key('saveConfigButton')), findsOneWidget);
  });

  testWidgets('tests and saves a custom OpenAI-compatible configuration', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = FakeLlmConfigRepository();
    final provider = FakeSuccessfulProvider();

    await tester.pumpWidget(
      MaterialApp(
        home: LlmSettingsPage(
          repository: repository,
          providerBuilder: (_) => provider,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('baseUrlField')),
      'http://192.168.1.10:11434/v1',
    );
    await tester.enterText(
      find.byKey(const Key('apiKeyField')),
      'widget-test-key-not-real',
    );
    await tester.enterText(
      find.byKey(const Key('modelField')),
      'local-recipe-model',
    );
    await tester.tap(find.byKey(const Key('testConnectionButton')));
    await tester.pumpAndSettle();

    expect(provider.callCount, 1);
    expect(provider.receivedKey, 'widget-test-key-not-real');
    expect(find.textContaining('连接成功'), findsOneWidget);

    await tester.tap(find.byKey(const Key('saveConfigButton')));
    await tester.pumpAndSettle();

    expect(repository.config, isNotNull);
    expect(repository.config!.providerType, LlmProviderType.openAiCompatible);
    expect(repository.config!.baseUrl, 'http://192.168.1.10:11434/v1');
    expect(repository.config!.model, 'local-recipe-model');
    expect(repository.apiKey, 'widget-test-key-not-real');
    expect(repository.config!.toJson().containsKey('apiKey'), isFalse);
  });

  testWidgets('does not refill a stored API key into the text field', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = FakeLlmConfigRepository()
      ..config = LlmConnectionConfig(
        id: 'saved-1',
        name: '已保存配置',
        providerType: LlmProviderType.gemini,
        baseUrl: 'https://generativelanguage.googleapis.com/v1beta',
        secretRef: 'saved-secret',
        model: 'gemini-test',
      )
      ..apiKey = 'stored-test-key-not-real';

    await tester.pumpWidget(
      MaterialApp(home: LlmSettingsPage(repository: repository)),
    );
    await tester.pumpAndSettle();

    final field = tester.widget<TextFormField>(
      find.byKey(const Key('apiKeyField')),
    );
    expect(field.controller!.text, isEmpty);
    expect(find.textContaining('已保存 Key'), findsOneWidget);
    expect(find.byKey(const Key('clearApiKeyButton')), findsOneWidget);
  });
}
