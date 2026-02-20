import 'package:supabase_flutter/supabase_flutter.dart';

class FollowService {
  final SupabaseClient _db;

  FollowService(this._db);

  Future<bool> isFollowing(String profileId) async {
    final myUserId = _db.auth.currentUser!.id;

    final row = await _db
        .from('follows')
        .select('id')
        .eq('follower_id', myUserId)
        .eq('followed_profile_id', profileId)
        .maybeSingle();

    return row != null;
  }

  Future<void> follow(String profileId) async {
    final myUserId = _db.auth.currentUser!.id;

    await _db.from('follows').insert({
      'follower_id': myUserId,
      'followed_profile_id': profileId,
    });
  }

  Future<void> unfollow(String profileId) async {
    final myUserId = _db.auth.currentUser!.id;

    await _db
        .from('follows')
        .delete()
        .eq('follower_id', myUserId)
        .eq('followed_profile_id', profileId);
  }
}
