import 'dart:convert';

class PublicPageMetadata {
  const PublicPageMetadata({
    this.title,
    this.description,
    this.authorName,
    this.publishedAt,
    this.caption,
    this.bodyText,
    this.imageUrls = const <String>[],
    this.videoUrls = const <String>[],
    this.imageMimeType,
    this.videoMimeType,
  });

  final String? title;
  final String? description;
  final String? authorName;
  final DateTime? publishedAt;
  final String? caption;
  final String? bodyText;
  final List<String> imageUrls;
  final List<String> videoUrls;
  final String? imageMimeType;
  final String? videoMimeType;

  bool get hasText =>
      title != null ||
      description != null ||
      caption != null ||
      bodyText != null;
  bool get hasMedia => imageUrls.isNotEmpty || videoUrls.isNotEmpty;
}

class PublicPageMetadataParser {
  const PublicPageMetadataParser();

  PublicPageMetadata parse(
    String content, {
    required Uri baseUri,
    String? contentType,
  }) {
    final normalizedContentType = _normalizedContentType(contentType);
    final meta = _readMeta(content);
    final structuredData = <Object?>[
      ..._readJsonLd(content),
      ..._readStandaloneJson(content, normalizedContentType),
    ];

    final title = _firstText(<Object?>[
      _firstMeta(meta, 'og:title'),
      _findFirstJsonValue(structuredData, const <String>['headline', 'name']),
      _readTitle(content),
    ]);
    final description = _firstText(<Object?>[
      _firstMeta(meta, 'og:description'),
      _firstMeta(meta, 'description'),
      _findFirstJsonValue(structuredData, const <String>['description']),
    ]);
    final caption = _firstText(<Object?>[
      _findFirstJsonValue(structuredData, const <String>['caption']),
    ]);
    final authorName = _firstText(<Object?>[
      _firstMeta(meta, 'author'),
      _findAuthor(structuredData),
    ]);
    final publishedAtText = _firstText(<Object?>[
      _firstMeta(meta, 'article:published_time'),
      _findFirstJsonValue(structuredData, const <String>[
        'datePublished',
        'uploadDate',
      ]),
    ]);

    final imageCandidates = <Object?>[
      ..._metaValues(meta, const <String>['og:image', 'og:image:url']),
      _findJsonValues(structuredData, const <String>{
        'image',
        'thumbnailUrl',
        'thumbnail',
      }),
    ];
    final videoCandidates = <Object?>[
      ..._metaValues(meta, const <String>[
        'og:video',
        'og:video:url',
        'og:video:secure_url',
      ]),
      _findJsonValues(structuredData, const <String>{
        'contentUrl',
        'embedUrl',
      }, onlyInsideVideoObject: true),
    ];

    return PublicPageMetadata(
      title: title,
      description: description,
      authorName: authorName,
      publishedAt: publishedAtText == null
          ? null
          : DateTime.tryParse(publishedAtText)?.toUtc(),
      caption: caption,
      bodyText: normalizedContentType == 'text/plain'
          ? _normalizeText(content)
          : null,
      imageUrls: _resolveUrls(imageCandidates, baseUri),
      videoUrls: _resolveUrls(videoCandidates, baseUri),
      imageMimeType: _firstMeta(meta, 'og:image:type'),
      videoMimeType: _firstMeta(meta, 'og:video:type'),
    );
  }

  static String? _normalizedContentType(String? header) {
    if (header == null) return null;
    final value = header.split(';').first.trim().toLowerCase();
    return value.isEmpty ? null : value;
  }

  static Map<String, List<String>> _readMeta(String html) {
    final values = <String, List<String>>{};
    final tagPattern = RegExp(r'<meta\b([^>]*?)>', caseSensitive: false);
    for (final match in tagPattern.allMatches(html)) {
      final attributes = _readAttributes(match.group(1) ?? '');
      final key = (attributes['property'] ?? attributes['name'])
          ?.trim()
          .toLowerCase();
      final value = _normalizeText(attributes['content']);
      if (key != null && key.isNotEmpty && value != null) {
        values.putIfAbsent(key, () => <String>[]).add(value);
      }
    }
    return values;
  }

