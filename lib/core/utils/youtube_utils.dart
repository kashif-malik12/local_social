String? extractYoutubeId(String? url) {
  if (url == null || url.trim().isEmpty) return null;

  final uri = Uri.tryParse(url.trim());
  if (uri == null) return null;

  final host = uri.host.toLowerCase();

  // Short link: https://youtu.be/VIDEO_ID
  if (host.contains('youtu.be')) {
    return uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
  }

  // Normal link: https://www.youtube.com/watch?v=VIDEO_ID
  final v = uri.queryParameters['v'];
  if (v != null && v.isNotEmpty) return v;

  // Embed link: https://www.youtube.com/embed/VIDEO_ID
  final segments = uri.pathSegments;
  final embedIndex = segments.indexOf('embed');
  if (embedIndex != -1 && segments.length > embedIndex + 1) {
    return segments[embedIndex + 1];
  }

  return null;
}

String? youtubeThumbnailUrlFromId(String videoId) {
  // Best quality often available (not always), fallback handled by Image errorBuilder if needed.
  return 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg';
}