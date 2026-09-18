import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

class PickedImportImage {
  const PickedImportImage({required this.localAssetId, this.mimeType});

  final String localAssetId;
  final String? mimeType;
}

class ImportImagePickerException implements Exception {
  const ImportImagePickerException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract interface class ImportImagePicker {
  Future<PickedImportImage?> pickImage();

  /// 从系统相册多选图片（用于菜谱多封面图）。
  Future<List<PickedImportImage>> pickMultipleImages();

  Future<PickedImportImage?> retrieveLostImage();
}

typedef PickGalleryImage = Future<XFile?> Function();
typedef RetrieveLostImageData = Future<LostDataResponse> Function();

class DeviceImportImagePicker implements ImportImagePicker {
  DeviceImportImagePicker({
    ImagePicker? picker,
    PickGalleryImage? pickGalleryImage,
    RetrieveLostImageData? retrieveLostData,
  }) : _picker = picker ?? ImagePicker(),
       _pickGalleryImage = pickGalleryImage,
       _retrieveLostData = retrieveLostData;

  final ImagePicker _picker;
  final PickGalleryImage? _pickGalleryImage;
  final RetrieveLostImageData? _retrieveLostData;

  @override
  Future<PickedImportImage?> pickImage() async {
    try {
      final file = await (_pickGalleryImage?.call() ??
          _picker.pickImage(
            source: ImageSource.gallery,
            requestFullMetadata: false,
          ));
      return file == null ? null : _fromFile(file);
    } on PlatformException catch (error) {
      throw ImportImagePickerException(_messageFor(error, recovering: false));
    } on ImportImagePickerException {
      rethrow;
    } catch (_) {
      throw const ImportImagePickerException('无法打开系统图片选择器，请稍后重试。');
    }
  }

  @override
  Future<List<PickedImportImage>> pickMultipleImages() async {
    try {
      final files = await _picker.pickMultiImage(requestFullMetadata: false);
      return files.map(_fromFile).toList(growable: false);
    } on PlatformException catch (error) {
      throw ImportImagePickerException(_messageFor(error, recovering: false));
    } on ImportImagePickerException {
      rethrow;
    } catch (_) {
      throw const ImportImagePickerException('无法打开系统图片选择器，请稍后重试。');
    }
  }

  @override
  Future<PickedImportImage?> retrieveLostImage() async {
    try {
      final response = await (_retrieveLostData?.call() ??
          _picker.retrieveLostData());
      if (response.isEmpty) return null;
      final exception = response.exception;
      if (exception != null) {
        throw ImportImagePickerException(
          _messageFor(exception, recovering: true),
        );
      }
      if (response.type == RetrieveType.video) {
        throw const ImportImagePickerException('选择结果不是可处理的图片，请重新选择。');
      }
      final files = response.files;
      final file = files != null && files.isNotEmpty
          ? files.first
          : response.file;
      if (file == null) {
        throw const ImportImagePickerException('无法恢复上次的图片选择结果，请重新选择。');
      }
      return _fromFile(file);
    } on PlatformException catch (error) {
      throw ImportImagePickerException(_messageFor(error, recovering: true));
    } on ImportImagePickerException {
      rethrow;
    } catch (_) {
      throw const ImportImagePickerException('无法恢复上次的图片选择结果，请重新选择。');
    }
  }

  static PickedImportImage _fromFile(XFile file) {
    final declaredMime = file.mimeType?.trim().toLowerCase();
    if (declaredMime != null &&
        declaredMime.isNotEmpty &&
        !declaredMime.startsWith('image/')) {
      throw const ImportImagePickerException('选择结果不是可处理的图片，请重新选择。');
    }
    return PickedImportImage(
      localAssetId: file.path,
      mimeType: declaredMime == null || declaredMime.isEmpty
          ? _mimeTypeFromPath(file.path)
          : declaredMime,
    );
  }

  static String? _mimeTypeFromPath(String path) {
    final normalized = path.toLowerCase();
    final dot = normalized.lastIndexOf('.');
    if (dot < 0 || dot == normalized.length - 1) return null;
    return switch (normalized.substring(dot + 1)) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      'gif' => 'image/gif',
      'heic' => 'image/heic',
      'heif' => 'image/heif',
      'bmp' => 'image/bmp',
      _ => null,
    };
  }

  static String _messageFor(
    PlatformException error, {
    required bool recovering,
  }) {
    final code = error.code.toLowerCase();
    if (code.contains('denied') ||
        code.contains('permission') ||
        code.contains('access')) {
      return '未获得相册访问权限，请在系统设置中允许后重试。';
    }
    return recovering
        ? '无法恢复上次的图片选择结果，请重新选择。'
        : '无法打开系统图片选择器，请稍后重试。';
  }
}