  static String? _firstMeta(Map<String, List<String>> meta, String key) =>
      _firstText(meta[key] ?? const <String>[]);

  static Iterable<String> _metaValues(
    Map<String, List<String>> meta,
    Iterable<String> keys,
  ) sync* {
    for (final key in keys) {
      yield* meta[key] ?? const <String>[];
    }
  }

  static Map<String, String> _readAttributes(String source) {
    final attributes = <String, String>{};
    final pattern = RegExp(
      r'''([:\w-]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+))''',
      caseSensitive: false,
    );
    for (final match in pattern.allMatches(source)) {
      final name = match.group(1)!.toLowerCase();
      final value = match.group(2) ?? match.group(3) ?? match.group(4) ?? '';
      attributes[name] = _decodeHtmlEntities(value);
    }
    return attributes;
  }

  static String? _readTitle(String html) {
    final match = RegExp(
      r'<title\b[^>]*>([\s\S]*?)</title>',
      caseSensitive: false,
    ).firstMatch(html);
    return _normalizeText(match?.group(1));
  }

  static List<Object?> _readStandaloneJson(
    String content,
    String? contentType,
  ) {
    if (contentType != 'application/json') return const <Object?>[];
    final raw = content.trim();
    if (raw.isEmpty) return const <Object?>[];
    try {
      return <Object?>[jsonDecode(raw)];
    } on FormatException {
      return const <Object?>[];
    }
  }

  static List<Object?> _readJsonLd(String html) {
    final documents = <Object?>[];
    final pattern = RegExp(
      r'<script\b([^>]*?)>([\s\S]*?)</script>',
      caseSensitive: false,
    );
    for (final match in pattern.allMatches(html)) {
      final attributes = _readAttributes(match.group(1) ?? '');
      final type = attributes['type']?.trim().toLowerCase();
      if (type != 'application/ld+json') continue;
      final raw = (match.group(2) ?? '').trim();
      if (raw.isEmpty) continue;
      try {
        documents.add(jsonDecode(_decodeHtmlEntities(raw)));
      } on FormatException {
        // Optional malformed JSON-LD does not invalidate usable Open Graph data.
      }
    }
    return documents;
  }

  static Object? _findFirstJsonValue(Object? node, Iterable<String> keys) {
    for (final key in keys) {
      final found = _findJsonValue(node, key);
      if (found != null) return found;
    }
    return null;
  }

  static Object? _findJsonValue(Object? node, String key) {
    if (node is Map<Object?, Object?>) {
      if (node.containsKey(key)) {
        final value = _extractScalar(node[key]);
        if (value != null) return value;
      }
      for (final value in node.values) {
        final found = _findJsonValue(value, key);
        if (found != null) return found;
      }
    } else if (node is Iterable<Object?>) {
      for (final value in node) {
        final found = _findJsonValue(value, key);
        if (found != null) return found;
      }
    }
    return null;
  }

  static List<Object?> _findJsonValues(
    Object? node,
    Set<String> keys, {
    bool onlyInsideVideoObject = false,
  }) {
    final values = <Object?>[];

    void visit(Object? value, {bool insideVideoObject = false}) {
      if (value is Map<Object?, Object?>) {
        final typeText = _firstText(<Object?>[value['@type']])?.toLowerCase();
        final isVideo =
            insideVideoObject ||
            (typeText != null && typeText.contains('video'));
        for (final entry in value.entries) {
          if (entry.key is String &&
              keys.contains(entry.key) &&
              (!onlyInsideVideoObject || isVideo)) {
            values.add(entry.value);
          }
        }
        for (final child in value.values) {
          visit(child, insideVideoObject: isVideo);
        }
      } else if (value is Iterable<Object?>) {
        for (final child in value) {
          visit(child, insideVideoObject: insideVideoObject);
        }
      }
    }

    visit(node);
    return values;
  }

