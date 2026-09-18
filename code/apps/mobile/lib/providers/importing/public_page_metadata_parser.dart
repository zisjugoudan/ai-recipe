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
    final xiaohongshuNote = _readXiaohongshuInitialStateNote(content);

    final title = _firstUsableTitle(<Object?>[
      xiaohongshuNote?['title'],
      _firstMeta(meta, 'og:title'),
      _findFirstJsonValue(structuredData, const <String>['headline', 'name']),
      _readTitle(content),
    ], baseUri);
    final description = _firstText(<Object?>[
      xiaohongshuNote?['desc'],
      _firstMeta(meta, 'og:description'),
      _firstMeta(meta, 'description'),
      _findFirstJsonValue(structuredData, const <String>['description']),
    ]);
    final caption = _firstText(<Object?>[
      _findFirstJsonValue(structuredData, const <String>['caption']),
    ]);
    final authorName = _firstText(<Object?>[
      _asMap(xiaohongshuNote?['user'])?['nickName'],
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
    final publishedAt =
        _parseUnixTimestamp(xiaohongshuNote?['time']) ??
        (publishedAtText == null
            ? null
            : DateTime.tryParse(publishedAtText)?.toUtc());

    final imageCandidates = <Object?>[
      ..._resolveXiaohongshuImageList(xiaohongshuNote?['imageList'], baseUri),
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
      publishedAt: publishedAt,
      caption: caption,
      bodyText: normalizedContentType == 'text/plain'
          ? _normalizeText(content)
          : null,
      imageUrls: _resolveUrls(imageCandidates, baseUri)
          .where(_hasUsableImagePath)
          .toList(growable: false),
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

  static Map<Object?, Object?>? _readXiaohongshuInitialStateNote(String html) {
    final assignment = RegExp(
      r'window\.__INITIAL_STATE__\s*=',
      caseSensitive: true,
    ).firstMatch(html);
    if (assignment == null) return null;

    var objectStart = assignment.end;
    while (objectStart < html.length &&
        _isWhitespace(html.codeUnitAt(objectStart))) {
      objectStart += 1;
    }
    if (objectStart >= html.length || html.codeUnitAt(objectStart) != 0x7b) {
      return null;
    }

    final objectSource = _readBalancedJsonObject(html, objectStart);
    if (objectSource == null) return null;

    try {
      final root = _asMap(jsonDecode(_replaceBareUndefined(objectSource)));
      final noteStore = _asMap(root?['noteData']);
      final data = _asMap(noteStore?['data']);
      return _asMap(data?['noteData']);
    } on FormatException {
      // The initial state is optional. Keep Open Graph/JSON-LD fallbacks usable.
      return null;
    }
  }

  static String? _readBalancedJsonObject(String source, int start) {
    var depth = 0;
    var inString = false;
    var escaped = false;

    for (var index = start; index < source.length; index += 1) {
      final codeUnit = source.codeUnitAt(index);
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (codeUnit == 0x5c) {
          escaped = true;
        } else if (codeUnit == 0x22) {
          inString = false;
        }
        continue;
      }

      if (codeUnit == 0x22) {
        inString = true;
      } else if (codeUnit == 0x7b) {
        depth += 1;
      } else if (codeUnit == 0x7d) {
        depth -= 1;
        if (depth == 0) return source.substring(start, index + 1);
      }
    }
    return null;
  }

  static String _replaceBareUndefined(String source) {
    const token = 'undefined';
    final buffer = StringBuffer();
    var inString = false;
    var escaped = false;
    var index = 0;

    while (index < source.length) {
      final codeUnit = source.codeUnitAt(index);
      if (inString) {
        buffer.writeCharCode(codeUnit);
        if (escaped) {
          escaped = false;
        } else if (codeUnit == 0x5c) {
          escaped = true;
        } else if (codeUnit == 0x22) {
          inString = false;
        }
        index += 1;
        continue;
      }

      if (codeUnit == 0x22) {
        inString = true;
        buffer.writeCharCode(codeUnit);
        index += 1;
        continue;
      }

      if (source.startsWith(token, index) &&
          _hasTokenBoundary(source, index - 1) &&
          _hasTokenBoundary(source, index + token.length)) {
        buffer.write('null');
        index += token.length;
        continue;
      }

      buffer.writeCharCode(codeUnit);
      index += 1;
    }
    return buffer.toString();
  }

  static bool _hasTokenBoundary(String source, int index) {
    if (index < 0 || index >= source.length) return true;
    final codeUnit = source.codeUnitAt(index);
    final isAsciiLetter =
        (codeUnit >= 0x41 && codeUnit <= 0x5a) ||
        (codeUnit >= 0x61 && codeUnit <= 0x7a);
    final isDigit = codeUnit >= 0x30 && codeUnit <= 0x39;
    return !isAsciiLetter && !isDigit && codeUnit != 0x5f && codeUnit != 0x24;
  }

  static bool _isWhitespace(int codeUnit) =>
      codeUnit == 0x20 ||
      codeUnit == 0x09 ||
      codeUnit == 0x0a ||
      codeUnit == 0x0d;

  static Map<Object?, Object?>? _asMap(Object? value) =>
      value is Map<Object?, Object?> ? value : null;

  static DateTime? _parseUnixTimestamp(Object? value) {
    final numericValue = value is num
        ? value
        : value is String
        ? num.tryParse(value)
        : null;
    if (numericValue == null) return null;
    final milliseconds = numericValue.abs() >= 100000000000
        ? numericValue.round()
        : (numericValue * 1000).round();
    try {
      return DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);
    } on RangeError {
      return null;
    }
  }

  static String? _firstUsableTitle(Iterable<Object?> candidates, Uri baseUri) {
    for (final candidate in candidates) {
      if (candidate is Iterable<Object?> && candidate is! String) {
        final nested = _firstUsableTitle(candidate, baseUri);
        if (nested != null) return nested;
        continue;
      }
      final normalized = _normalizeText(candidate?.toString());
      if (normalized == null) continue;
      if (_isGenericXiaohongshuShellTitle(normalized, baseUri)) continue;
      return normalized;
    }
    return null;
  }

  static bool _isGenericXiaohongshuShellTitle(String title, Uri baseUri) {
    final host = baseUri.host.toLowerCase();
    final isXiaohongshu =
        host == 'xiaohongshu.com' ||
        host.endsWith('.xiaohongshu.com') ||
        host == 'xhslink.com' ||
        host.endsWith('.xhslink.com');
    if (!isXiaohongshu) return false;
    final normalized = _normalizeText(title)?.toLowerCase();
    return normalized == '小红书' || normalized == 'xiaohongshu';
  }

  static List<String> _resolveXiaohongshuImageList(
    Object? imageList,
    Uri baseUri,
  ) {
    final entries = imageList is Iterable<Object?> && imageList is! String
        ? imageList
        : <Object?>[imageList];
    final result = <String>[];
    final seen = <String>{};

    void addFirstResolved(Object? candidate) {
      // 只接受带实际资源路径的图片 URL；`https://ci.xiaohongshu.com/?imageMogr2/...`
      // 这类只有图片处理管道参数、缺少图片 ID 的残缺 URL 无法下载，直接跳过。
      final urls = _resolveUrls(<Object?>[candidate], baseUri)
          .where(_hasUsableImagePath)
          .toList(growable: false);
      if (urls.isEmpty) return;
      final url = urls.first;
      if (seen.add(url)) result.add(url);
    }

    for (final entry in entries) {
      if (entry is! Map<Object?, Object?>) {
        addFirstResolved(entry);
        continue;
      }

      var resolved = false;
      for (final key in const <String>[
        'urlDefault',
        'urlPre',
        'url',
        'urlList',
        'urls',
        'infoList',
        'urlSizeLarge',
        'urlSizeMedium',
        'urlSizeSmall',
      ]) {
        final urls = _resolveUrls(<Object?>[entry[key]], baseUri)
            .where(_hasUsableImagePath)
            .toList(growable: false);
        if (urls.isEmpty) continue;
        final url = urls.first;
        if (seen.add(url)) result.add(url);
        resolved = true;
        break;
      }
      if (!resolved) addFirstResolved(entry);
    }

    return List<String>.unmodifiable(result);
  }

  /// 图片 URL 必须带有实际资源路径；path 为空或仅 `/` 视为残缺地址。
  static bool _hasUsableImagePath(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    final path = uri.path;
    return path.isNotEmpty && path != '/';
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

    bool addCandidate(Object? candidate) {
      if (candidate is Iterable<Object?> && candidate is! String) {
        var found = false;
        for (final child in candidate) {
          found = addCandidate(child) || found;
        }
        return found;
      }
      if (candidate is Map<Object?, Object?>) {
        for (final key in const <String>[
          'urlDefault',
          'urlPre',
          'url',
          'urlList',
          'urls',
          'infoList',
          'urlSizeLarge',
          'urlSizeMedium',
          'urlSizeSmall',
          'contentUrl',
          'embedUrl',
          '@id',
        ]) {
          if (addCandidate(candidate[key])) return true;
        }
        return false;
      }
      final text = _normalizeText(candidate?.toString());
      if (text == null) return false;
      final parsed = Uri.tryParse(text);
      if (parsed == null) return false;
      final resolved = baseUri.resolveUri(parsed);
      final scheme = resolved.scheme.toLowerCase();
      if ((scheme != 'http' && scheme != 'https') || !resolved.hasAuthority) {
        return false;
      }
      final value = resolved.toString();
      if (seen.add(value)) result.add(value);
      return true;
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
