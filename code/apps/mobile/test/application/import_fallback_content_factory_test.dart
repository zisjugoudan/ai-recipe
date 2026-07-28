import 'package:ai_recipe/application/importing/import_fallback_content_factory.dart';
import 'package:ai_recipe/domain/importing/import_content.dart';
import 'package:ai_recipe/domain/importing/import_fallback_input.dart';
import 'package:ai_recipe/domain/importing/import_task.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = ImportSourceLink.parse(
    'https://www.xiaohongshu.com/explore/fallback',
  );
  final capturedAt = DateTime.utc(2026, 7, 28, 13);
  const factory = ImportFallbackContentFactory();

  test('pasted text becomes article content for direct LLM processing', () {
    final content = factory.build(
      ImportFallbackInput.pastedText(
        source: source,
        text: '  Chop onions.\n\nSimmer for 10 minutes. ',
        capturedAt: capturedAt,
      ),
    );

    expect(content.contentType, ImportContentType.article);
    expect(
      content.textFragments.single.text,
      'Chop onions. Simmer for 10 minutes.',
    );
    expect(content.media, isEmpty);
    expect(content.warnings, <ImportContentWarning>{
      ImportContentWarning.missingTitle,
      ImportContentWarning.missingMedia,
      ImportContentWarning.partialContent,
    });
  });

  test('local image becomes OCR-ready unified content', () {
    final content = factory.build(
      ImportFallbackInput.localImage(
        source: source,
        localAssetId: 'asset-image-1',
        mimeType: 'IMAGE/JPEG',
        capturedAt: capturedAt,
      ),
    );

    expect(content.contentType, ImportContentType.imageGallery);
    expect(content.media.single.kind, ImportMediaKind.image);
    expect(content.media.single.localAssetId, 'asset-image-1');
    expect(content.media.single.mimeType, 'image/jpeg');
    expect(content.warnings, contains(ImportContentWarning.requiresOcr));
  });

  test('local video becomes ASR-ready unified content', () {
    final content = factory.build(
      ImportFallbackInput.localVideo(
        source: source,
        localAssetId: 'asset-video-1',
        mimeType: 'video/mp4',
        capturedAt: capturedAt,
      ),
    );

    expect(content.contentType, ImportContentType.video);
    expect(content.media.single.kind, ImportMediaKind.video);
    expect(content.media.single.localAssetId, 'asset-video-1');
    expect(content.warnings, contains(ImportContentWarning.requiresAsr));
  });

  test('rejects empty pasted text before entering the pipeline', () {
    expect(
      () => ImportFallbackInput.pastedText(
        source: source,
        text: '  \n ',
        capturedAt: capturedAt,
      ),
      throwsArgumentError,
    );
  });

  test('rejects empty local asset IDs', () {
    expect(
      () => ImportFallbackInput.localImage(
        source: source,
        localAssetId: '   ',
        capturedAt: capturedAt,
      ),
      throwsArgumentError,
    );
  });

  test('rejects a MIME type that does not match the fallback kind', () {
    expect(
      () => ImportFallbackInput.localVideo(
        source: source,
        localAssetId: 'asset-1',
        mimeType: 'image/jpeg',
        capturedAt: capturedAt,
      ),
      throwsArgumentError,
    );
  });
}
