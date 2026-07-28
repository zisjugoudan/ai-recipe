import '../../domain/importing/import_content.dart';
import '../../domain/importing/import_fallback_input.dart';

class ImportFallbackContentFactory {
  const ImportFallbackContentFactory();

  ImportContent build(ImportFallbackInput input) {
    return switch (input.kind) {
      ImportFallbackInputKind.pastedText => ImportContent(
        source: input.source,
        resolvedUrl: input.source.normalizedUrl,
        contentType: ImportContentType.article,
        capturedAt: input.capturedAt,
        textFragments: <ImportTextFragment>[
          ImportTextFragment(
            kind: ImportTextFragmentKind.body,
            text: input.text!,
            order: 0,
          ),
        ],
        warnings: const <ImportContentWarning>{
          ImportContentWarning.missingTitle,
          ImportContentWarning.missingMedia,
          ImportContentWarning.partialContent,
        },
      ),
      ImportFallbackInputKind.localImage => ImportContent(
        source: input.source,
        resolvedUrl: input.source.normalizedUrl,
        contentType: ImportContentType.imageGallery,
        capturedAt: input.capturedAt,
        media: <ImportMediaReference>[
          ImportMediaReference(
            kind: ImportMediaKind.image,
            localAssetId: input.localAssetId,
            mimeType: input.mimeType,
            order: 0,
          ),
        ],
        warnings: const <ImportContentWarning>{
          ImportContentWarning.missingTitle,
          ImportContentWarning.missingText,
          ImportContentWarning.partialContent,
          ImportContentWarning.requiresOcr,
        },
      ),
      ImportFallbackInputKind.localVideo => ImportContent(
        source: input.source,
        resolvedUrl: input.source.normalizedUrl,
        contentType: ImportContentType.video,
        capturedAt: input.capturedAt,
        media: <ImportMediaReference>[
          ImportMediaReference(
            kind: ImportMediaKind.video,
            localAssetId: input.localAssetId,
            mimeType: input.mimeType,
            order: 0,
          ),
        ],
        warnings: const <ImportContentWarning>{
          ImportContentWarning.missingTitle,
          ImportContentWarning.missingText,
          ImportContentWarning.partialContent,
          ImportContentWarning.requiresAsr,
        },
      ),
    };
  }
}
