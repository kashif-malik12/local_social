import 'package:supabase_flutter/supabase_flutter.dart';

class UserBlockService {
  final SupabaseClient _db;

  UserBlockService(this._db);

  Future<void> blockUser(String blockedUserId) async {
    final me = _db.auth.currentUser?.id;
    if (me == null) throw Exception('Not logged in');
    if (blockedUserId.isEmpty || blockedUserId == me) {
      throw Exception('Invalid user');
    }

    try {
      await _db.from('user_blocks').insert({
        'blocker_id': me,
        'blocked_id': blockedUserId,
      });
    } on PostgrestException catch (e) {
      final message = e.message.toLowerCase();
      if ((e.code ?? '') == '23505' || message.contains('duplicate')) {
        return;
      }
      rethrow;
    }
  }
}
