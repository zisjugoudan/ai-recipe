import 'package:ai_recipe/domain/importing/import_content.dart';
import 'package:ai_recipe/domain/importing/import_content_adapter.dart';
import 'package:ai_recipe/domain/importing/import_task.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_import_dependencies.dart';

void main() {
  final source = ImportSourceLink.parse(
    'https://www.xiaohongshu.com/explore/1',
  );

  test(
    'unified content normalizes optional text and orders source entries',
    () {
      final content = ImportContent(
        source: source,
        resolvedUrl: source.normalizedUrl,
        contentType: ImportContentType.mixed,
        title: '  Braised chicken  ',
        description: '   ',
        capturedAt: DateTime.parse('2026-07-28T18:00:00+08:00'),
        textFragments: <ImportTextFragment>[
          ImportTextFragment(
            kind: ImportTextFragmentKind.body,
            text: 'Add seasoning',
            order: 2,
          ),
          ImportTextFragment(
            kind: ImportTextFragmentKind.caption,
            text: 'Prepare ingredients',
            order: 1,
          ),
        ],
        media: <ImportMediaReference>[
          ImportMediaReference(
            kind: ImportMediaKind.image,
            localAssetId: 'asset-2',
            order: 2,
          ),
          ImportMediaReference(
            kind: ImportMediaKind.video,
            remoteUrl: 'https://example.com/video.mp4',
            order: 1,
          ),
        ],
        warnings: const <ImportContentWarning>[
          ImportContentWarning.requiresOcr,
          ImportContentWarning.requiresOcr,
        ],
      );

      expect(content.title, 'Braised chicken');
      expect(content.description, isNull);
      expect(content.capturedAt, DateTime.utc(2026, 7, 28, 10));
      expect(content.textFragments.map((item) => item.order), <int>[1, 2]);
      expect(content.media.map((item) => item.order), <int>[1, 2]);
      expect(content.warnings, <ImportContentWarning>{
        ImportContentWarning.requiresOcr,
      });
      expect(content.toJson()['version'], 1);
    },
  );

  test('content toJson/fromJson round-trips the original evidence', () {
    final content = ImportContent(
      source: source,
      resolvedUrl: source.normalizedUrl,
      contentType: ImportContentType.mixed,
      title: '番茄炒蛋',
      description: '酸甜开胃的快手家常菜。',
      authorName: '阿飞',
      capturedAt: DateTime.parse('2026-07-28T18:00:00+08:00'),
      textFragments: <ImportTextFragment>[
        ImportTextFragment(
          kind: ImportTextFragmentKind.body,
          text: '鸡蛋打散备用。',
          order: 0,
          confidence: 0.92,
          sourceType: ImportTextFragmentSourceType.ocr,
        ),
        ImportTextFragment(
          kind: ImportTextFragmentKind.title,
          text: '番茄炒蛋',
          order: 1,
        ),
      ],
      media: <ImportMediaReference>[
        ImportMediaReference(
          kind: ImportMediaKind.image,
          localAssetId: 'asset-1',
          order: 0,
        ),
      ],
      warnings: const <ImportContentWarning>[
        ImportContentWarning.partialContent,
      ],
    );

    final restored = ImportContent.fromJson(content.toJson());
    expect(restored.source.sourceUrl, content.source.sourceUrl);
    expect(restored.source.normalizedUrl, content.source.normalizedUrl);
    expect(restored.source.platform, content.source.platform);
    expect(restored.resolvedUrl, content.resolvedUrl);
    expect(restored.contentType, content.contentType);
    expect(restored.title, content.title);
    expect(restored.description, content.description);
    expect(restored.authorName, content.authorName);
    expect(restored.capturedAt, content.capturedAt);
    expect(restored.textFragments.length, content.textFragments.length);
    expect(restored.textFragments[0].text, '鸡蛋打散备用。');
    expect(restored.textFragments[0].sourceType, ImportTextFragmentSourceType.ocr);
    expect(restored.textFragments[0].confidence, 0.92);
    expect(restored.media.length, content.media.length);
    expect(restored.media.single.localAssetId, 'asset-1');
    expect(
      restored.warnings,
      <ImportContentWarning>{ImportContentWarning.partialContent},
    );
  });

  test('content requires text or media and validates media URLs', () {
    expect(
      () => ImportContent(
        source: source,
        resolvedUrl: source.normalizedUrl,
        contentType: ImportContentType.unknown,
        capturedAt: DateTime.utc(2026, 7, 28),
      ),
      throwsArgumentError,
    );
    expect(
      () => ImportMediaReference(
        kind: ImportMediaKind.image,
        remoteUrl: 'file:///private/image.jpg',
        order: 0,
      ),
      throwsArgumentError,
    );
    expect(
      () => ImportMediaReference(kind: ImportMediaKind.image, order: 0),
      throwsArgumentError,
    );
  });

  test('text fragments preserve OCR and ASR evidence and validate ranges', () {
    final fragment = ImportTextFragment(
      kind: ImportTextFragmentKind.caption,
      text: ' ASR text ',
      order: 3,
      confidence: 0.75,
      sourceMediaOrder: 2,
      sourceProvider: ' whisper-local ',
      sourceLanguage: ' zh-Hans ',
      sourceStartMs: 1200,
      sourceEndMs: 3400,
      speakerLabel: ' cook ',
    );

    expect(fragment.text, 'ASR text');
    expect(fragment.sourceProvider, 'whisper-local');
    expect(fragment.sourceLanguage, 'zh-Hans');
    expect(fragment.speakerLabel, 'cook');
    expect(fragment.toJson(), <String, Object?>{
      'kind': 'caption',
      'text': 'ASR text',
      'order': 3,
      'confidence': 0.75,
      'sourceMediaOrder': 2,
      'sourceProvider': 'whisper-local',
      'sourceLanguage': 'zh-Hans',
      'sourceStartMs': 1200,
      'sourceEndMs': 3400,
      'speakerLabel': 'cook',
      'sourceType': 'authorText',
    });
    final emptyEvidence = ImportTextFragment(
      kind: ImportTextFragmentKind.body,
      text: 'text',
      order: 0,
      sourceProvider: '   ',
      sourceLanguage: '   ',
      speakerLabel: '   ',
    );
    expect(emptyEvidence.sourceProvider, isNull);
    expect(emptyEvidence.sourceLanguage, isNull);
    expect(emptyEvidence.speakerLabel, isNull);
    expect(
      () => ImportTextFragment(
        kind: ImportTextFragmentKind.body,
        text: 'text',
        order: 0,
        confidence: 1.1,
      ),
      throwsArgumentError,
    );
    expect(
      () => ImportTextFragment(
        kind: ImportTextFragmentKind.body,
        text: 'text',
        order: 0,
        sourceMediaOrder: -1,
      ),
      throwsArgumentError,
    );
    expect(
      () => ImportTextFragment(
        kind: ImportTextFragmentKind.caption,
        text: 'text',
        order: 0,
        sourceStartMs: 0,
      ),
      throwsArgumentError,
    );
    expect(
      () => ImportTextFragment(
        kind: ImportTextFragmentKind.caption,
        text: 'text',
        order: 0,
        sourceEndMs: 1,
      ),
      throwsArgumentError,
    );
    expect(
      () => ImportTextFragment(
        kind: ImportTextFragmentKind.caption,
        text: 'text',
        order: 0,
        sourceStartMs: -1,
        sourceEndMs: 1,
      ),
      throwsArgumentError,
    );
    expect(
      () => ImportTextFragment(
        kind: ImportTextFragmentKind.caption,
        text: 'text',
        order: 0,
        sourceStartMs: 100,
        sourceEndMs: 100,
      ),
      throwsArgumentError,
    );
  });
  test(
    'adapter registry selects by platform and exposes supported platforms',
    () {
      final adapter = FakeImportContentAdapter(
        platform: ImportSourcePlatform.xiaohongshu,
        handler: (source, _) async => sampleImportContent(source),
      );
      final registry = ImportContentAdapterRegistry(<ImportContentAdapter>[
        adapter,
      ]);

      expect(
        registry.adapterFor(ImportSourcePlatform.xiaohongshu),
        same(adapter),
      );
      expect(registry.supportedPlatforms, <ImportSourcePlatform>{
        ImportSourcePlatform.xiaohongshu,
      });
      expect(
        () => registry.adapterFor(ImportSourcePlatform.douyin),
        throwsA(
          isA<ImportContentAdapterException>().having(
            (error) => error.kind,
            'kind',
            ImportContentAdapterErrorKind.unsupportedPlatform,
          ),
        ),
      );
    },
  );

  test('adapter registry rejects duplicate platform registrations', () {
    FakeImportContentAdapter adapter() => FakeImportContentAdapter(
      platform: ImportSourcePlatform.xiaohongshu,
      handler: (source, _) async => sampleImportContent(source),
    );

    expect(
      () => ImportContentAdapterRegistry(<ImportContentAdapter>[
        adapter(),
        adapter(),
      ]),
      throwsA(isA<ImportContentAdapterRegistrationException>()),
    );
  });
}
