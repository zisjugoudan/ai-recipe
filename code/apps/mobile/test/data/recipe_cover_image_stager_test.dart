import 'dart:io';

import 'package:ai_recipe/data/recipe_cover_image_stager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
  late Directory tempRoot;
  late Directory sourceDir;
  late DeviceRecipeCoverImageStager stager;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('cover-stager-test');
    sourceDir = Directory(path.join(tempRoot.path, 'sources'));
    await sourceDir.create();
    stager = DeviceRecipeCoverImageStager(
      baseDirectory: () async => Directory(path.join(tempRoot.path, 'covers')),
    );
  });

  tearDown(() async {
    try {
      await tempRoot.delete(recursive: true);
    } catch (_) {
      // best-effort 清理测试临时目录。
    }
  });

  Future<String> makeSource(String name, {int bytes = 32}) async {
    final file = File(path.join(sourceDir.path, name));
    await file.writeAsBytes(List<int>.filled(bytes, 65));
    return file.path;
  }

  test('copies a picked image into the private cover directory', () async {
    final source = await makeSource('photo.jpg');
    final target = await stager.copyIn(
      sourcePath: source,
      containerId: 'recipe-1',
      index: 0,
    );

    expect(path.basename(target), '0.jpg');
    expect(File(target).existsSync(), isTrue);
    expect(target, contains('recipe-1'));
  });

  test('normalizes unknown extensions and sanitizes container id', () async {
    final source = await makeSource('photo.heic-extra');
    final target = await stager.copyIn(
      sourcePath: source,
      containerId: '../recipe/1',
      index: 1,
    );

    expect(path.basename(target), '1.jpg');
    expect(target.contains('..'), isFalse);
    expect(File(target).existsSync(), isTrue);
  });

  test('rejects empty and oversized sources', () async {
    final empty = await makeSource('empty.png', bytes: 0);
    await expectLater(
      stager.copyIn(sourcePath: empty, containerId: 'r', index: 0),
      throwsA(isA<RecipeCoverImageException>()),
    );

    final small = await makeSource('small.png', bytes: 8);
    final limited = DeviceRecipeCoverImageStager(
      baseDirectory: () async => tempRoot,
      maxBytes: 4,
    );
    await expectLater(
      limited.copyIn(sourcePath: small, containerId: 'r', index: 0),
      throwsA(isA<RecipeCoverImageException>()),
    );
  });

  test('deleteFile and deleteContainer clean private files', () async {
    final source = await makeSource('photo.jpg');
    final target = await stager.copyIn(
      sourcePath: source,
      containerId: 'recipe-2',
      index: 0,
    );
    expect(File(target).existsSync(), isTrue);

    await stager.deleteFile(target);
    expect(File(target).existsSync(), isFalse);

    final second = await stager.copyIn(
      sourcePath: source,
      containerId: 'recipe-2',
      index: 0,
    );
    await stager.deleteContainer('recipe-2');
    expect(File(second).existsSync(), isFalse);
  });
}
