import 'dart:convert';

class ChatMessagePayload {
  const ChatMessagePayload({
    required this.text,
    this.imageUrl,
    this.fileUrl,
    this.fileName,
    this.replyToId,
    this.replyToText,
    this.replyToSenderName,
  });

  final String text;
  final String? imageUrl;
  final String? fileUrl;
  final String? fileName;
  final String? replyToId;
  final String? replyToText;
  final String? replyToSenderName;

  bool get hasImage => (imageUrl ?? '').trim().isNotEmpty;
  bool get hasFile => (fileUrl ?? '').trim().isNotEmpty;
  bool get hasAttachments => hasImage || hasFile;
  bool get hasReply => (replyToId ?? '').trim().isNotEmpty;
}

class ChatMessageCodec {
  static const String _prefix = '[[chat_attachment_v1]]';

  static String encode({
    required String text,
    String? imageUrl,
    String? fileUrl,
    String? fileName,
    String? replyToId,
    String? replyToText,
    String? replyToSenderName,
  }) {
    final payload = <String, dynamic>{
      'text': text,
      'image_url': imageUrl,
      'file_url': fileUrl,
      'file_name': fileName,
      'reply_to_id': replyToId,
      'reply_to_text': replyToText,
      'reply_to_sender': replyToSenderName,
    };
    return '$_prefix${jsonEncode(payload)}';
  }

  static ChatMessagePayload decode(String raw) {
    if (!raw.startsWith(_prefix)) {
      return ChatMessagePayload(text: raw);
    }

    try {
      final parsed = jsonDecode(raw.substring(_prefix.length));
      if (parsed is! Map) {
        return ChatMessagePayload(text: raw);
      }
      final payload = Map<String, dynamic>.from(parsed);
      return ChatMessagePayload(
        text: (payload['text'] ?? '').toString(),
        imageUrl: payload['image_url']?.toString(),
        fileUrl: payload['file_url']?.toString(),
        fileName: payload['file_name']?.toString(),
        replyToId: payload['reply_to_id']?.toString(),
        replyToText: payload['reply_to_text']?.toString(),
        replyToSenderName: payload['reply_to_sender']?.toString(),
      );
    } catch (_) {
      return ChatMessagePayload(text: raw);
    }
  }

  static String previewText(String raw) {
    final payload = decode(raw);
    if (!payload.hasAttachments) {
      return payload.text.trim();
    }

    final parts = <String>[];
    if (payload.text.trim().isNotEmpty) parts.add(payload.text.trim());
    if (payload.hasImage) parts.add('Photo');
    if (payload.hasFile) {
      parts.add(payload.fileName?.trim().isNotEmpty == true
        ? 'File: ${payload.fileName!.trim()}'
        : 'File');
    }
    return parts.join(' • ');
  }
}
