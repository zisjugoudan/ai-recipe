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
