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

import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'media_compression_service.dart';
import 'user_block_service.dart';

class PostService {
  final SupabaseClient _db;
  PostService(this._db);

  static const String postSelect =
      '*, profiles(full_name, avatar_url, city, zipcode, org_kind, business_type, business_name, job_title)';

  Future<String> _uploadImageXFile({
    required XFile image,
    required String userId,
  }) async {
    final compressed = await MediaCompressionService.compressImage(image);
    final safeExt = compressed.extension;

    final fileName = '${DateTime.now().millisecondsSinceEpoch}.$safeExt';
    final path = '$userId/$fileName';

    await _db.storage.from('post-images').uploadBinary(
          path,
          compressed.bytes,
          fileOptions: FileOptions(
            upsert: false,
            contentType: compressed.contentType,
          ),
        );

    return _db.storage.from('post-images').getPublicUrl(path);
  }

  Future<String> uploadPostImage({
    required XFile image,
    required String userId,
  }) async {
    return _uploadImageXFile(image: image, userId: userId);
  }

  Future<({String videoUrl, String? thumbnailUrl})> uploadPostVideo({
    required XFile video,
    required String userId,
  }) async {
    final preparedVideo = await MediaCompressionService.compressVideo(video);
    final thumbnailFile =
        await MediaCompressionService.generateVideoThumbnail(preparedVideo);
    final ext = preparedVideo.name.split('.').last.toLowerCase();
    final safeExt = ext.isEmpty ? 'mp4' : ext;

    final fileName = '${DateTime.now().millisecondsSinceEpoch}.$safeExt';
    final path = '$userId/$fileName';

    final Uint8List bytes = await preparedVideo.readAsBytes();
    await _db.storage.from('post-images').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            upsert: false,
            contentType: _videoContentTypeFromExt(safeExt),
          ),
        );

    final videoUrl = _db.storage.from('post-images').getPublicUrl(path);
    String? thumbnailUrl;
    if (thumbnailFile != null) {
      try {
        thumbnailUrl = await _uploadImageXFile(
          image: thumbnailFile,
          userId: userId,
        );
      } catch (_) {
        thumbnailUrl = null;
      }
    }

    return (
      videoUrl: videoUrl,
      thumbnailUrl: thumbnailUrl,
    );
  }

  Future<String?> createPost({
    required String content,
    required String visibility,
    required double latitude,
    required double longitude,
    String? locationName,
    String? imageUrl,
    String? secondImageUrl,
    String? videoUrl,
    required String postType,
    String? marketCategory,
    String? marketIntent,
    String? marketTitle,
    double? marketPrice,
    double? marketPriceMax,
    String shareScope = 'none',
    List<String> taggedUserIds = const [],
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

    var finalVisibility = visibility == 'local' ? 'followers' : visibility;
    // Enforce public for marketplace, gigs, lost & found, food ads, and organizations
    if (postType != 'post' || authorType == 'org') {
      finalVisibility = 'public';
    }

    final payload = <String, dynamic>{
      'user_id': user.id,
      'content': content,
      'visibility': finalVisibility,
      'latitude': latitude,
      'longitude': longitude,
      'location_name': locationName,
      'image_url': imageUrl,
      'second_image_url': secondImageUrl,
      'video_url': videoUrl,
      'post_type': postType,
      'author_profile_type': authorType,
      'market_category': marketCategory,
      'market_intent': marketIntent,
      'market_title': marketTitle,
      'market_price': marketPrice,
      'market_price_max': marketPriceMax,
      'share_scope': shareScope,
    };

    try {
      final inserted = await _db.from('posts').insert(payload).select('id').single();
      final postId = (inserted['id'] ?? '').toString();
      if (postId.isNotEmpty) {
        await _notifyTaggedUsers(postId: postId, taggedUserIds: taggedUserIds);
        return postId;
      }
      return null;
    } on PostgrestException catch (e) {
       // Some deployments still enforce an older post_type CHECK that uses
      // 'food' instead of 'food_ad'. Retry with legacy value.
      if (_isPostTypeConstraintError(e) && postType == 'food_ad') {
        final legacy = Map<String, dynamic>.from(payload)..['post_type'] = 'food';
        final inserted = await _db.from('posts').insert(legacy).select('id').single();
        final postId = (inserted['id'] ?? '').toString();
        if (postId.isNotEmpty) {
          await _notifyTaggedUsers(postId: postId, taggedUserIds: taggedUserIds);
          return postId;
        }
        return null;
      }

      // Backward-compatible fallback for deployments where optional columns
      // (second_image_url / video_url / post_type / author_profile_type / market_category / market_intent) are not migrated yet.
      if (!_isMissingColumnError(e)) rethrow;

      dynamic inserted;
      try {
        final retryPayload = Map<String, dynamic>.from(payload)..remove('second_image_url');
        inserted = await _db.from('posts').insert(retryPayload).select('id').single();
      } on PostgrestException catch (retryError) {
        if (!_isMissingColumnError(retryError)) rethrow;
        inserted = await _db.from('posts').insert({
          'user_id': user.id,
          'content': content,
          'visibility': finalVisibility,
          'latitude': latitude,
          'longitude': longitude,
          'location_name': locationName,
          'image_url': imageUrl,
        }).select('id').single();
      }

      final postId = (inserted['id'] ?? '').toString();
      if (postId.isNotEmpty) {
        await _notifyTaggedUsers(postId: postId, taggedUserIds: taggedUserIds);
        return postId;
      }
      return null;
    }
  }

  String _videoContentTypeFromExt(String ext) {
    switch (ext) {
      case 'mov':
        return 'video/quicktime';
      case 'webm':
        return 'video/webm';
      case 'm4v':
        return 'video/x-m4v';
      case 'mp4':
      default:
        return 'video/mp4';
    }
  }

  Future<void> _notifyTaggedUsers({
    required String postId,
    required List<String> taggedUserIds,
  }) async {
    final actorId = _db.auth.currentUser?.id;
    if (actorId == null) return;

    for (final recipientId in taggedUserIds.toSet()) {
      if (recipientId.isEmpty || recipientId == actorId) continue;
      try {
        await _db.rpc('create_mention_notification', params: {
          'p_recipient_id': recipientId,
          'p_actor_id': actorId,
          'p_post_id': postId,
          'p_comment_id': null,
        });
      } catch (_) {
        // Mentions are best-effort.
      }
    }
  }

  Future<void> deleteOwnPost(String postId) async {
    await _db.rpc('delete_own_post', params: {'p_post_id': postId});
  }

  Future<void> sharePost({
    required String originalPostId,
    required String originalAuthorId,
    required String originalVisibility,
    required double originalLatitude,
    required double originalLongitude,
    String? originalLocationName,
  }) async {
    final user = _db.auth.currentUser;
    if (user == null) throw Exception('Not logged in');
    if (originalAuthorId == user.id) {
      throw Exception('You cannot share your own post');
    }

    final profile = await _db
        .from('profiles')
        .select('profile_type, account_type, city, latitude, longitude')
        .eq('id', user.id)
        .maybeSingle();

    final authorType = (profile?['profile_type'] as String?) ??
        (profile?['account_type'] as String?) ??
        'person';

    final existing = await _db
        .from('posts')
        .select('id')
        .eq('user_id', user.id)
        .eq('shared_post_id', originalPostId)
        .maybeSingle();
    if (existing != null) {
      throw Exception('You already shared this post');
    }

    final inserted = await _db.from('posts').insert({
      'user_id': user.id,
      'content': '',
      'visibility': originalVisibility,
      'latitude': ((profile?['latitude'] as num?) ?? originalLatitude).toDouble(),
      'longitude': ((profile?['longitude'] as num?) ?? originalLongitude).toDouble(),
      'location_name': (profile?['city'] as String?) ?? originalLocationName,
      'post_type': 'post',
      'author_profile_type': authorType,
      'share_scope': 'none',
      'shared_post_id': originalPostId,
    }).select('id').single();

    final shareId = (inserted['id'] ?? '').toString();
    if (shareId.isEmpty) return;

    try {
      await _db.rpc('create_share_notification', params: {
        'p_recipient_id': originalAuthorId,
        'p_actor_id': user.id,
        'p_post_id': originalPostId,
      });
    } catch (_) {
      // Share notifications are best-effort.
    }
  }

  Future<List<Map<String, dynamic>>> attachSharedPosts(List<Map<String, dynamic>> rows) async {
    final rowIds = rows
        .map((row) => row['id']?.toString())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    final sharedIds = rows
        .map((row) => row['shared_post_id']?.toString())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    if (rowIds.isEmpty && sharedIds.isEmpty) return rows;

    final baseRows = rowIds.isEmpty
        ? const <Map<String, dynamic>>[]
        : (await _db
                .from('posts')
                .select(postSelect)
                .inFilter('id', rowIds)) as List;

    final sharedRows = sharedIds.isEmpty
        ? const <Map<String, dynamic>>[]
        : (await _db
                .from('posts')
                .select(postSelect)
                .inFilter('id', sharedIds)) as List;

    final filteredBaseRows =
        await excludeUnavailableAuthorRows(baseRows.cast<Map<String, dynamic>>());
    final filteredSharedRows =
        await excludeUnavailableAuthorRows(sharedRows.cast<Map<String, dynamic>>());

    final baseById = <String, Map<String, dynamic>>{};
    for (final row in filteredBaseRows) {
      final id = (row['id'] ?? '').toString();
      if (id.isNotEmpty) {
        baseById[id] = row;
      }
    }

    final byId = <String, Map<String, dynamic>>{};
    for (final row in filteredSharedRows) {
      final id = (row['id'] ?? '').toString();
      if (id.isNotEmpty) {
        byId[id] = row;
      }
    }

    return rows.map((row) {
      final rowId = row['id']?.toString();
      final sharedId = row['shared_post_id']?.toString();
      final base = rowId == null || rowId.isEmpty ? null : baseById[rowId];
      final mergedBase = base == null ? row : {...row, ...base};
      if (sharedId == null || sharedId.isEmpty) return mergedBase;
      final shared = byId[sharedId];
      if (shared == null) return mergedBase;
      return {
        ...mergedBase,
        'shared_post': shared,
      };
    }).toList();
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
            msg.contains('second_image_url') ||
            msg.contains('post_type') ||
            msg.contains('author_profile_type') ||
            msg.contains('market_category') ||
            msg.contains('market_intent') ||
            msg.contains('share_scope') ||
            msg.contains('shared_post_id') ||
            msg.contains('market_title') ||
            msg.contains('market_price'));
  }

  Future<Set<String>> fetchDisabledProfileIds(Iterable<String> profileIds) async {
    final ids = profileIds.where((id) => id.isNotEmpty).toSet().toList();
    if (ids.isEmpty) return <String>{};

    final rows = await _db
        .from('profiles')
        .select('id, is_disabled')
        .inFilter('id', ids);

    return (rows as List)
        .cast<Map<String, dynamic>>()
        .where((row) => row['is_disabled'] == true)
        .map((row) => (row['id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  Future<List<Map<String, dynamic>>> excludeDisabledAuthorRows(
    List<Map<String, dynamic>> rows, {
    String authorKey = 'user_id',
  }) async {
    if (rows.isEmpty) return rows;

    final disabledIds = await fetchDisabledProfileIds(
      rows.map((row) => (row[authorKey] ?? '').toString()),
    );

    if (disabledIds.isEmpty) return rows;

    return rows
        .where((row) => !disabledIds.contains((row[authorKey] ?? '').toString()))
        .toList();
  }

  Future<List<Map<String, dynamic>>> excludeBlockedAuthorRows(
    List<Map<String, dynamic>> rows, {
    String authorKey = 'user_id',
  }) async {
    if (rows.isEmpty) return rows;
    final blockedIds = await UserBlockService(_db).fetchBlockedRelatedUserIds();
    if (blockedIds.isEmpty) return rows;

    return rows
        .where((row) => !blockedIds.contains((row[authorKey] ?? '').toString()))
        .toList();
  }

  Future<List<Map<String, dynamic>>> excludeUnavailableAuthorRows(
    List<Map<String, dynamic>> rows, {
    String authorKey = 'user_id',
  }) async {
    final visibleRows = await excludeDisabledAuthorRows(rows, authorKey: authorKey);
    return excludeBlockedAuthorRows(visibleRows, authorKey: authorKey);
  }

  // -----------------------------
  // Cursor-based feed pagination
  // -----------------------------
  Future<List<Map<String, dynamic>>> fetchPublicFeed({
    int limit = 20,
    String postType = 'all',
    String authorType = 'all',
    String scope = 'all', // 'all' or 'following'
    int? radiusKmOverride,
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
    final radiusKm = radiusKmOverride ?? (me?['radius_km'] as int?) ?? 5;

    // 2) Fallback if location isn't set
    // Also force direct query for food filter to support both legacy 'food'
    // and newer 'food_ad' post_type values.
    final forceDirectQuery = postType == 'food_ad';
    if (lat == null || lng == null || forceDirectQuery) {
      if (scope != 'following') {
        // PUBLIC scope: only public posts (server-side filters + cursor)
        var q = _db
            .from('posts')
            .select(postSelect)
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

        return excludeUnavailableAuthorRows((data as List).cast<Map<String, dynamic>>());
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
          .select(postSelect)
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

      return excludeUnavailableAuthorRows((data as List).cast<Map<String, dynamic>>());
    }

    // 3) Location exists: use RPC for distance-filtered feed
    // ✅ NEW: pass cursor params (requires SQL function update)
    final rows = await _db.rpc('nearby_posts_city', params: {
      'p_lat': lat,
      'p_lng': lng,
      'p_radius_km': radiusKm.toDouble(),
      'p_limit': limit,
      'p_post_type': postType,
      'p_author_type': authorType,
      'p_scope': scope == 'following'
          ? 'following'
          : scope == 'all'
              ? 'all'
              : 'public',
      'p_viewer_id': user.id,
      'p_before_created_at': beforeCreatedAt?.toIso8601String(),
      'p_before_id': beforeId,
    });

    return excludeUnavailableAuthorRows((rows as List).cast<Map<String, dynamic>>());
  }
} // Added missing closing brace
