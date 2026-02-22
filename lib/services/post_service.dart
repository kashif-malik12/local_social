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
      'post_type': postType,
      'author_profile_type': authorType,
    });
  }

  Future<List<Map<String, dynamic>>> fetchPublicFeed({
    int limit = 50,
    String postType = 'all',
    String authorType = 'all',
    String scope = 'all', // 'all' or 'following'
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
      // PUBLIC scope: only public posts
      if (scope != 'following') {
        final data = await _db
            .from('posts')
            .select('*, profiles(full_name, avatar_url)')
            .eq('visibility', 'public')
            .order('created_at', ascending: false)
            .limit(limit);

        final list = (data as List).cast<Map<String, dynamic>>();

        // Apply optional filters client-side (simple & avoids query rebuild)
        return list.where((p) {
          final pt = p['post_type']?.toString() ?? '';
          final at = p['author_profile_type']?.toString() ?? '';
          if (postType != 'all' && pt != postType) return false;
          if (authorType != 'all' && at != authorType) return false;
          return true;
        }).toList();
      }

      // FOLLOWING scope: posts from followed users + self
      final followed = await _db
          .from('follows')
          .select('followed_profile_id')
          .eq('follower_id', user.id);

      final ids = (followed as List)
          .map((e) => e['followed_profile_id'] as String?)
          .whereType<String>()
          .toSet();

      ids.add(user.id); // include my own posts
      if (ids.isEmpty) return <Map<String, dynamic>>[];

      // No visibility filter here — RLS will enforce followers visibility
      final data = await _db
          .from('posts')
          .select('*, profiles(full_name, avatar_url)')
          .inFilter('user_id', ids.toList())
          .order('created_at', ascending: false)
          .limit(limit);

      final list = (data as List).cast<Map<String, dynamic>>();

      return list.where((p) {
        final pt = p['post_type']?.toString() ?? '';
        final at = p['author_profile_type']?.toString() ?? '';
        if (postType != 'all' && pt != postType) return false;
        if (authorType != 'all' && at != authorType) return false;
        return true;
      }).toList();
    }

    // 3) Location exists: use RPC for distance-filtered feed
    final rows = await _db.rpc('nearby_posts', params: {
      'p_lat': lat,
      'p_lng': lng,
      'p_radius_km': radiusKm.toDouble(),      'p_limit': limit,
      'p_post_type': postType,
      'p_author_type': authorType,
      'p_scope': scope == 'following' ? 'following' : 'public',
      'p_viewer_id': user.id,
    });

    return (rows as List).cast<Map<String, dynamic>>();
  }
}