  static Object? _findAuthor(Object? node) {
    if (node is Map<Object?, Object?>) {
      if (node.containsKey('author')) {
        final author = node['author'];
        if (author is Map<Object?, Object?>) {
          return _extractScalar(author['name']);
        }
        if (author is Iterable<Object?>) {
          for (final value in author) {
            final found = _findAuthor(<String, Object?>{'author': value});
            if (found != null) return found;
          }
        }
        return _extractScalar(author);
      }
      for (final value in node.values) {
        final found = _findAuthor(value);
        if (found != null) return found;
      }
    } else if (node is Iterable<Object?>) {
      for (final value in node) {
        final found = _findAuthor(value);
        if (found != null) return found;
      }
    }
    return null;
  }

  static Object? _extractScalar(Object? value) {
    if (value is String || value is num || value is bool) return value;
    if (value is Map<Object?, Object?>) {
      return _extractScalar(
        value['url'] ?? value['contentUrl'] ?? value['name'] ?? value['@id'],
      );
    }
    if (value is Iterable<Object?>) {
      for (final child in value) {
        final scalar = _extractScalar(child);
        if (scalar != null) return scalar;
      }
    }
    return null;
  }

  static List<String> _resolveUrls(Iterable<Object?> candidates, Uri baseUri) {
    final result = <String>[];
    final seen = <String>{};

    void addCandidate(Object? candidate) {
      if (candidate is Iterable<Object?> && candidate is! String) {
        for (final child in candidate) {
          addCandidate(child);
        }
        return;
      }
      if (candidate is Map<Object?, Object?>) {
        addCandidate(
          candidate['url'] ??
              candidate['contentUrl'] ??
              candidate['embedUrl'] ??
              candidate['@id'],
        );
        return;
      }
      final text = _normalizeText(candidate?.toString());
      if (text == null) return;
      final parsed = Uri.tryParse(text);
      if (parsed == null) return;
      final resolved = baseUri.resolveUri(parsed);
      final scheme = resolved.scheme.toLowerCase();
      if ((scheme != 'http' && scheme != 'https') || !resolved.hasAuthority) {
        return;
      }
      final value = resolved.toString();
      if (seen.add(value)) result.add(value);
    }

    for (final candidate in candidates) {
      addCandidate(candidate);
    }
    return List<String>.unmodifiable(result);
  }

  static String? _firstText(Iterable<Object?> candidates) {
    for (final candidate in candidates) {
      if (candidate is Iterable<Object?> && candidate is! String) {
        final nested = _firstText(candidate);
        if (nested != null) return nested;
      } else {
        final normalized = _normalizeText(candidate?.toString());
        if (normalized != null) return normalized;
      }
    }
    return null;
  }

  static String? _normalizeText(String? value) {
    if (value == null) return null;
    final withoutTags = value.replaceAll(RegExp(r'<[^>]+>'), ' ');
    final normalized = _decodeHtmlEntities(
      withoutTags,
    ).replaceAll(RegExp(r'\s+'), ' ').trim();
    return normalized.isEmpty ? null : normalized;
  }

  static String _decodeHtmlEntities(String value) {
    return value.replaceAllMapped(
      RegExp(r'&(#x?[0-9a-f]+|\w+);', caseSensitive: false),
      (match) {
        final token = match.group(1)!;
        if (token.startsWith('#x') || token.startsWith('#X')) {
          final code = int.tryParse(token.substring(2), radix: 16);
          return code == null ? match.group(0)! : String.fromCharCode(code);
        }
        if (token.startsWith('#')) {
          final code = int.tryParse(token.substring(1));
          return code == null ? match.group(0)! : String.fromCharCode(code);
        }
        return switch (token.toLowerCase()) {
          'amp' => '&',
          'lt' => '<',
          'gt' => '>',
          'quot' => '"',
          'apos' => "'",
          'nbsp' => ' ',
          _ => match.group(0)!,
        };
      },
    );
  }
}
