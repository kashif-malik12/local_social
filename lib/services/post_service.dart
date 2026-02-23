// lib/services/post_service.dart
//
// ✅ Updated to implement cursor-based pagination for:
// (1) Public feed (no location): server-side filters + stable cursor (created_at + id)
// (2) Following feed (no location): server-side filters + stable cursor
// (3) RPC nearby_posts: passes cursor params (requires SQL function update)
//
// Notes:
// - This assumes posts.id is UUID (string). Cursor uses created_at + id.
// - For perfect tie-break, always pass both beforeCreatedAt and beforeId when paginating.

import 'dart:io' show File;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PostService {
  final SupabaseClient _db;
  PostService(this._db);

  Future<String> uploadPostImage({
    required XFile image,
    required String userId,
  }) async {
    final ext = image.name.split('.').last.toLowerCase();
    final safeExt = ext.isEmpty ? 'jpg' : ext;

    final fileName = '${DateTime.now().millisecondsSinceEpoch}.$safeExt';
    final path = '$userId/$fileName';

    if (kIsWeb) {
      final Uint8List bytes = await image.readAsBytes();

      await _db.storage.from('post-images').uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              upsert: false,
              contentType: _contentTypeFromExt(safeExt),
            ),
          );
    } else {
      final file = File(image.path);

      await _db.storage.from('post-images').upload(
            path,
            file,
            fileOptions: FileOptions(
              upsert: false,
              contentType: _contentTypeFromExt(safeExt),
            ),
          );
    }

    return _db.storage.from('post-images').getPublicUrl(path);
  }

  String _contentTypeFromExt(String ext) {
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      case 'jpg':
      case 'jpeg':
      default:
        return 'image/jpeg';
    }
  }

  Future<void> createPost({
    required String content,
    required String visibility,
    required double latitude,
    required double longitude,
    String? locationName,
    String? imageUrl,
    String? videoUrl,
    required String postType,
  }) async {
    final user = _db.auth.currentUser;
    if (user == null) throw Exception('Not logged in');

    final profile = await _db
        .from('profiles')
        .select('profile_type, account_type')
        .eq('id', user.id)
        .maybeSingle();

    final authorType = (profile?['profile_type'] as String?) ??
        (profile?['account_type'] as String?) ??
        'person';

    await _db.from('posts').insert({
      'user_id': user.id,
      'content': content,
      'visibility': visibility,
      'latitude': latitude,
      'longitude': longitude,
      'location_name': locationName,
      'image_url': imageUrl,
      'video_url': videoUrl,
      'post_type': postType,
      'author_profile_type': authorType,
    });
  }

  // -----------------------------
  // Cursor-based feed pagination
  // -----------------------------
  Future<List<Map<String, dynamic>>> fetchPublicFeed({
    int limit = 20,
    String postType = 'all',
    String authorType = 'all',
    String scope = 'all', // 'all' or 'following'
    DateTime? beforeCreatedAt,
    String? beforeId,
  }) async {
    final user = _db.auth.currentUser;
    if (user == null) return <Map<String, dynamic>>[];

    // 1) Load viewer profile location + radius
    final me = await _db
        .from('profiles')
        .select('latitude, longitude, radius_km')
        .eq('id', user.id)
        .maybeSingle();

    final lat = (me?['latitude'] as num?)?.toDouble();
    final lng = (me?['longitude'] as num?)?.toDouble();
    final radiusKm = (me?['radius_km'] as int?) ?? 5;

    // 2) Fallback if location isn't set
    if (lat == null || lng == null) {
      if (scope != 'following') {
        // PUBLIC scope: only public posts (server-side filters + cursor)
        var q = _db
            .from('posts')
            .select('*, profiles(full_name, avatar_url)')
            .eq('visibility', 'public');

        if (postType != 'all') q = q.eq('post_type', postType);
        if (authorType != 'all') q = q.eq('author_profile_type', authorType);

        // Cursor: older than (created_at, id)
        if (beforeCreatedAt != null) {
          final ts = beforeCreatedAt.toIso8601String();
          if (beforeId != null && beforeId.isNotEmpty) {
            q = q.or(
              'created_at.lt.$ts,and(created_at.eq.$ts,id.lt.$beforeId)',
            );
          } else {
            q = q.lt('created_at', ts);
          }
        }

        final data = await q
            .order('created_at', ascending: false)
            .order('id', ascending: false)
            .limit(limit);

        return (data as List).cast<Map<String, dynamic>>();
      }

      // FOLLOWING scope: posts from accepted followed users + self (server-side filters + cursor)
      final followed = await _db
          .from('follows')
          .select('followed_profile_id')
          .eq('follower_id', user.id)
          .eq('status', 'accepted');

      final ids = (followed as List)
          .map((e) => e['followed_profile_id'] as String?)
          .whereType<String>()
          .toSet();

      ids.add(user.id);
      if (ids.isEmpty) return <Map<String, dynamic>>[];

      var q = _db
          .from('posts')
          .select('*, profiles(full_name, avatar_url)')
          .inFilter('user_id', ids.toList());

      if (postType != 'all') q = q.eq('post_type', postType);
      if (authorType != 'all') q = q.eq('author_profile_type', authorType);

      if (beforeCreatedAt != null) {
        final ts = beforeCreatedAt.toIso8601String();
        if (beforeId != null && beforeId.isNotEmpty) {
          q = q.or(
            'created_at.lt.$ts,and(created_at.eq.$ts,id.lt.$beforeId)',
          );
        } else {
          q = q.lt('created_at', ts);
        }
      }

      final data = await q
          .order('created_at', ascending: false)
          .order('id', ascending: false)
          .limit(limit);

      return (data as List).cast<Map<String, dynamic>>();
    }

    // 3) Location exists: use RPC for distance-filtered feed
    // ✅ NEW: pass cursor params (requires SQL function update)
    final rows = await _db.rpc('nearby_posts', params: {
      'p_lat': lat,
      'p_lng': lng,
      'p_radius_km': radiusKm.toDouble(),
      'p_limit': limit,
      'p_post_type': postType,
      'p_author_type': authorType,
      'p_scope': scope == 'following' ? 'following' : 'public',
      'p_viewer_id': user.id,
      'p_before_created_at': beforeCreatedAt?.toIso8601String(),
      'p_before_id': beforeId,
    });

    return (rows as List).cast<Map<String, dynamic>>();
  }
}