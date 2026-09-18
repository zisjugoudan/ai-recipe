import 'package:ai_recipe/features/importing/import_image_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

void main() {
  group('DeviceImportImagePicker', () {
    test('returns null when the user cancels gallery selection', () async {
      final picker = DeviceImportImagePicker(
        pickGalleryImage: () async => null,
      );

      expect(await picker.pickImage(), isNull);
    });

    test('prefers a declared image MIME type', () async {
      final picker = DeviceImportImagePicker(
        pickGalleryImage: () async => XFile(
          '/private/selected.bin',
          mimeType: ' Image/PNG ',
        ),
      );

      final result = await picker.pickImage();

      expect(result?.localAssetId, '/private/selected.bin');
      expect(result?.mimeType, 'image/png');
    });

    test('infers supported MIME types from file extensions', () async {
      final cases = <String, String>{
        'photo.JPG': 'image/jpeg',
        'photo.jpeg': 'image/jpeg',
        'photo.PNG': 'image/png',
        'photo.webp': 'image/webp',
        'photo.gif': 'image/gif',
        'photo.heic': 'image/heic',
        'photo.heif': 'image/heif',
        'photo.bmp': 'image/bmp',
      };

      for (final entry in cases.entries) {
        final picker = DeviceImportImagePicker(
          pickGalleryImage: () async => XFile('/private/${entry.key}'),
        );
        expect((await picker.pickImage())?.mimeType, entry.value);
      }
    });

    test('keeps MIME type null when the extension is unknown', () async {
      final picker = DeviceImportImagePicker(
        pickGalleryImage: () async => XFile('/private/selected.unknown'),
      );

      expect((await picker.pickImage())?.mimeType, isNull);
    });

    test('rejects a declared non-image MIME type safely', () async {
      final picker = DeviceImportImagePicker(
        pickGalleryImage: () async => XFile(
          '/private/secret-video.mp4',
          mimeType: 'video/mp4',
        ),
      );

      await expectLater(
        picker.pickImage(),
        throwsA(
          isA<ImportImagePickerException>()
              .having(
                (error) => error.message,
                'message',
                '选择结果不是可处理的图片，请重新选择。',
              )
              .having(
                (error) => error.message,
                'safe message',
                isNot(contains('/private/secret-video.mp4')),
              ),
        ),
      );
    });

    test('maps permission PlatformException to a stable message', () async {
      final picker = DeviceImportImagePicker(
        pickGalleryImage: () async => throw PlatformException(
          code: 'photo_access_denied',
          message: '/private/secret.jpg',
        ),
      );

      await expectLater(
        picker.pickImage(),
        throwsA(
          isA<ImportImagePickerException>().having(
            (error) => error.message,
            'message',
            '未获得相册访问权限，请在系统设置中允许后重试。',
          ),
        ),
      );
    });

    test('hides unexpected picker exception details', () async {
      final picker = DeviceImportImagePicker(
        pickGalleryImage: () async =>
            throw StateError('failed at /private/secret.jpg'),
      );

      await expectLater(
        picker.pickImage(),
        throwsA(
          isA<ImportImagePickerException>()
              .having(
                (error) => error.message,
                'message',
                '无法打开系统图片选择器，请稍后重试。',
              )
              .having(
                (error) => error.message,
                'safe message',
                isNot(contains('/private/secret.jpg')),
              ),
        ),
      );
    });

    test('returns null when there is no Android lost data', () async {
      final picker = DeviceImportImagePicker(
        retrieveLostData: () async => LostDataResponse.empty(),
      );

      expect(await picker.retrieveLostImage(), isNull);
    });

    test('restores the first lost image and prefers files over file', () async {
      final first = XFile('/private/first.png');
      final legacy = XFile('/private/legacy.jpg');
      final picker = DeviceImportImagePicker(
        retrieveLostData: () async => LostDataResponse(
          file: legacy,
          files: <XFile>[first, legacy],
          type: RetrieveType.image,
        ),
      );

      final result = await picker.retrieveLostImage();

      expect(result?.localAssetId, '/private/first.png');
      expect(result?.mimeType, 'image/png');
    });

    test('maps lost-data failures without leaking plugin details', () async {
      final picker = DeviceImportImagePicker(
        retrieveLostData: () async => LostDataResponse(
          exception: PlatformException(
            code: 'retrieve_failed',
            message: '/private/secret.jpg',
          ),
          type: RetrieveType.image,
        ),
      );

      await expectLater(
        picker.retrieveLostImage(),
        throwsA(
          isA<ImportImagePickerException>()
              .having(
                (error) => error.message,
                'message',
                '无法恢复上次的图片选择结果，请重新选择。',
              )
              .having(
                (error) => error.message,
                'safe message',
                isNot(contains('/private/secret.jpg')),
              ),
        ),
      );
    });

    test('rejects lost video data as a non-image result', () async {
      final picker = DeviceImportImagePicker(
        retrieveLostData: () async => LostDataResponse(
          file: XFile('/private/video.mp4', mimeType: 'video/mp4'),
          type: RetrieveType.video,
        ),
      );

      await expectLater(
        picker.retrieveLostImage(),
        throwsA(
          isA<ImportImagePickerException>().having(
            (error) => error.message,
            'message',
            '选择结果不是可处理的图片，请重新选择。',
          ),
        ),
      );
    });
  });
}
