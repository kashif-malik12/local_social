import 'package:supabase_flutter/supabase_flutter.dart';

class ReportService {
  final SupabaseClient _db;

  ReportService(this._db);

  Future<void> reportPost({
    required String postId,
    required String reason,
    String? details,
  }) async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) {
      throw Exception('Not authenticated');
    }

    final payload = {
      'post_id': postId,
      'reporter_id': uid,
      'reason': reason.trim(),
      'details': (details ?? '').trim().isEmpty ? null : details!.trim(),
    };

    try {
      await _db.from('post_reports').insert(payload);
    } on PostgrestException catch (e) {
      // unique violation (already reported)
      if (e.code == '23505' || e.message.toLowerCase().contains('duplicate')) {
        throw Exception('You already reported this post.');
      }
      throw Exception(e.message);
    }
  }
}