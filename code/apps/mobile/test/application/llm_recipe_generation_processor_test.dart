import 'package:ai_recipe/application/importing/import_pipeline_contracts.dart';
import 'package:ai_recipe/application/importing/llm_recipe_generation_processor.dart';
import 'package:ai_recipe/domain/importing/import_cancellation_token.dart';
import 'package:ai_recipe/domain/importing/import_content.dart';
import 'package:ai_recipe/domain/importing/import_task.dart';
import 'package:ai_recipe/domain/llm/llm_connection_config.dart';
import 'package:ai_recipe/domain/llm/llm_models.dart';
import 'package:ai_recipe/domain/llm/llm_provider_exception.dart';
import 'package:ai_recipe/domain/llm/llm_provider_type.dart';
import 'package:ai_recipe/domain/ocr/ocr_models.dart';
import 'package:ai_recipe/domain/ocr/ocr_provider_exception.dart';
import 'package:ai_recipe/domain/ocr/ocr_remote_image_stager.dart';
import 'package:ai_recipe/domain/recipe/recipe.dart';
import 'package:ai_recipe/domain/recipe/recipe_cover_image_storer.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_recipe_generation_dependencies.dart';

void main() {
  test('generates, validates and saves a local-only recipe draft', () async {
    final provider = FakeLlmProvider((config, apiKey, request, token) async {
      expect(apiKey, 'secret-key');
      return const LlmGenerationResult(text: validRecipeGenerationJson);
    });
    final repository = MemoryRecipeRepository();
    final ids = <String>['recipe-1', 'ingredient-1', 'step-1'].iterator;
    final stages = <(ImportTaskStage, double)>[];
    final processor = _processor(
      provider: provider,
      repository: repository,
      idGenerator: () {
        ids.moveNext();
        return ids.current;
      },
    );

    final result = await processor.process(
      _textContent(),
      onProgress: (stage, progress, [detail]) async {
        stages.add((stage, progress));
      },
    );

    expect(result.recipeId, 'recipe-1');
    expect(provider.callCount, 1);
    expect(stages, <(ImportTaskStage, double)>[
      (ImportTaskStage.generating, 0.65),
      (ImportTaskStage.generating, 0.88),
      (ImportTaskStage.generating, 0.9),
    ]);
    final recipe = repository.recipes['recipe-1']!;
    expect(recipe.status, RecipeStatus.draft);
    expect(recipe.favorite, isFalse);
    expect(recipe.sourceId, 'https://www.xiaohongshu.com/explore/abc');
    expect(recipe.coverImage, 'https://example.com/cover.jpg');
    expect(recipe.categoryIds, isEmpty);
    expect(recipe.ingredients.single.id, 'ingredient-1');
    expect(recipe.ingredients.single.sortOrder, 0);
    expect(recipe.steps.single.id, 'step-1');
    expect(recipe.steps.single.stepNumber, 1);
    expect(recipe.createdAt, DateTime.utc(2026, 7, 28, 16));
    expect(recipe.updatedAt, recipe.createdAt);
  });

  test('accepts controlled model wrappers before saving the draft', () async {
    final repository = MemoryRecipeRepository();
    final processor = _processor(
      provider: FakeLlmProvider((config, apiKey, request, token) async {
        return const LlmGenerationResult(
          text:
              '<think>Validate the recipe fields.</think>\n'
              'Here is the recipe JSON:\n'
              '```json\n$validRecipeGenerationJson\n```',
        );
      }),
      repository: repository,
    );

    final result = await processor.process(
      _textContent(),
      onProgress: _ignoreProgress,
    );

    expect(repository.recipes[result.recipeId]?.title, '番茄炒蛋');
  });
  test('maps invalid JSON to non-retryable schemaInvalid', () async {
    final processor = _processor(
      provider: FakeLlmProvider((config, apiKey, request, token) async {
        return const LlmGenerationResult(text: '{invalid');
      }),
      repository: MemoryRecipeRepository(),
    );

    expect(
      () => processor.process(_textContent(), onProgress: _ignoreProgress),
      throwsA(
        isA<ImportPipelineException>()
            .having(
              (error) => error.code,
              'code',
              ImportTaskErrorCode.schemaInvalid,
            )
            .having((error) => error.retryable, 'retryable', isFalse),
      ),
    );
  });

  test(
    'maps network and timeout errors without exposing provider message',
    () async {
      for (final testCase in <(LlmProviderErrorKind, ImportTaskErrorCode)>[
        (LlmProviderErrorKind.network, ImportTaskErrorCode.networkUnavailable),
        (LlmProviderErrorKind.timeout, ImportTaskErrorCode.timeout),
      ]) {
        final processor = _processor(
          provider: FakeLlmProvider((config, apiKey, request, token) async {
            throw LlmProviderException(
              testCase.$1,
              'sensitive provider response with token=abc',
            );
          }),
          repository: MemoryRecipeRepository(),
        );

        try {
          await processor.process(_textContent(), onProgress: _ignoreProgress);
          fail('Expected ImportPipelineException');
        } on ImportPipelineException catch (error) {
          expect(error.code, testCase.$2);
          expect(error.retryable, isTrue);
          expect(error.message, isNot(contains('sensitive')));
          expect(error.message, isNot(contains('token=abc')));
        }
      }
    },
  );

  test('maps repository failure to retryable storageFailure', () async {
    final repository = MemoryRecipeRepository()
      ..upsertError = StateError('disk');
    final processor = _processor(
      provider: FakeLlmProvider((config, apiKey, request, token) async {
        return const LlmGenerationResult(text: validRecipeGenerationJson);
      }),
      repository: repository,
    );

    expect(
      () => processor.process(_textContent(), onProgress: _ignoreProgress),
      throwsA(
        isA<ImportPipelineException>()
            .having(
              (error) => error.code,
              'code',
              ImportTaskErrorCode.storageFailure,
            )
            .having((error) => error.retryable, 'retryable', isTrue),
      ),
    );
  });

  test(
    'does not call LLM when media requires OCR and no text exists',
    () async {
      final provider = FakeLlmProvider((config, apiKey, request, token) async {
        return const LlmGenerationResult(text: validRecipeGenerationJson);
      });
      final processor = _processor(
        provider: provider,
        repository: MemoryRecipeRepository(),
      );
      final content = ImportContent(
        source: ImportSourceLink.parse(
          'https://www.xiaohongshu.com/explore/image',
        ),
        resolvedUrl: 'https://www.xiaohongshu.com/explore/image',
        contentType: ImportContentType.imageGallery,
        capturedAt: DateTime.utc(2026, 7, 28),
        media: <ImportMediaReference>[
          ImportMediaReference(
            kind: ImportMediaKind.image,
            remoteUrl: 'https://example.com/image.jpg',
            order: 0,
          ),
        ],
        warnings: const <ImportContentWarning>{
          ImportContentWarning.requiresOcr,
        },
      );

      expect(
        () => processor.process(content, onProgress: _ignoreProgress),
        throwsA(
          isA<ImportPipelineException>().having(
            (error) => error.code,
            'code',
            ImportTaskErrorCode.ocrFailed,
          ),
        ),
      );
      expect(provider.callCount, 0);
    },
  );

  test('does not treat a page title as OCR or ASR recipe text', () async {
    for (final testCase
        in <(ImportContentWarning, ImportMediaKind, ImportTaskErrorCode)>[
          (
            ImportContentWarning.requiresOcr,
            ImportMediaKind.image,
            ImportTaskErrorCode.ocrFailed,
          ),
          (
            ImportContentWarning.requiresAsr,
            ImportMediaKind.video,
            ImportTaskErrorCode.asrFailed,
          ),
        ]) {
      final provider = FakeLlmProvider((config, apiKey, request, token) async {
        return const LlmGenerationResult(text: validRecipeGenerationJson);
      });
      final processor = _processor(
        provider: provider,
        repository: MemoryRecipeRepository(),
      );
      final content = ImportContent(
        source: ImportSourceLink.parse(
          'https://www.douyin.com/video/title-only',
        ),
        resolvedUrl: 'https://www.douyin.com/video/title-only',
        contentType: ImportContentType.video,
        title: '????',
        capturedAt: DateTime.utc(2026, 7, 28),
        media: <ImportMediaReference>[
          ImportMediaReference(
            kind: testCase.$2,
            remoteUrl: 'https://example.com/source-media',
            order: 0,
          ),
        ],
        warnings: <ImportContentWarning>{testCase.$1},
      );

      expect(
        () => processor.process(content, onProgress: _ignoreProgress),
        throwsA(
          isA<ImportPipelineException>().having(
            (error) => error.code,
            'code',
            testCase.$3,
          ),
        ),
      );
      expect(provider.callCount, 0);
    }
  });

  test('maps provider cancellation to cancelled', () async {
    final processor = _processor(
      provider: FakeLlmProvider((config, apiKey, request, token) async {
        throw const LlmProviderException(
          LlmProviderErrorKind.cancelled,
          'cancelled',
        );
      }),
      repository: MemoryRecipeRepository(),
    );

    expect(
      () => processor.process(_textContent(), onProgress: _ignoreProgress),
      throwsA(
        isA<ImportPipelineException>()
            .having(
              (error) => error.code,
              'code',
              ImportTaskErrorCode.cancelled,
            )
            .having((error) => error.retryable, 'retryable', isFalse),
      ),
    );
  });
  test('downloads remote cover images into the draft before saving', () async {
    final repository = MemoryRecipeRepository();
    final storer = _FakeCoverImageStorer();
    final remote = _FakeRemoteCoverImageStager();
    final processor = _processor(
      provider: FakeLlmProvider((config, apiKey, request, token) async {
        return const LlmGenerationResult(text: validRecipeGenerationJson);
      }),
      repository: repository,
      coverImageStorer: storer,
      remoteCoverImageStager: remote,
    );

    final result = await processor.process(
      _textContent(),
      onProgress: _ignoreProgress,
    );

    // 远程配图被下载并复制到菜谱私有封面目录，草稿封面使用本地路径。
    expect(remote.inputs, hasLength(1));
    expect(remote.inputs.single.remoteUrl, 'https://example.com/cover.jpg');
    expect(storer.copied, <String>['/tmp/staged-0.jpg']);
    final recipe = repository.recipes[result.recipeId]!;
    expect(recipe.images, <String>['/covers/${result.recipeId}/0.jpg']);
    expect(recipe.coverImage, '/covers/${result.recipeId}/0.jpg');
  });

  test('upgrades http cover URLs to https before downloading', () async {
    final repository = MemoryRecipeRepository();
    final storer = _FakeCoverImageStorer();
    final remote = _FakeRemoteCoverImageStager();
    final processor = _processor(
      provider: FakeLlmProvider((config, apiKey, request, token) async {
        return const LlmGenerationResult(text: validRecipeGenerationJson);
      }),
      repository: repository,
      coverImageStorer: storer,
      remoteCoverImageStager: remote,
    );
    final content = ImportContent(
      source: ImportSourceLink.parse(
        'https://www.xiaohongshu.com/explore/http-cover',
      ),
      resolvedUrl: 'https://www.xiaohongshu.com/explore/http-cover',
      contentType: ImportContentType.mixed,
      title: 'http 配图',
      capturedAt: DateTime.utc(2026, 7, 28),
      textFragments: <ImportTextFragment>[
        ImportTextFragment(
          kind: ImportTextFragmentKind.body,
          text: '番茄炒蛋。',
          order: 0,
        ),
      ],
      media: <ImportMediaReference>[
        ImportMediaReference(
          kind: ImportMediaKind.image,
          remoteUrl: 'http://sns-webpic-qc.xhscdn.com/2026/pic.jpg',
          order: 0,
        ),
      ],
    );

    await processor.process(content, onProgress: _ignoreProgress);

    // 小红书 http 配图在下载前被升级为 https，避免被 HTTPS-only 安全层拒绝。
    expect(storer.copied, hasLength(1));
    expect(
      remote.inputs.single.remoteUrl,
      'https://sns-webpic-qc.xhscdn.com/2026/pic.jpg',
    );
  });

  test('keeps the draft unchanged when cover downloads fail', () async {
    final repository = MemoryRecipeRepository();
    final storer = _FakeCoverImageStorer();
    final remote = _FakeRemoteCoverImageStager()..failDownload = true;
    final processor = _processor(
      provider: FakeLlmProvider((config, apiKey, request, token) async {
        return const LlmGenerationResult(text: validRecipeGenerationJson);
      }),
      repository: repository,
      coverImageStorer: storer,
      remoteCoverImageStager: remote,
    );

    final result = await processor.process(
      _textContent(),
      onProgress: _ignoreProgress,
    );

    // 下载失败为 best-effort：草稿仍生成，不携带本地封面。
    expect(storer.copied, isEmpty);
    final recipe = repository.recipes[result.recipeId]!;
    expect(recipe.images, isEmpty);
    expect(recipe.coverImage, 'https://example.com/cover.jpg');
  });

  test('skips cover downloads when content has no remote images', () async {
    final repository = MemoryRecipeRepository();
    final storer = _FakeCoverImageStorer();
    final remote = _FakeRemoteCoverImageStager();
    final processor = _processor(
      provider: FakeLlmProvider((config, apiKey, request, token) async {
        return const LlmGenerationResult(text: validRecipeGenerationJson);
      }),
      repository: repository,
      coverImageStorer: storer,
      remoteCoverImageStager: remote,
    );
    final content = ImportContent(
      source: ImportSourceLink.parse(
        'https://www.xiaohongshu.com/explore/plain',
      ),
      resolvedUrl: 'https://www.xiaohongshu.com/explore/plain',
      contentType: ImportContentType.article,
      title: '纯文字菜谱',
      capturedAt: DateTime.utc(2026, 7, 28),
      textFragments: <ImportTextFragment>[
        ImportTextFragment(
          kind: ImportTextFragmentKind.body,
          text: '番茄两个，鸡蛋三个。',
          order: 0,
        ),
      ],
    );

    final result = await processor.process(content, onProgress: _ignoreProgress);

    expect(remote.inputs, isEmpty);
    expect(storer.copied, isEmpty);
    final recipe = repository.recipes[result.recipeId]!;
    expect(recipe.images, isEmpty);
    expect(recipe.coverImage, isNull);
  });
}

