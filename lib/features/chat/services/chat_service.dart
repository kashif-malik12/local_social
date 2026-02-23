import 'package:supabase_flutter/supabase_flutter.dart';

class ChatService {
  final SupabaseClient _db;
  ChatService(this._db);

  String get myId => _db.auth.currentUser!.id;

  Future<String> getOrCreateConversation(String otherUserId) async {
    final res = await _db.rpc('get_or_create_conversation', params: {
      'p_other_user_id': otherUserId,
    });
    return (res as String);
  }

  Future<List<Map<String, dynamic>>> getChatList() async {
    final res = await _db.rpc('get_chat_list');
    return (res as List).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> getMessages({
    required String conversationId,
    int limit = 50,
    String? beforeIso, // created_at ISO string
  }) async {
    final res = await _db.rpc('get_messages', params: {
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
    final res = await _db.rpc('send_message', params: {
      'p_conversation_id': conversationId,
      'p_content': content,
    });

    // send_message returns a table => List with single row
    final row = (res as List).first as Map<String, dynamic>;
    return row;
  }

  Future<int> markConversationRead(String conversationId) async {
    final res = await _db.rpc('mark_conversation_read', params: {
      'p_conversation_id': conversationId,
    });
    return (res as num).toInt();
  }

  Future<int> getUnreadTotal() async {
    final res = await _db.rpc('get_unread_total');
    return (res as num).toInt();
  }
}