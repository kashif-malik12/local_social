import 'package:supabase_flutter/supabase_flutter.dart';

enum FollowStatus { none, pending, accepted, declined }

class FollowService {
  final SupabaseClient _db;
  FollowService(this._db);

  String get _me => _db.auth.currentUser!.id;

  FollowStatus _parseStatus(String? s) {
    switch (s) {
      case 'pending':
        return FollowStatus.pending;
      case 'accepted':
        return FollowStatus.accepted;
      case 'declined':
        return FollowStatus.declined;
      default:
        return FollowStatus.none;
    }
  }

  /// Status of my relationship to profileId
  Future<FollowStatus> getMyStatus(String profileId) async {
    final row = await _db
        .from('follows')
        .select('status')
        .eq('follower_id', _me)
        .eq('followed_profile_id', profileId)
        .maybeSingle();

    return _parseStatus(row?['status'] as String?);
  }

  /// Create a follow request (pending)
  /// ✅ Notifications are created by DB trigger (_notify_follow)
  Future<void> requestFollow(String profileId) async {
    // Do not allow following yourself
    if (profileId == _me) return;

    // If a row already exists (declined/pending/accepted), update it.
    final existing = await _db
        .from('follows')
        .select('id, status')
        .eq('follower_id', _me)
        .eq('followed_profile_id', profileId)
        .maybeSingle();

    if (existing != null) {
      final status = existing['status'] as String?;
      // If already accepted, nothing to do
      if (status == 'accepted') return;

      // If pending/declined -> set back to pending + refresh requested_at
      await _db
          .from('follows')
          .update({
            'status': 'pending',
            'requested_at': DateTime.now().toIso8601String(),
            'responded_at': null,
          })
          .eq('follower_id', _me)
          .eq('followed_profile_id', profileId);

      return;
    }

    // No existing row -> insert new pending request
    await _db.from('follows').insert({
      'follower_id': _me,
      'followed_profile_id': profileId,
      'status': 'pending',
    });

    // ✅ No notifications insert here (DB trigger handles it)
  }

  /// Cancel request OR unfollow (delete row)
  Future<void> cancelOrUnfollow(String profileId) async {
    await _db
        .from('follows')
        .delete()
        .eq('follower_id', _me)
        .eq('followed_profile_id', profileId);
  }

  /// Incoming pending follow requests to me
  Future<List<Map<String, dynamic>>> incomingRequests({int limit = 100}) async {
    final rows = await _db
        .from('follows')
        .select('follower_id, requested_at')
        .eq('followed_profile_id', _me)
        .eq('status', 'pending')
        .order('requested_at', ascending: false)
        .limit(limit);

    final list = (rows as List).cast<Map<String, dynamic>>();
    final followerIds = list.map((e) => e['follower_id'] as String).toList();

    if (followerIds.isEmpty) return list;

    final profRows = await _db
        .from('profiles')
        .select('id, full_name, avatar_url')
        .inFilter('id', followerIds);

    final profMap = {
      for (final p in (profRows as List).cast<Map<String, dynamic>>())
        p['id'] as String: p
    };

    // attach profile data in same shape your screen expects
    return list.map((r) {
      final fid = r['follower_id'] as String;
      return {
        ...r,
        'profiles': profMap[fid],
      };
    }).toList();
  }

  /// Accept an incoming request from followerId -> me
  /// ✅ Notifications are created by DB trigger on UPDATE (pending -> accepted)
  Future<void> acceptRequest(String followerId) async {
    await _db
        .from('follows')
        .update({
          'status': 'accepted',
          'responded_at': DateTime.now().toIso8601String(),
        })
        .eq('followed_profile_id', _me)
        .eq('follower_id', followerId)
        .eq('status', 'pending');

    // ✅ No notifications insert here (DB trigger handles it)
  }

  /// Decline an incoming request from followerId -> me
  /// (No notification by default)
  Future<void> declineRequest(String followerId) async {
    await _db
        .from('follows')
        .update({
          'status': 'declined',
          'responded_at': DateTime.now().toIso8601String(),
        })
        .eq('followed_profile_id', _me)
        .eq('follower_id', followerId)
        .eq('status', 'pending');
  }

  /// Counts should include accepted only
  Future<int> followersCount(String profileId) async {
    final rows = await _db
        .from('follows')
        .select('follower_id')
        .eq('followed_profile_id', profileId)
        .eq('status', 'accepted');
    return (rows as List).length;
  }

  Future<int> followingCount(String profileId) async {
    final rows = await _db
        .from('follows')
        .select('followed_profile_id')
        .eq('follower_id', profileId)
        .eq('status', 'accepted');
    return (rows as List).length;
  }
}