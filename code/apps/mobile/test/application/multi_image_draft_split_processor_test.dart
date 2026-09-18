import 'package:ai_recipe/application/importing/import_pipeline_contracts.dart';
import 'package:ai_recipe/application/importing/multi_image_draft_split_processor.dart';
import 'package:ai_recipe/domain/importing/import_cancellation_token.dart';
import 'package:ai_recipe/domain/importing/import_content.dart';
import 'package:ai_recipe/domain/importing/import_task.dart';
import 'package:ai_recipe/domain/llm/llm_cancellation_token.dart';
import 'package:ai_recipe/domain/llm/llm_connection_config.dart';
import 'package:ai_recipe/domain/llm/llm_models.dart';
import 'package:ai_recipe/domain/llm/llm_provider.dart';
import 'package:ai_recipe/domain/llm/llm_provider_exception.dart';
import 'package:ai_recipe/domain/llm/llm_provider_type.dart';
import 'package:flutter_test/flutter_test.dart';

/// 可编程纯文本 LLM：返回配置的分组 JSON 或抛出错误。
class FakeGroupingLlmProvider implements LlmProvider {
  FakeGroupingLlmProvider({this.responseText, this.error});

  String? responseText;
  Object? error;
  final List<String> prompts = <String>[];

  @override
  Future<LlmGenerationResult> generate({
    required LlmConnectionConfig config,
    required String apiKey,
    required LlmGenerationRequest request,
    LlmCancellationToken? cancellationToken,
  }) async {
    prompts.add(request.messages.map((m) => m.content).join('\n'));
    if (error != null) throw error!;
    return LlmGenerationResult(text: responseText ?? '{"mode":"combined"}');
  }
}

/// 记录收到的内容并递增返回草稿 ID。
class RecordingSingleDraftProcessor implements ImportContentProcessor {
  final List<ImportContent> received = <ImportContent>[];

  @override
  Future<ImportRecipeDraftResult> process(
    ImportContent content, {
    required ImportPipelineProgressCallback onProgress,
    ImportCancellationToken? cancellationToken,
  }) async {
    received.add(content);
    return ImportRecipeDraftResult(recipeId: 'draft-${received.length}');
  }
}

