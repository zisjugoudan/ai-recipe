import 'dart:io';

import 'package:ai_recipe/providers/importing/public_page_metadata_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const parser = PublicPageMetadataParser();

  String fixture(String name) =>
      File('test/fixtures/importing/$name').readAsStringSync();

  test('merges Xiaohongshu Open Graph and JSON-LD metadata', () {
    final metadata = parser.parse(
      fixture('xiaohongshu_public.html'),
      baseUri: Uri.parse('https://www.xiaohongshu.com/explore/123'),
      contentType: 'text/html; charset=utf-8',
    );

    expect(metadata.title, 'Braised Chicken Wings & Potatoes');
    expect(
      metadata.description,
      'Chicken wings, potatoes, soy sauce. Brown, simmer, and reduce the sauce.',
    );
    expect(metadata.caption, 'Serve while hot.');
    expect(metadata.authorName, 'Kitchen Notes');
    expect(metadata.publishedAt, DateTime.utc(2026, 7, 20, 0, 30));
    expect(metadata.imageMimeType, 'image/jpeg');
    expect(metadata.imageUrls, <String>[
      'https://www.xiaohongshu.com/media/chicken-cover.jpg',
      'https://www.xiaohongshu.com/media/chicken-step-2.jpg',
    ]);
    expect(metadata.videoUrls, isEmpty);
  });

  test('extracts Douyin video, cover, author, and publication time', () {
    final metadata = parser.parse(
      fixture('douyin_public.html'),
      baseUri: Uri.parse('https://www.douyin.com/video/123456'),
      contentType: 'text/html',
    );

    expect(metadata.title, 'Quick Tomato Egg Stir Fry');
    expect(metadata.authorName, 'Home Cook');
    expect(metadata.publishedAt, DateTime.utc(2026, 7, 21, 1, 15));
    expect(metadata.imageUrls, <String>[
      'https://www.douyin.com/media/tomato-cover.jpg',
      'https://www.douyin.com/media/tomato-step.jpg',
    ]);
    expect(metadata.videoUrls, <String>[
      'https://www.douyin.com/video/tomato-egg.mp4',
      'https://www.douyin.com/video/123456',
    ]);
    expect(metadata.videoMimeType, 'video/mp4');
  });

  test('supports standalone public JSON metadata', () {
    final metadata = parser.parse(
      '''
      {
        "@type": "VideoObject",
        "name": "JSON recipe video",
        "description": "Public JSON description",
        "thumbnailUrl": "/cover.jpg",
        "contentUrl": "/recipe.mp4",
        "author": {"name": "JSON Cook"}
      }
      ''',
      baseUri: Uri.parse('https://www.douyin.com/api/public/1'),
      contentType: 'application/json; charset=utf-8',
    );

    expect(metadata.title, 'JSON recipe video');
    expect(metadata.description, 'Public JSON description');
    expect(metadata.authorName, 'JSON Cook');
    expect(metadata.imageUrls, <String>['https://www.douyin.com/cover.jpg']);
    expect(metadata.videoUrls, <String>['https://www.douyin.com/recipe.mp4']);
  });

  test('treats plain text as a usable body fragment', () {
    final metadata = parser.parse(
      '  Chop onions.\nThen simmer for 20 minutes.  ',
      baseUri: Uri.parse('https://www.xiaohongshu.com/note/plain'),
      contentType: 'text/plain',
    );

    expect(metadata.bodyText, 'Chop onions. Then simmer for 20 minutes.');
    expect(metadata.hasText, isTrue);
    expect(metadata.hasMedia, isFalse);
  });

  test('ignores malformed optional JSON-LD when Open Graph is usable', () {
    final metadata = parser.parse(
      '''
      <meta property="og:title" content="Safe title">
      <script type="application/ld+json">{broken</script>
      ''',
      baseUri: Uri.parse('https://www.xiaohongshu.com/explore/safe'),
      contentType: 'text/html',
    );

    expect(metadata.title, 'Safe title');
    expect(metadata.hasText, isTrue);
  });
}
