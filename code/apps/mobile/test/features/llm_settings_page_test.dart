import 'package:ai_recipe/data/llm_config_repository.dart';
import 'package:ai_recipe/domain/llm/llm_cancellation_token.dart';
import 'package:ai_recipe/domain/llm/llm_connection_config.dart';
import 'package:ai_recipe/domain/llm/llm_provider_type.dart';
import 'package:ai_recipe/features/llm_settings/llm_settings_page.dart';
import 'package:ai_recipe/providers/llm/llm_provider_factory.dart';
import 'package:ai_recipe/providers/llm/llm_transport.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_backend_harness.dart';

class FakeLlmConfigRepository implements LlmConfigRepository {
  LlmConnectionConfig? config;
  String apiKey = '';
  Object? loadError;
  Object? saveError;

  @override
  Future<void> clearApiKey(String secretRef) async {
    apiKey = '';
  }

  @override
  Future<LlmConnectionConfig?> load() async {
    if (loadError case final error?) throw error;
    return config;
  }

  @override
  Future<String> readApiKey(String secretRef) async => apiKey;

  @override
  Future<void> save(LlmConnectionConfig config, {String? apiKey}) async {
    if (saveError case final error?) throw error;
    this.config = config;
    if (apiKey != null) this.apiKey = apiKey;
  }
}

class RecordingLlmTransport implements LlmTransport {
  RecordingLlmTransport({this.statusCode = 200, this.responseBody});

  final int statusCode;
  final String? responseBody;
  final List<LlmHttpRequest> requests = <LlmHttpRequest>[];

  @override
  Future<LlmHttpResponse> send(
    LlmHttpRequest request, {
    LlmCancellationToken? cancellationToken,
  }) async {
    requests.add(request);
    return LlmHttpResponse(
      statusCode: statusCode,
      body: responseBody ?? '{"choices":[{"message":{"content":"OK"}}]}',
    );
  }

  @override
  Future<LlmDiagnosticReport> sendDiagnostic(
    LlmDiagnosticRequest request, {
    LlmCancellationToken? cancellationToken,
  }) async {
    return const LlmDiagnosticReport(
      records: [],
      totalElapsedMs: 0,
      succeeded: true,
    );
  }
}