class _FakeCoverImageStorer implements RecipeCoverImageStorer {
  final List<String> copied = <String>[];
  String? deletedContainer;

  @override
  Future<String> copyIn({
    required String sourcePath,
    required String containerId,
    required int index,
  }) async {
    copied.add(sourcePath);
    return '/covers/$containerId/$index.jpg';
  }

  @override
  Future<void> deleteFile(String imagePath) async {}

  @override
  Future<void> deleteContainer(String containerId) async {
    deletedContainer = containerId;
  }
}

class _FakeRemoteCoverImageStager implements OcrRemoteImageStager {
  bool failDownload = false;
  final List<OcrImageInput> inputs = <OcrImageInput>[];

  @override
  Future<StagedOcrImage> stage(
    OcrImageInput input, {
    ImportCancellationToken? cancellationToken,
  }) async {
    if (failDownload) {
      throw const OcrProviderException(
        kind: OcrProviderErrorKind.networkUnavailable,
        message: 'network down',
      );
    }
    inputs.add(input);
    return StagedOcrImage(
      input: OcrImageInput(
        localAssetId: '/tmp/staged-${input.order}.jpg',
        mimeType: 'image/jpeg',
        order: input.order,
      ),
      byteLength: 1,
      width: 100,
      height: 100,
      dispose: () async {},
    );
  }
}

