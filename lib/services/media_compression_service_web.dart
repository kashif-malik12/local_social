import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

class CompressedImageResult {
  const CompressedImageResult({
    required this.bytes,
    required this.extension,
    required this.contentType,
  });

  final Uint8List bytes;
  final String extension;
  final String contentType;
}

class MediaCompressionService {
  static Future<CompressedImageResult> compressImage(
    XFile image, {
    int quality = 78,
  }) async {
    final bytes = await image.readAsBytes();
    final ext = image.name.split('.').last.toLowerCase();
    final safeExt = ext.isEmpty ? 'jpg' : ext;
    return CompressedImageResult(
      bytes: bytes,
      extension: safeExt,
      contentType: _imageContentType(safeExt),
    );
  }

  static Future<XFile> compressVideo(XFile video) async => video;

  static Future<XFile?> generateVideoThumbnail(XFile video) async => null;

  static String _imageContentType(String ext) {
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      case 'jpg':
      case 'jpeg':
      default:
        return 'image/jpeg';
    }
  }
}
