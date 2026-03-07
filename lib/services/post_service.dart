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
    String? marketCategory,
    String? marketIntent,
    String? marketTitle,
    double? marketPrice,
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

    final payload = <String, dynamic>{
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
      'market_category': marketCategory,
      'market_intent': marketIntent,
      'market_title': marketTitle,
      'market_price': marketPrice,
    };

    try {
      await _db.from('posts').insert(payload);
    } on PostgrestException catch (e) {
       // Some deployments still enforce an older post_type CHECK that uses
      // 'food' instead of 'food_ad'. Retry with legacy value.
      if (_isPostTypeConstraintError(e) && postType == 'food_ad') {
        final legacy = Map<String, dynamic>.from(payload)..['post_type'] = 'food';
        await _db.from('posts').insert(legacy);
        return;
      }

      // Backward-compatible fallback for deployments where optional columns
      // (video_url / post_type / author_profile_type / market_category / market_intent) are not migrated yet.
      if (!_isMissingColumnError(e)) rethrow;

      await _db.from('posts').insert({
        'user_id': user.id,
        'content': content,
        'visibility': visibility,
        'latitude': latitude,
        'longitude': longitude,
        'location_name': locationName,
        'image_url': imageUrl,
      });
    }
  }

  bool _isPostTypeConstraintError(PostgrestException e) {
    final code = (e.code ?? '').trim();
    final msg = e.message.toLowerCase();

    return code == '23514' &&
        msg.contains('post') &&
        msg.contains('type') &&
        msg.contains('check');
  }

  bool _isMissingColumnError(PostgrestException e) {
    final code = (e.code ?? '').trim();
    final msg = e.message.toLowerCase();

    if (code == '42703') return true;

    return msg.contains('column') &&
        (msg.contains('video_url') ||
            msg.contains('post_type') ||
            msg.contains('author_profile_type') ||
            msg.contains('market_category') ||
            msg.contains('market_intent') ||
            msg.contains('market_title') ||
            msg.contains('market_price'));
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
    // Also force direct query for food filter to support both legacy 'food'
    // and newer 'food_ad' post_type values.
    final forceDirectQuery = postType == 'food_ad';
    if (lat == null || lng == null || forceDirectQuery) {
      if (scope != 'following') {
        // PUBLIC scope: only public posts (server-side filters + cursor)
        var q = _db
            .from('posts')
            .select('*, profiles(full_name, avatar_url)')
            .eq('visibility', 'public');

        if (postType != 'all') {
          if (postType == 'food_ad') {
            q = q.inFilter('post_type', ['food_ad', 'food']);
          } else {
            q = q.eq('post_type', postType);
          }
        }
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

      if (postType != 'all') {
        if (postType == 'food_ad') {
          q = q.inFilter('post_type', ['food_ad', 'food']);
        } else {
          q = q.eq('post_type', postType);
        }
      }
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
} // Added missing closing brace