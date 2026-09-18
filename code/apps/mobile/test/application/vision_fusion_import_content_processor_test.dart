import 'dart:io';

import 'package:ai_recipe/application/importing/import_pipeline_contracts.dart';
import 'package:ai_recipe/application/importing/vision_fusion_import_content_processor.dart';
import 'package:ai_recipe/domain/importing/import_cancellation_token.dart';
import 'package:ai_recipe/domain/importing/import_content.dart';
import 'package:ai_recipe/domain/importing/import_task.dart';
import 'package:ai_recipe/domain/llm/llm_cancellation_token.dart';
import 'package:ai_recipe/domain/llm/llm_connection_config.dart';
import 'package:ai_recipe/domain/llm/llm_diagnostic.dart';
import 'package:ai_recipe/domain/llm/llm_models.dart';
import 'package:ai_recipe/domain/llm/llm_provider_exception.dart';
import 'package:ai_recipe/domain/llm/llm_provider_type.dart';
import 'package:ai_recipe/domain/llm/multimodal_llm_provider.dart';
import 'package:ai_recipe/domain/ocr/ocr_models.dart';
import 'package:ai_recipe/domain/ocr/ocr_provider_exception.dart';
import 'package:ai_recipe/domain/ocr/ocr_remote_image_stager.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_import_dependencies.dart';
import '../support/fake_ocr_provider.dart';

/// 可编程多模态 Provider：支持返回结果或抛出指定错误。
class FakeMultimodalProvider extends MultimodalLlmProvider {
  FakeMultimodalProvider({this.resultText, this.error});

  final String? resultText;
  final LlmProviderException? error;
  final List<MultimodalImageInput> inputs = <MultimodalImageInput>[];