void main() {
  Future<TestBackendHarness> pumpPage(
    WidgetTester tester, {
    required FakeLlmConfigRepository repository,
    RecordingLlmTransport? transport,
  }) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    final harness = TestBackendHarness(
      llmConfigRepository: repository,
      llmProviderFactory: LlmProviderFactory(
        transport: transport ?? RecordingLlmTransport(),
      ),
    );
    addTearDown(() async {
      await harness.close();
      await tester.binding.setSurfaceSize(null);
    });
    await tester.pumpWidget(
      MaterialApp(home: LlmSettingsPage(backend: harness.root.backend)),
    );
    await tester.pumpAndSettle();
    return harness;
  }

  testWidgets('shows protocol, address, key, model and action controls', (
    tester,
  ) async {
    final repository = FakeLlmConfigRepository();
    await pumpPage(tester, repository: repository);

    expect(find.byKey(const Key('providerTypeField')), findsOneWidget);
    expect(find.byKey(const Key('baseUrlField')), findsOneWidget);
    expect(find.byKey(const Key('apiKeyField')), findsOneWidget);
    expect(find.byKey(const Key('modelField')), findsOneWidget);
    expect(find.byKey(const Key('requestTimeoutField')), findsOneWidget);
    expect(find.byKey(const Key('testConnectionButton')), findsOneWidget);
    expect(find.byKey(const Key('saveConfigButton')), findsOneWidget);
  });

  testWidgets('tests and saves through facade without exposing repository', (
    tester,
  ) async {
    final repository = FakeLlmConfigRepository();
    final transport = RecordingLlmTransport();
    await pumpPage(tester, repository: repository, transport: transport);

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

    expect(transport.requests, hasLength(1));
    expect(
      transport.requests.single.uri.toString(),
      'http://192.168.1.10:11434/v1/chat/completions',
    );
    expect(
      transport.requests.single.headers['Authorization'],
      'Bearer widget-test-key-not-real',
    );
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
    final repository = FakeLlmConfigRepository()
      ..config = LlmConnectionConfig(
        id: 'saved-1',
        name: '已保存配置',
        providerType: LlmProviderType.gemini,
        baseUrl: LlmProviderType.gemini.defaultBaseUrl,
        secretRef: 'saved-secret',
        model: 'gemini-test',
      )
      ..apiKey = 'stored-test-key-not-real';

    await pumpPage(tester, repository: repository);

    final field = tester.widget<TextFormField>(
      find.byKey(const Key('apiKeyField')),
    );
    expect(field.controller!.text, isEmpty);
    expect(find.textContaining('已保存 Key'), findsOneWidget);
    expect(find.byKey(const Key('clearApiKeyButton')), findsOneWidget);
  });

  testWidgets('blank key keeps the stored key when saving', (tester) async {
    final repository = FakeLlmConfigRepository()
      ..config = LlmConnectionConfig(
        id: 'saved-2',
        name: '本地服务',
        providerType: LlmProviderType.openAiCompatible,
        baseUrl: 'http://127.0.0.1:11434/v1',
        secretRef: 'saved-secret-2',
        model: 'old-model',
      )
      ..apiKey = 'keep-this-test-key';

    await pumpPage(tester, repository: repository);
    await tester.enterText(find.byKey(const Key('modelField')), 'new-model');
    await tester.tap(find.byKey(const Key('saveConfigButton')));
    await tester.pumpAndSettle();

    expect(repository.config!.model, 'new-model');
    expect(repository.apiKey, 'keep-this-test-key');
  });

  testWidgets('clears a stored key through the facade', (tester) async {
    final repository = FakeLlmConfigRepository()
      ..config = LlmConnectionConfig(
        id: 'saved-3',
        name: '本地服务',
        providerType: LlmProviderType.openAiCompatible,
        baseUrl: 'http://127.0.0.1:11434/v1',
        secretRef: 'saved-secret-3',
        model: 'model',
      )
      ..apiKey = 'clear-this-test-key';

    await pumpPage(tester, repository: repository);
    await tester.tap(find.byKey(const Key('clearApiKeyButton')));
    await tester.pumpAndSettle();

    expect(repository.apiKey, isEmpty);
    expect(find.textContaining('已清除保存的 API Key'), findsOneWidget);
    expect(find.byKey(const Key('clearApiKeyButton')), findsNothing);
  });

  testWidgets('switches protocol default URL and applies timeout selection', (
    tester,
  ) async {
    final repository = FakeLlmConfigRepository();
    final transport = RecordingLlmTransport();
    await pumpPage(tester, repository: repository, transport: transport);

    await tester.tap(find.byKey(const Key('providerTypeField')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gemini 原生').last);
    await tester.pumpAndSettle();

    final urlField = tester.widget<TextFormField>(
      find.byKey(const Key('baseUrlField')),
    );
    expect(urlField.controller!.text, LlmProviderType.gemini.defaultBaseUrl);

    await tester.tap(find.byKey(const Key('providerTypeField')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OpenAI 兼容').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('modelField')),
      'timeout-model',
    );
    await tester.tap(find.byKey(const Key('requestTimeoutField')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('30 秒').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('testConnectionButton')));
    await tester.pumpAndSettle();

    expect(transport.requests.single.timeout, const Duration(seconds: 30));
  });

  testWidgets('request timeout offers up to 600 seconds for slow local models', (
    tester,
  ) async {
    final repository = FakeLlmConfigRepository();
    await pumpPage(tester, repository: repository);

    // 慢速本地模型（Ollama/LM Studio 等）生成完整菜谱 JSON 可能超过 120 秒，
    // 设置页必须提供 600 秒档位（BUG-008）。
    await tester.tap(find.byKey(const Key('requestTimeoutField')));
    await tester.pumpAndSettle();
    expect(find.text('180 秒'), findsOneWidget);
    expect(find.text('300 秒'), findsOneWidget);
    expect(find.text('600 秒'), findsOneWidget);
    await tester.tap(find.text('600 秒').last);
    await tester.pumpAndSettle();

    // 保存后配置应携带 600 秒超时。
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
      'slow-local-model',
    );
    await tester.tap(find.byKey(const Key('saveConfigButton')));
    await tester.pumpAndSettle();

    expect(repository.config, isNotNull);
    expect(
      repository.config!.requestTimeout,
      const Duration(seconds: 600),
    );
  });

  testWidgets('structured generation test sends text and shows elapsed', (
    tester,
  ) async {
    final repository = FakeLlmConfigRepository();
    final transport = RecordingLlmTransport();
    await pumpPage(tester, repository: repository, transport: transport);

    // 必填项：模型名称。
    await tester.enterText(
      find.byKey(const Key('modelField')),
      'structured-test-model',
    );
    // 输入要测试结构化的菜谱文本。
    await tester.enterText(
      find.byKey(const Key('structuredGenInputField')),
      '红烧肉。五花肉 500 克焯水，锅中放糖炒出糖色…',
    );
    await tester.tap(find.byKey(const Key('testStructuredGenButton')));
    await tester.pumpAndSettle();

    // 请求真实发出且携带用户文本；页面展示耗时（毫秒）与结果。
    expect(transport.requests, isNotEmpty);
    final lastBody = transport.requests.last.body;
    expect(lastBody, contains('红烧肉'));
    expect(find.byKey(const Key('structuredGenElapsedText')), findsOneWidget);
    expect(find.textContaining('耗时'), findsOneWidget);
  });

  testWidgets('structured generation test reports empty input', (
    tester,
  ) async {
    final repository = FakeLlmConfigRepository();
    await pumpPage(tester, repository: repository);

    await tester.tap(find.byKey(const Key('testStructuredGenButton')));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('请先输入要测试结构化的菜谱文本'),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('testStructuredGenButton')),
      findsOneWidget,
    );
  });

  testWidgets('connection failure never renders the entered key', (
    tester,
  ) async {
    const key = 'never-render-this-test-key';
    final repository = FakeLlmConfigRepository();
    final transport = RecordingLlmTransport(
      statusCode: 401,
      responseBody: 'unauthorized: $key',
    );
    await pumpPage(tester, repository: repository, transport: transport);

    await tester.enterText(find.byKey(const Key('apiKeyField')), key);
    await tester.enterText(
      find.byKey(const Key('modelField')),
      'private-model',
    );
    await tester.tap(find.byKey(const Key('testConnectionButton')));
    await tester.pumpAndSettle();

    final status = tester.widget<Text>(find.byKey(const Key('statusMessage')));
    expect(status.data, contains('API Key 无效'));
    expect(status.data, isNot(contains(key)));
    expect(find.byKey(const Key('apiKeyField')), findsOneWidget);
  });
}
