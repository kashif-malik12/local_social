import 'package:supabase_flutter/supabase_flutter.dart';

class OfferChatService {
  final SupabaseClient _db;
  OfferChatService(this._db);

  Future<String?> findConversationId({
    required String postId,
    required String otherUserId,
  }) async {
    final me = _db.auth.currentUser?.id;
    if (me == null) return null;

    final row = await _db
        .from('offer_conversations')
        .select('id')
        .eq('post_id', postId)
        .or(
          'and(buyer_id.eq.$me,seller_id.eq.$otherUserId),and(buyer_id.eq.$otherUserId,seller_id.eq.$me)',
        )
        .maybeSingle();

    final id = row?['id']?.toString();
    if (id == null || id.isEmpty) return null;
    return id;
  }

  Future<String> getOrCreateConversation({
    required String postId,
    required String otherUserId,
  }) async {
    final res = await _db.rpc('get_or_create_offer_conversation', params: {
      'p_post_id': postId,
      'p_other_user_id': otherUserId,
    });
    return (res as String);
  }

  Future<List<Map<String, dynamic>>> getChatList() async {
    final res = await _db.rpc('get_offer_chat_list');
    return (res as List).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> getMessages({
    required String conversationId,
    int limit = 50,
    String? beforeIso,
  }) async {
    final res = await _db.rpc('get_offer_messages', params: {
      'p_conversation_id': conversationId,
      'p_limit': limit,
      'p_before': beforeIso,
    });
    return (res as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> sendMessage({
    required String conversationId,
    required String content,
  }) async {
    final res = await _db.rpc('send_offer_message', params: {
      'p_conversation_id': conversationId,
      'p_content': content,
    });
    return (res as List).first as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> submitOffer({
    required String conversationId,
    required double amount,
  }) async {
    final res = await _db.rpc('submit_offer_amount', params: {
      'p_conversation_id': conversationId,
      'p_amount': amount,
    });
    return (res as List).first as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> respondToOffer({
    required String conversationId,
    required String decision,
  }) async {
    final res = await _db.rpc('respond_to_offer', params: {
      'p_conversation_id': conversationId,
      'p_decision': decision,
    });
    return (res as List).first as Map<String, dynamic>;
  }

  Future<int> markConversationRead(String conversationId) async {
    final res = await _db.rpc('mark_offer_conversation_read', params: {
      'p_conversation_id': conversationId,
    });
    return (res as num).toInt();
  }

  Future<void> deleteConversation(String conversationId) async {
    await _db.rpc('delete_offer_conversation', params: {
      'p_conversation_id': conversationId,
    });
  }

  /// Toggle ❤️ on an offer message.
  Future<void> toggleReaction(String messageId) async {
    final me = _db.auth.currentUser!.id;
    final existing = await _db
        .from('offer_message_reactions')
        .select('id')
        .eq('message_id', messageId)
        .eq('user_id', me)
        .maybeSingle();

    if (existing != null) {
      await _db
          .from('offer_message_reactions')
          .delete()
          .eq('message_id', messageId)
          .eq('user_id', me);
    } else {
      await _db.from('offer_message_reactions').insert({
        'message_id': messageId,
        'user_id': me,
      });
    }
  }

  /// Returns a map of messageId → {count, likedByMe} for the given message IDs.
  Future<Map<String, Map<String, dynamic>>> fetchReactions(
      List<String> messageIds) async {
    if (messageIds.isEmpty) return {};
    final me = _db.auth.currentUser!.id;
    final rows = await _db
        .from('offer_message_reactions')
        .select('message_id, user_id')
        .inFilter('message_id', messageIds);

    final result = <String, Map<String, dynamic>>{};
    for (final row in (rows as List).cast<Map<String, dynamic>>()) {
      final msgId = row['message_id'] as String;
      result.putIfAbsent(msgId, () => {'count': 0, 'liked_by_me': false});
      result[msgId]!['count'] = (result[msgId]!['count'] as int) + 1;
      if (row['user_id'] == me) result[msgId]!['liked_by_me'] = true;
    }
    return result;
  }
}
