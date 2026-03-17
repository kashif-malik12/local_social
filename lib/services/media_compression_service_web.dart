import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

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
  static const int _maxDimension = 1600;

  static Future<CompressedImageResult> compressImage(
    XFile image, {
    int quality = 78,
  }) async {
    final bytes = await image.readAsBytes();
    try {
      final compressed = await _compressViaCanvas(bytes, quality: quality);
      return CompressedImageResult(
        bytes: compressed,
        extension: 'jpg',
        contentType: 'image/jpeg',
      );
    } catch (_) {
      // Canvas compression failed — fall back to raw bytes.
      final ext = image.name.split('.').last.toLowerCase();
      final safeExt = ext.isEmpty ? 'jpg' : ext;
      return CompressedImageResult(
        bytes: bytes,
        extension: safeExt,
        contentType: _imageContentType(safeExt),
      );
    }
  }

  static Future<Uint8List> _compressViaCanvas(
    Uint8List input, {
    required int quality,
  }) async {
    final blob = html.Blob([input]);
    final url = html.Url.createObjectUrlFromBlob(blob);
    try {
      final img = html.ImageElement()..src = url;
      await img.onLoad.first;

      final origW = img.naturalWidth;
      final origH = img.naturalHeight;

      int targetW = origW;
      int targetH = origH;
      if (origW > _maxDimension || origH > _maxDimension) {
        if (origW >= origH) {
          targetW = _maxDimension;
          targetH = (origH * _maxDimension / origW).round();
        } else {
          targetH = _maxDimension;
          targetW = (origW * _maxDimension / origH).round();
        }
      }

      final canvas = html.CanvasElement(width: targetW, height: targetH);
      canvas.context2D.drawImageScaled(img, 0, 0, targetW, targetH);

      final dataUrl = canvas.toDataUrl('image/jpeg', quality / 100);
      final base64 = dataUrl.split(',').last;
      return base64Decode(base64);
    } finally {
      html.Url.revokeObjectUrl(url);
    }
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
