import 'package:supabase_flutter/supabase_flutter.dart';

class UserReportService {
  final SupabaseClient _db;
  UserReportService(this._db);

  Future<void> reportUser({
    required String reportedUserId,
    required String reason,
    String? details,
  }) async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) throw Exception('Not authenticated');

    final payload = {
      'reported_user_id': reportedUserId,
      'reporter_id': uid,
      'reason': reason.trim(),
      'details': (details ?? '').trim().isEmpty ? null : details!.trim(),
    };

    try {
      await _db.from('user_reports').insert(payload);
    } on PostgrestException catch (e) {
      if (e.code == '23505' || e.message.toLowerCase().contains('duplicate')) {
        throw Exception('You already reported this user.');
      }
      throw Exception(e.message);
    }
  }
}