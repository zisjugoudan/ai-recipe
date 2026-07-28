import '../../domain/importing/import_cancellation_token.dart';
import '../../domain/importing/import_content.dart';
import '../../domain/importing/import_content_adapter.dart';
import '../../domain/importing/import_task.dart';
import 'import_http_transport.dart';
import 'public_page_metadata_parser.dart';

typedef ImportClock = DateTime Function();

abstract class PublicPageImportContentAdapter implements ImportContentAdapter {
  PublicPageImportContentAdapter({
    required ImportHttpTransport transport,
    PublicPageMetadataParser parser = const PublicPageMetadataParser(),
    ImportClock? clock,
  }) : _transport = transport,
       _parser = parser,
       _clock = clock ?? DateTime.now;

  final ImportHttpTransport _transport;
  final PublicPageMetadataParser _parser;
  final ImportClock _clock;

  Set<String> get allowedHosts;

  Iterable<String> get loginRequiredMarkers => const <String>[
    '\u8bf7\u5148\u767b\u5f55',
    '\u767b\u5f55\u540e\u67e5\u770b',
    '\u767b\u5f55\u540e\u7ee7\u7eed',
    'login required',
    'sign in to continue',
  ];

  Iterable<String> get contentUnavailableMarkers => const <String>[
    '\u5185\u5bb9\u4e0d\u5b58\u5728',
    '\u4f5c\u54c1\u4e0d\u5b58\u5728',
    '\u5185\u5bb9\u5df2\u5220\u9664',
    '\u4f5c\u54c1\u5df2\u5220\u9664',
    'content unavailable',
    'content is unavailable',
    'page not found',
  ];

  @override
  Future<ImportContent> fetch(
    ImportSourceLink source, {
    ImportCancellationToken? cancellationToken,
  }) async {
    if (source.platform != platform) {
      throw ImportContentAdapterException(
        kind: ImportContentAdapterErrorKind.unsupportedPlatform,
        message: 'The source platform does not match this content adapter.',
        retryable: false,
      );
    }

    final requestUri = Uri.parse(source.normalizedUrl);
    final request = ImportHttpRequest(
      uri: requestUri,
      allowedHosts: <String>{...allowedHosts, requestUri.host.toLowerCase()},
      headers: const <String, String>{
        'Accept':
            'text/html,application/xhtml+xml,application/json,text/plain;q=0.8',
        'User-Agent': 'AIRecipe/1.0 PublicMetadataImporter',
      },
    );

    try {
      final response = await _transport.get(
        request,
        cancellationToken: cancellationToken,
      );
      _throwForStatus(response.statusCode);
      _throwForKnownPageState(response.body);

      final metadata = _parser.parse(
        response.body,
        baseUri: response.resolvedUri,
        contentType: response.headers['content-type'],
      );
      if (!metadata.hasText && !metadata.hasMedia) {
        throw const ImportContentAdapterException(
          kind: ImportContentAdapterErrorKind.invalidPayload,
          message: 'The public page did not expose usable text or media.',
          retryable: false,
        );
      }

      final textFragments = <ImportTextFragment>[];
      void addText(ImportTextFragmentKind kind, String? text) {
        if (text == null || text.trim().isEmpty) return;
        if (textFragments.any((fragment) => fragment.text == text.trim())) {
          return;
        }
        textFragments.add(
          ImportTextFragment(
            kind: kind,
            text: text,
            order: textFragments.length,
          ),
        );
      }

      addText(ImportTextFragmentKind.title, metadata.title);
      addText(ImportTextFragmentKind.description, metadata.description);
      addText(ImportTextFragmentKind.caption, metadata.caption);
      addText(ImportTextFragmentKind.body, metadata.bodyText);

      final media = <ImportMediaReference>[];
      for (final imageUrl in metadata.imageUrls) {
        media.add(
          ImportMediaReference(
            kind: ImportMediaKind.image,
            remoteUrl: imageUrl,
            mimeType: metadata.imageMimeType,
            order: media.length,
          ),
        );
      }
      for (final videoUrl in metadata.videoUrls) {
        media.add(
          ImportMediaReference(
            kind: ImportMediaKind.video,
            remoteUrl: videoUrl,
            mimeType: metadata.videoMimeType,
            order: media.length,
          ),
        );
      }

      final hasText = metadata.hasText;
      final hasMedia = metadata.hasMedia;
      final hasImages = metadata.imageUrls.isNotEmpty;
      final hasVideos = metadata.videoUrls.isNotEmpty;
      final redirected =
          response.redirectCount > 0 ||
          response.resolvedUri.toString() != source.normalizedUrl;
      final warnings = <ImportContentWarning>{
        if (metadata.title == null) ImportContentWarning.missingTitle,
        if (!hasText) ImportContentWarning.missingText,
        if (!hasMedia) ImportContentWarning.missingMedia,
        if (!hasText || !hasMedia) ImportContentWarning.partialContent,
        if (hasImages) ImportContentWarning.requiresOcr,
        if (hasVideos) ImportContentWarning.requiresAsr,
        if (redirected) ImportContentWarning.redirected,
      };

      return ImportContent(
        source: source,
        resolvedUrl: response.resolvedUri.toString(),
        contentType: _contentType(
          hasText: hasText,
          hasImages: hasImages,
          hasVideos: hasVideos,
        ),
        title: metadata.title,
        description: metadata.description ?? metadata.caption,
        authorName: metadata.authorName,
        publishedAt: metadata.publishedAt,
        capturedAt: _clock().toUtc(),
        textFragments: textFragments,
        media: media,
        warnings: warnings,
      );
    } on ImportContentAdapterException {
      rethrow;
    } on ImportHttpTransportException catch (error) {
      throw _mapTransportError(error);
    } on ImportOperationCancelledException {
      throw const ImportContentAdapterException(
        kind: ImportContentAdapterErrorKind.cancelled,
        message: 'The public content import was cancelled.',
        retryable: false,
      );
    } on FormatException {
      throw const ImportContentAdapterException(
        kind: ImportContentAdapterErrorKind.invalidPayload,
        message: 'The public content response was malformed.',
        retryable: false,
      );
    } catch (_) {
      throw const ImportContentAdapterException(
        kind: ImportContentAdapterErrorKind.unknown,
        message: 'The public content import failed unexpectedly.',
        retryable: false,
      );
    }
  }