  @override
  Future<LlmGenerationResult> generate({
    required LlmConnectionConfig config,
    required String apiKey,
    required LlmGenerationRequest request,
    LlmCancellationToken? cancellationToken,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<LlmDiagnosticReport> diagnose({
    required LlmConnectionConfig config,
    required String apiKey,
    required bool imageProbe,
    LlmCancellationToken? cancellationToken,
  }) async {
    return const LlmDiagnosticReport(
      records: [],
      totalElapsedMs: 0,
      succeeded: true,
    );
  }

  @override
  String? validateImageBytes({required List<int> bytes, String? mimeType}) {
    return null;
  }

  @override
  Future<MultimodalRecognitionResult> recognizeImage({
    required LlmConnectionConfig config,
    required String apiKey,
    required MultimodalImageInput input,
    required String prompt,
    LlmCancellationToken? cancellationToken,
  }) async {
    inputs.add(input);
    if (error != null) throw error!;
    return MultimodalRecognitionResult(
      text: resultText ?? '画面中有一道菜和几个食材',
      providerId: 'fake-vision',
    );
  }
}

/// 固定返回本地文件的暂存器（多模态读取字节用）。
class FakeStager implements OcrRemoteImageStager {
  FakeStager(this.localAssetId);

  final String localAssetId;
  Object? error;

  @override
  Future<StagedOcrImage> stage(
    OcrImageInput input, {
    ImportCancellationToken? cancellationToken,
  }) async {
    if (error != null) throw error!;
    return StagedOcrImage(
      input: OcrImageInput(
        localAssetId: localAssetId,
        mimeType: 'image/png',
        order: input.order,
      ),
      byteLength: 3,
      width: 8,
      height: 8,
      dispose: () async {},
    );
  }
}

/// 记录下游收到的内容并返回草稿。
class RecordingProcessor implements ImportContentProcessor {
  ImportContent? received;

  @override
  Future<ImportRecipeDraftResult> process(
    ImportContent content, {
    required ImportPipelineProgressCallback onProgress,
    ImportCancellationToken? cancellationToken,
  }) async {
    received = content;
    return ImportRecipeDraftResult(recipeId: 'draft-1');
  }
}

void main() {
  late Directory tempDir;
  late String imagePath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('fusion-test');
    imagePath = '${tempDir.path}/probe.png';
    await File(imagePath).writeAsBytes(<int>[1, 2, 3]);
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  ImportContent sampleWithImage() {
    final source = ImportSourceLink.parse(
      'https://www.xiaohongshu.com/explore/sample',
    );
    return ImportContent(
      source: source,
      resolvedUrl: source.normalizedUrl,
      contentType: ImportContentType.imageGallery,
      capturedAt: DateTime.utc(2026, 8, 5, 10),
      media: <ImportMediaReference>[
        ImportMediaReference(
          kind: ImportMediaKind.image,
          remoteUrl: 'https://example.com/recipe.jpg',
          order: 0,
        ),
      ],
      warnings: const <ImportContentWarning>{
        ImportContentWarning.requiresOcr,
      },
    );
  }

  Future<ImportRecipeDraftResult> run(
    ImportContentProcessor processor,
    ImportContent content,
  ) {
    return processor.process(content, onProgress: (_, _, [detail]) async {});
  }

  test('OCR 成功、多模态失败：保留 OCR 并标记视觉观察缺失', () async {
    final downstream = RecordingProcessor();
    final processor = VisionFusionImportContentProcessor(
      ocrProvider: FakeOcrProvider(
        (input, _) async => sampleOcrDocument(text: '菜名：红烧肉\n配料：猪肉'),
      ),
      multimodalProvider: FakeMultimodalProvider(
        error: const LlmProviderException(
          LlmProviderErrorKind.timeout,
          '超时',
        ),
      ),
      multimodalConfig: LlmConnectionConfig(
        id: 'm1',
        name: 'vision',
        providerType: LlmProviderType.openAiCompatible,
        baseUrl: 'https://example.com/v1',
        secretRef: 's1',
        model: 'vision-model',
      ),
      multimodalApiKey: 'key',
      stager: FakeStager(imagePath),
      downstream: downstream,
    );

    final result = await run(processor, sampleWithImage());

    expect(result.recipeId, 'draft-1');
    final received = downstream.received!;
    final fragments = received.textFragments;
    expect(fragments.length, 1);
    expect(fragments.single.sourceType, ImportTextFragmentSourceType.ocr);
    expect(fragments.single.text, contains('红烧肉'));
    expect(received.warnings, contains(ImportContentWarning.visionIncomplete));
    expect(
      received.warnings,
      isNot(contains(ImportContentWarning.ocrIncomplete)),
    );
  });

  test('多模态成功、OCR 失败：保留视觉观察并标记文字提取缺失', () async {
    final downstream = RecordingProcessor();
    final processor = VisionFusionImportContentProcessor(
      ocrProvider: FakeOcrProvider(
        (input, _) async => throw const OcrProviderException(
          kind: OcrProviderErrorKind.modelNotInstalled,
          message: '模型未安装',
        ),
      ),
      multimodalProvider: FakeMultimodalProvider(
        resultText: '画面中有一盘红烧肉',
      ),
      multimodalConfig: LlmConnectionConfig(
        id: 'm1',
        name: 'vision',
        providerType: LlmProviderType.openAiCompatible,
        baseUrl: 'https://example.com/v1',
        secretRef: 's1',
        model: 'vision-model',
      ),
      multimodalApiKey: 'key',
      stager: FakeStager(imagePath),
      downstream: downstream,
    );

    final result = await run(processor, sampleWithImage());

    expect(result.recipeId, 'draft-1');
    final fragments = downstream.received!.textFragments;
    expect(fragments.length, 1);
    expect(
      fragments.single.sourceType,
      ImportTextFragmentSourceType.visionObservation,
    );
    expect(fragments.single.text, contains('红烧肉'));
    expect(downstream.received!.warnings, contains(ImportContentWarning.ocrIncomplete));
    expect(
      downstream.received!.warnings,
      isNot(contains(ImportContentWarning.visionIncomplete)),
    );
  });

  test('两路都成功：按来源分别保留 OCR 与视觉观察，不互相覆盖', () async {
    final downstream = RecordingProcessor();
    final processor = VisionFusionImportContentProcessor(
      ocrProvider: FakeOcrProvider(
        (input, _) async => sampleOcrDocument(text: '配料：猪肉 500 克'),
      ),
      multimodalProvider: FakeMultimodalProvider(
        resultText: '画面中有一盘红烧肉',
      ),
      multimodalConfig: LlmConnectionConfig(
        id: 'm1',
        name: 'vision',
        providerType: LlmProviderType.openAiCompatible,
        baseUrl: 'https://example.com/v1',
        secretRef: 's1',
        model: 'vision-model',
      ),
      multimodalApiKey: 'key',
      stager: FakeStager(imagePath),
      downstream: downstream,
    );

    await run(processor, sampleWithImage());

    final fragments = downstream.received!.textFragments;
    expect(fragments.length, 2);
    final sourceTypes = fragments.map((f) => f.sourceType).toSet();
    expect(sourceTypes, <ImportTextFragmentSourceType>{
      ImportTextFragmentSourceType.ocr,
      ImportTextFragmentSourceType.visionObservation,
    });
    expect(
      downstream.received!.warnings,
      isNot(contains(ImportContentWarning.visionIncomplete)),
    );
    expect(
      downstream.received!.warnings,
      isNot(contains(ImportContentWarning.ocrIncomplete)),
    );
  });

  test('两路都失败但有作者正文：基于已有证据继续', () async {
    final downstream = RecordingProcessor();
    final processor = VisionFusionImportContentProcessor(
      ocrProvider: FakeOcrProvider(
        (input, _) async => throw const OcrProviderException(
          kind: OcrProviderErrorKind.inferenceFailed,
          message: '识别失败',
        ),
      ),
      multimodalProvider: FakeMultimodalProvider(
        error: const LlmProviderException(
          LlmProviderErrorKind.network,
          '网络失败',
        ),
      ),
      multimodalConfig: LlmConnectionConfig(
        id: 'm1',
        name: 'vision',
        providerType: LlmProviderType.openAiCompatible,
        baseUrl: 'https://example.com/v1',
        secretRef: 's1',
        model: 'vision-model',
      ),
      multimodalApiKey: 'key',
      stager: FakeStager(imagePath),
      downstream: downstream,
    );

    final content = ImportContent(
      source: ImportSourceLink.parse('https://example.com/a'),
      resolvedUrl: 'https://example.com/a',
      contentType: ImportContentType.mixed,
      title: '我的红烧肉做法',
      capturedAt: DateTime.utc(2026, 8, 5, 10),
      media: <ImportMediaReference>[
        ImportMediaReference(
          kind: ImportMediaKind.image,
          remoteUrl: 'https://example.com/b.jpg',
          order: 0,
        ),
      ],
      warnings: const <ImportContentWarning>{
        ImportContentWarning.requiresOcr,
      },
    );

    final result = await run(processor, content);

    expect(result.recipeId, 'draft-1');
    expect(downstream.received!.title, '我的红烧肉做法');
    expect(downstream.received!.warnings, contains(ImportContentWarning.visionIncomplete));
    expect(downstream.received!.warnings, contains(ImportContentWarning.ocrIncomplete));
  });

  test('两路都失败且无其他证据：不生成空草稿', () async {
    final processor = VisionFusionImportContentProcessor(
      ocrProvider: FakeOcrProvider(
        (input, _) async => throw const OcrProviderException(
          kind: OcrProviderErrorKind.inferenceFailed,
          message: '识别失败',
        ),
      ),
      multimodalProvider: FakeMultimodalProvider(
        error: const LlmProviderException(
          LlmProviderErrorKind.network,
          '网络失败',
        ),
      ),
      multimodalConfig: LlmConnectionConfig(
        id: 'm1',
        name: 'vision',
        providerType: LlmProviderType.openAiCompatible,
        baseUrl: 'https://example.com/v1',
        secretRef: 's1',
        model: 'vision-model',
      ),
      multimodalApiKey: 'key',
      stager: FakeStager(imagePath),
      downstream: RecordingProcessor(),
    );

    await expectLater(
      run(processor, sampleWithImage()),
      throwsA(
        isA<ImportPipelineException>()
            .having((e) => e.code, 'code', ImportTaskErrorCode.ocrFailed)
            .having((e) => e.retryable, 'retryable', isFalse),
      ),
    );
  });

  test('无图内容不触发识别，直接交给下游', () async {
    final downstream = RecordingProcessor();
    final ocr = FakeOcrProvider((input, _) async => sampleOcrDocument());
    final vision = FakeMultimodalProvider();
    final processor = VisionFusionImportContentProcessor(
      ocrProvider: ocr,
      multimodalProvider: vision,
      multimodalConfig: LlmConnectionConfig(
        id: 'm1',
        name: 'vision',
        providerType: LlmProviderType.openAiCompatible,
        baseUrl: 'https://example.com/v1',
        secretRef: 's1',
        model: 'vision-model',
      ),
      multimodalApiKey: 'key',
      stager: FakeStager(imagePath),
      downstream: downstream,
    );

    final source = ImportSourceLink.parse('https://example.com/text');
    await run(
      processor,
      ImportContent(
        source: source,
        resolvedUrl: source.normalizedUrl,
        contentType: ImportContentType.article,
        title: '纯文字菜谱',
        capturedAt: DateTime.utc(2026, 8, 5, 10),
      ),
    );

    expect(ocr.inputs, isEmpty);
    expect(vision.inputs, isEmpty);
    expect(downstream.received!.title, '纯文字菜谱');
  });
}