LlmRecipeGenerationProcessor _processor({
  required FakeLlmProvider provider,
  required MemoryRecipeRepository repository,
  String Function()? idGenerator,
  RecipeCoverImageStorer? coverImageStorer,
  OcrRemoteImageStager? remoteCoverImageStager,
}) {
  var nextId = 0;
  return LlmRecipeGenerationProcessor(
    provider: provider,
    config: LlmConnectionConfig(
      id: 'config-1',
      name: 'Test',
      providerType: LlmProviderType.openAiCompatible,
      baseUrl: 'https://example.com/v1',
      secretRef: 'secret-ref',
      model: 'test-model',
    ),
    apiKey: 'secret-key',
    recipeRepository: repository,
    idGenerator: idGenerator ?? () => 'generated-${nextId += 1}',
    clock: () => DateTime.utc(2026, 7, 28, 16),
    coverImageStorer: coverImageStorer,
    remoteCoverImageStager: remoteCoverImageStager,
  );
}

ImportContent _textContent() {
  return ImportContent(
    source: ImportSourceLink.parse('https://www.xiaohongshu.com/explore/abc'),
    resolvedUrl: 'https://www.xiaohongshu.com/explore/abc',
    contentType: ImportContentType.mixed,
    title: '番茄炒蛋',
    capturedAt: DateTime.utc(2026, 7, 28),
    textFragments: <ImportTextFragment>[
      ImportTextFragment(
        kind: ImportTextFragmentKind.body,
        text: '番茄两个，鸡蛋三个。番茄炒软后加入蛋液。',
        order: 0,
      ),
    ],
    media: <ImportMediaReference>[
      ImportMediaReference(
        kind: ImportMediaKind.image,
        remoteUrl: 'https://example.com/cover.jpg',
        order: 0,
      ),
    ],
  );
}

Future<void> _ignoreProgress(
  ImportTaskStage stage,
  double progress,
  [String? detail],
) async {}