  void _throwForStatus(int statusCode) {
    if (statusCode == 401 || statusCode == 403) {
      throw const ImportContentAdapterException(
        kind: ImportContentAdapterErrorKind.authorizationRequired,
        message: 'The public content requires authorization.',
        retryable: false,
      );
    }
    if (statusCode == 404 || statusCode == 410) {
      throw const ImportContentAdapterException(
        kind: ImportContentAdapterErrorKind.contentUnavailable,
        message: 'The public content is unavailable.',
        retryable: false,
      );
    }
    if (statusCode == 408) {
      throw const ImportContentAdapterException(
        kind: ImportContentAdapterErrorKind.timeout,
        message: 'The public content request timed out.',
        retryable: true,
      );
    }
    if (statusCode == 429 || statusCode >= 500) {
      throw const ImportContentAdapterException(
        kind: ImportContentAdapterErrorKind.networkUnavailable,
        message: 'The public content service is temporarily unavailable.',
        retryable: true,
      );
    }
    if (statusCode >= 400) {
      throw const ImportContentAdapterException(
        kind: ImportContentAdapterErrorKind.invalidPayload,
        message: 'The public content request returned an unsupported response.',
        retryable: false,
      );
    }
  }

  void _throwForKnownPageState(String body) {
    final normalized = body.toLowerCase();
    if (loginRequiredMarkers.any(normalized.contains)) {
      throw const ImportContentAdapterException(
        kind: ImportContentAdapterErrorKind.authorizationRequired,
        message: 'The public page requires the user to sign in.',
        retryable: false,
      );
    }
    if (contentUnavailableMarkers.any(normalized.contains)) {
      throw const ImportContentAdapterException(
        kind: ImportContentAdapterErrorKind.contentUnavailable,
        message: 'The public page reports that the content is unavailable.',
        retryable: false,
      );
    }
  }

  static ImportContentType _contentType({
    required bool hasText,
    required bool hasImages,
    required bool hasVideos,
  }) {
    if (hasVideos && (hasImages || hasText)) return ImportContentType.mixed;
    if (hasVideos) return ImportContentType.video;
    if (hasImages && hasText) return ImportContentType.mixed;
    if (hasImages) return ImportContentType.imageGallery;
    if (hasText) return ImportContentType.article;
    return ImportContentType.unknown;
  }

  static ImportContentAdapterException _mapTransportError(
    ImportHttpTransportException error,
  ) {
    return switch (error.kind) {
      ImportHttpTransportErrorKind.network => ImportContentAdapterException(
        kind: ImportContentAdapterErrorKind.networkUnavailable,
        message: 'The public content network request failed.',
        retryable: true,
      ),
      ImportHttpTransportErrorKind.timeout => ImportContentAdapterException(
        kind: ImportContentAdapterErrorKind.timeout,
        message: 'The public content request timed out.',
        retryable: true,
      ),
      ImportHttpTransportErrorKind.cancelled => ImportContentAdapterException(
        kind: ImportContentAdapterErrorKind.cancelled,
        message: 'The public content import was cancelled.',
        retryable: false,
      ),
      ImportHttpTransportErrorKind.invalidRequest ||
      ImportHttpTransportErrorKind.invalidRedirect ||
      ImportHttpTransportErrorKind.tooManyRedirects ||
      ImportHttpTransportErrorKind.responseTooLarge ||
      ImportHttpTransportErrorKind.unsupportedContentType =>
        ImportContentAdapterException(
          kind: ImportContentAdapterErrorKind.invalidPayload,
          message: 'The public content response failed safety validation.',
          retryable: false,
        ),
    };
  }
}

class XiaohongshuPublicContentAdapter extends PublicPageImportContentAdapter {
  XiaohongshuPublicContentAdapter({
    required super.transport,
    super.parser,
    super.clock,
  });

  @override
  ImportSourcePlatform get platform => ImportSourcePlatform.xiaohongshu;

  @override
  Set<String> get allowedHosts => const <String>{
    'xiaohongshu.com',
    'www.xiaohongshu.com',
    'xhslink.com',
    'www.xhslink.com',
  };
}

class DouyinPublicContentAdapter extends PublicPageImportContentAdapter {
  DouyinPublicContentAdapter({
    required super.transport,
    super.parser,
    super.clock,
  });

  @override
  ImportSourcePlatform get platform => ImportSourcePlatform.douyin;

  @override
  Set<String> get allowedHosts => const <String>{
    'douyin.com',
    'www.douyin.com',
    'v.douyin.com',
    'iesdouyin.com',
    'www.iesdouyin.com',
  };
}
