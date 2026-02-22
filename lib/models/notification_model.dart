class AppNotification {
  final String id;
  final String recipientId;
  final String? actorId;
  final String type; // follow|like|comment
  final String? postId;
  final String? commentId;
  final DateTime createdAt;
  final DateTime? readAt;

  final String? actorName;
  final String? actorAvatarUrl;

  AppNotification({
    required this.id,
    required this.recipientId,
    required this.type,
    required this.createdAt,
    this.actorId,
    this.postId,
    this.commentId,
    this.readAt,
    this.actorName,
    this.actorAvatarUrl,
  });

  factory AppNotification.fromMap(Map<String, dynamic> map) {
    final actor = map['actor'] as Map<String, dynamic>?;
    return AppNotification(
      id: map['id'] as String,
      recipientId: map['recipient_id'] as String,
      actorId: map['actor_id'] as String?,
      type: map['type'] as String,
      postId: map['post_id'] as String?,
      commentId: map['comment_id'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      readAt: map['read_at'] == null ? null : DateTime.parse(map['read_at'] as String),
      actorName: actor?['full_name'] as String?,
      actorAvatarUrl: actor?['avatar_url'] as String?,
    );
  }
}