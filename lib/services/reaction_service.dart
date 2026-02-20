import 'package:supabase_flutter/supabase_flutter.dart';

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
        .select('id, content, created_at, user_id, profiles(full_name)')
        .eq('post_id', postId)
        .order('created_at', ascending: true);

    return (rows as List).cast<Map<String, dynamic>>();
  }

  Future<int> commentsCount(String postId) async {
    final rows = await _db.from('post_comments').select('id').eq('post_id', postId);
    return (rows as List).length;
  }

  Future<void> addComment(String postId, String content) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return;

    await _db.from('post_comments').insert({
      'post_id': postId,
      'user_id': _me,
      'content': trimmed,
    });
  }

  Future<void> deleteComment(String commentId) async {
    await _db.from('post_comments').delete().eq('id', commentId);
  }
}