void main() {
  final config = LlmConnectionConfig(
    id: 'llm-1',
    name: 'llm',
    providerType: LlmProviderType.openAiCompatible,
    baseUrl: 'https://example.com/v1',
    secretRef: 's1',
    model: 'recipe-model',
  );

  /// 构造两张图（order 0/1）各带转录片段的导入内容。
  ImportContent sampleContent({bool withAuthorText = true}) {
    final source = ImportSourceLink.parse('https://example.com/multi');
    return ImportContent(
      source: source,
      resolvedUrl: source.normalizedUrl,
      contentType: ImportContentType.imageGallery,
      capturedAt: DateTime.utc(2026, 8, 5, 10),
      title: withAuthorText ? '多图菜谱合集' : null,
      description: withAuthorText ? '包含两份独立菜谱' : null,
      textFragments: <ImportTextFragment>[
        ImportTextFragment(
          kind: ImportTextFragmentKind.body,
          text: '【菜谱一】红烧肉：五花肉500克、生抽、糖。步骤：1.焯水 2.炒糖色 3.焖煮',
          order: 0,
          sourceMediaOrder: 0,
          sourceType: ImportTextFragmentSourceType.ocr,
        ),
        ImportTextFragment(
          kind: ImportTextFragmentKind.body,
          text: '【菜谱二】清蒸鱼：鲈鱼1条、姜葱。步骤：1.腌制 2.上锅蒸8分钟',
          order: 1,
          sourceMediaOrder: 1,
          sourceType: ImportTextFragmentSourceType.ocr,
        ),
      ],
      media: <ImportMediaReference>[
        ImportMediaReference(
          kind: ImportMediaKind.image,
          remoteUrl: 'https://example.com/1.jpg',
          order: 0,
        ),
        ImportMediaReference(
          kind: ImportMediaKind.image,
          remoteUrl: 'https://example.com/2.jpg',
          order: 1,
        ),
      ],
      warnings: const <ImportContentWarning>{
        ImportContentWarning.requiresOcr,
        ImportContentWarning.partialContent,
      },
    );
  }

  ImportRecipeDraftResult run(
    MultiImageDraftSplitProcessor processor,
    ImportContent content,
  ) {
    return processor.process(content, onProgress: (_, _, [detail]) async {}) as dynamic;
  }

  test('independent：两张图各自生成独立草稿（一主一附加）', () async {
    final downstream = RecordingSingleDraftProcessor();
    final provider = FakeGroupingLlmProvider(
      responseText: '{"mode":"independent","reason":"每张图都是完整菜谱"}',
    );
    final processor = MultiImageDraftSplitProcessor(
      provider: provider,
      config: config,
      apiKey: 'key',
      downstream: downstream,
    );

    final result = await run(processor, sampleContent());

    expect(result.recipeId, 'draft-1');
    expect(result.additionalRecipeIds, <String>['draft-2']);
    expect(downstream.received.length, 2);
    // 第一份草稿含作者原文与第一张图转录；第二份只含第二张图转录。
    final first = downstream.received.first;
    expect(first.title, '多图菜谱合集');
    expect(first.textFragments.map((f) => f.sourceMediaOrder), contains(0));
    expect(first.textFragments.map((f) => f.sourceMediaOrder), isNot(contains(1)));
    final second = downstream.received.last;
    expect(second.title, isNull);
    expect(second.textFragments.map((f) => f.sourceMediaOrder), <int?>[1]);
  });

  test('combined：两张图合并生成单草稿', () async {
    final downstream = RecordingSingleDraftProcessor();
    final processor = MultiImageDraftSplitProcessor(
      provider: FakeGroupingLlmProvider(
        responseText: '{"mode":"combined","reason":"两张图是一份菜谱的步骤"}',
      ),
      config: config,
      apiKey: 'key',
      downstream: downstream,
    );

    final result = await run(processor, sampleContent());

    expect(result.recipeId, 'draft-1');
    expect(result.additionalRecipeIds, isEmpty);
    expect(downstream.received.length, 1);
    expect(
      downstream.received.single.textFragments.map((f) => f.sourceMediaOrder),
      <int?>[0, 1],
    );
  });

  test('mixed：按图号分组合成', () async {
    final downstream = RecordingSingleDraftProcessor();
    final processor = MultiImageDraftSplitProcessor(
      provider: FakeGroupingLlmProvider(
        responseText: '{"mode":"mixed","groups":[[1],[0]],"reason":"第二张独立，第一张单独"}',
      ),
      config: config,
      apiKey: 'key',
      downstream: downstream,
    );

    final result = await run(processor, sampleContent());

    expect(result.recipeId, 'draft-1');
    expect(result.additionalRecipeIds, <String>['draft-2']);
    expect(downstream.received.length, 2);
    // 第一组是图 1（作者原文并入第一份），第二组是图 0。
    expect(downstream.received.first.title, '多图菜谱合集');
    expect(
      downstream.received.first.textFragments.map((f) => f.sourceMediaOrder),
      <int?>[1],
    );
    expect(
      downstream.received.last.textFragments.map((f) => f.sourceMediaOrder),
      <int?>[0],
    );
  });

  test('分组判断失败：回退为全部合并，不丢弃内容', () async {
    final downstream = RecordingSingleDraftProcessor();
    final processor = MultiImageDraftSplitProcessor(
      provider: FakeGroupingLlmProvider(
        error: const LlmProviderException(
          LlmProviderErrorKind.network,
          '网络失败',
        ),
      ),
      config: config,
      apiKey: 'key',
      downstream: downstream,
    );

    final result = await run(processor, sampleContent());

    expect(result.recipeId, 'draft-1');
    expect(result.additionalRecipeIds, isEmpty);
    expect(downstream.received.length, 1);
    expect(
      downstream.received.single.textFragments.map((f) => f.sourceMediaOrder),
      <int?>[0, 1],
    );
  });

  test('分组响应无法解析：回退为全部合并', () async {
    final downstream = RecordingSingleDraftProcessor();
    final processor = MultiImageDraftSplitProcessor(
      provider: FakeGroupingLlmProvider(responseText: '我不知道'),
      config: config,
      apiKey: 'key',
      downstream: downstream,
    );

    final result = await run(processor, sampleContent());

    expect(result.recipeId, 'draft-1');
    expect(downstream.received.length, 1);
  });

  test('单图转录：不做分组判断，直接生成单草稿', () async {
    final downstream = RecordingSingleDraftProcessor();
    final provider = FakeGroupingLlmProvider();
    final processor = MultiImageDraftSplitProcessor(
      provider: provider,
      config: config,
      apiKey: 'key',
      downstream: downstream,
    );
    final source = ImportSourceLink.parse('https://example.com/single');
    final content = ImportContent(
      source: source,
      resolvedUrl: source.normalizedUrl,
      contentType: ImportContentType.imageGallery,
      capturedAt: DateTime.utc(2026, 8, 5, 10),
      textFragments: <ImportTextFragment>[
        ImportTextFragment(
          kind: ImportTextFragmentKind.body,
          text: '红烧肉做法…',
          order: 0,
          sourceMediaOrder: 0,
          sourceType: ImportTextFragmentSourceType.ocr,
        ),
      ],
      media: <ImportMediaReference>[
        ImportMediaReference(
          kind: ImportMediaKind.image,
          remoteUrl: 'https://example.com/1.jpg',
          order: 0,
        ),
      ],
      warnings: const <ImportContentWarning>{
        ImportContentWarning.requiresOcr,
      },
    );

    final result = await run(processor, content);

    expect(result.recipeId, 'draft-1');
    expect(provider.prompts, isEmpty, reason: '单图不发起分组判断调用');
    expect(downstream.received.length, 1);
  });
}
