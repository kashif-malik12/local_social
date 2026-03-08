import 'package:supabase_flutter/supabase_flutter.dart';

import 'mention_service.dart';

class ReactionService {
  final SupabaseClient _db;
  ReactionService(this._db);

  String get _me => _db.auth.currentUser!.id;

  // ---------- Likes ----------
  Future<bool> isLiked(String postId) async {
    final row = await _db
        .from('post_likes')
        .select('post_id')
        .eq('post_id', postId)
        .eq('user_id', _me)
        .maybeSingle();
    return row != null;
  }

  Future<int> likesCount(String postId) async {
    final rows = await _db.from('post_likes').select('user_id').eq('post_id', postId);
    return (rows as List).length;
  }

  Future<void> like(String postId) async {
    await _db.from('post_likes').insert({'post_id': postId, 'user_id': _me});
  }

  Future<void> unlike(String postId) async {
    await _db
        .from('post_likes')
        .delete()
        .eq('post_id', postId)
        .eq('user_id', _me);
  }

  // ---------- Comments ----------
  Future<List<Map<String, dynamic>>> fetchComments(String postId) async {
    final rows = await _db
        .from('post_comments')
        .select('id, post_id, content, created_at, user_id, parent_comment_id, profiles(full_name, avatar_url), posts(user_id)')
        .eq('post_id', postId)
        .order('created_at', ascending: true);

    final comments = (rows as List).cast<Map<String, dynamic>>();
    if (comments.isEmpty) return comments;

    final ids = comments.map((e) => e['id']?.toString()).whereType<String>().toList();
    final likes = await _db
        .from('post_comment_likes')
        .select('comment_id, user_id')
        .inFilter('comment_id', ids);

    final likeRows = (likes as List).cast<Map<String, dynamic>>();
    final counts = <String, int>{};
    final liked = <String>{};
    for (final row in likeRows) {
      final commentId = (row['comment_id'] ?? '').toString();
      final userId = (row['user_id'] ?? '').toString();
      if (commentId.isEmpty) continue;
      counts[commentId] = (counts[commentId] ?? 0) + 1;
      if (userId == _me) liked.add(commentId);
    }

    return comments
        .map((comment) {
          final post = comment['posts'];
          return {
            ...comment,
            'post_owner_id': post is Map ? post['user_id']?.toString() : null,
            'like_count': counts[(comment['id'] ?? '').toString()] ?? 0,
            'liked_by_me': liked.contains((comment['id'] ?? '').toString()),
          };
        })
        .toList();
  }

  Future<int> commentsCount(String postId) async {
    final rows = await _db.from('post_comments').select('id').eq('post_id', postId);
    return (rows as List).length;
  }

  Future<void> addComment(
    String postId,
    String content, {
    String? parentCommentId,
    String? postOwnerId,
    String? parentCommentUserId,
    List<String> taggedUserIds = const [],
  }) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return;

    final inserted = await _db.from('post_comments').insert({
      'post_id': postId,
      'user_id': _me,
      'content': trimmed,
      'parent_comment_id': ?parentCommentId,
    }).select('id').single();

    final commentId = (inserted['id'] ?? '').toString();
    if (commentId.isEmpty) return;
    final allowedTaggedUserIds = await MentionService(_db).filterAllowedUserIds(taggedUserIds);
    final skipMentionRecipients = <String>{_me};

    if (parentCommentId != null &&
        parentCommentUserId != null &&
        parentCommentUserId.isNotEmpty &&
        parentCommentUserId != _me) {
      skipMentionRecipients.add(parentCommentUserId);
      await _notifyCommentEngagement(
        recipientId: parentCommentUserId,
        postId: postId,
        commentId: commentId,
        type: 'comment_reply',
      );
    }

    if (postOwnerId != null && postOwnerId.isNotEmpty && postOwnerId != _me) {
      skipMentionRecipients.add(postOwnerId);
      await _notifyCommentEngagement(
        recipientId: postOwnerId,
        postId: postId,
        commentId: commentId,
        type: 'comment',
      );
    }

    await _notifyTaggedUsers(
      postId: postId,
      commentId: commentId,
      taggedUserIds: allowedTaggedUserIds.where((id) => !skipMentionRecipients.contains(id)).toList(),
    );
  }

  Future<void> deleteComment(String commentId) async {
    await _db.from('post_comments').delete().eq('id', commentId);
  }

  Future<void> likeComment({
    required String commentId,
    required String postId,
    required String commentOwnerId,
  }) async {
    await _db.from('post_comment_likes').insert({
      'comment_id': commentId,
      'user_id': _me,
    });

    if (commentOwnerId.isNotEmpty && commentOwnerId != _me) {
      await _notifyCommentEngagement(
        recipientId: commentOwnerId,
        postId: postId,
        commentId: commentId,
        type: 'comment_like',
      );
    }
  }

  Future<void> unlikeComment(String commentId) async {
    await _db
        .from('post_comment_likes')
        .delete()
        .eq('comment_id', commentId)
        .eq('user_id', _me);
  }

  Future<void> _notifyCommentEngagement({
    required String recipientId,
    required String postId,
    required String commentId,
    required String type,
  }) async {
    try {
      await _db.rpc('create_comment_notification', params: {
        'p_recipient_id': recipientId,
        'p_actor_id': _me,
        'p_post_id': postId,
        'p_comment_id': commentId,
        'p_type': type,
      });
    } catch (_) {
      // Notifications are best-effort.
    }
  }

  Future<void> _notifyTaggedUsers({
    required String postId,
    required String commentId,
    required List<String> taggedUserIds,
  }) async {
    for (final recipientId in taggedUserIds.toSet()) {
      if (recipientId.isEmpty || recipientId == _me) continue;
      try {
        await _db.rpc('create_mention_notification', params: {
          'p_recipient_id': recipientId,
          'p_actor_id': _me,
          'p_post_id': postId,
          'p_comment_id': commentId,
        });
      } catch (_) {
        try {
          await _db.from('notifications').insert({
            'recipient_id': recipientId,
            'actor_id': _me,
            'post_id': postId,
            'comment_id': commentId,
            'type': 'mention',
          });
        } catch (_) {
          // Mentions are best-effort.
        }
      }
    }
  }
}
