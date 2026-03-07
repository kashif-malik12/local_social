import 'package:supabase_flutter/supabase_flutter.dart';

class OfferChatService {
  final SupabaseClient _db;
  OfferChatService(this._db);

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
}
