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
      // ✅ Web: upload bytes
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
      // ✅ Mobile: upload file
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

    // If bucket is PUBLIC:
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

// 🔹 Fetch profile type
final profile = await _db
    .from('profiles')
    .select('profile_type, account_type')
    .eq('id', user.id)
    .maybeSingle();

final authorType =
    (profile?['profile_type'] as String?) ??
    (profile?['account_type'] as String?) ??
    'person';

// 🔹 Insert post
await _db.from('posts').insert({
  'user_id': user.id,
  'content': content,
  'visibility': visibility,
  'latitude': latitude,
  'longitude': longitude,
  'location_name': locationName,
  'image_url': imageUrl,
  'post_type': postType,
  'author_profile_type': authorType, // ✅ NEW
});

}


  Future<List<Map<String, dynamic>>> fetchPublicFeed({
  int limit = 50,
  String postType = 'all',
  String authorType = 'all',
  String scope = 'all', // ✅ 'all' or 'following'
}) async {
  final user = _db.auth.currentUser; // can be null if logged out

  var query = await _db
      .from('posts')
      .select('*, profiles(full_name)')
      .eq('visibility', 'public')
      .order('created_at', ascending: false)
      .limit(limit);

  // ✅ Filter by post type
  if (postType != 'all') {
    query = await _db
        .from('posts')
        .select('*, profiles(full_name)')
        .eq('visibility', 'public')
        .eq('post_type', postType)
        .order('created_at', ascending: false)
        .limit(limit);
  }

  // ✅ Filter by author type
  if (authorType != 'all') {
    query = await _db
        .from('posts')
        .select('*, profiles(full_name)')
        .eq('visibility', 'public')
        .eq('author_profile_type', authorType)
        .order('created_at', ascending: false)
        .limit(limit);
  }

  // ✅ Following scope (only show posts whose user_id is in followed profiles)
  if (scope == 'following') {
    if (user == null) {
      // Not logged in: no following feed
      return <Map<String, dynamic>>[];
    }

    // 1) get followed profile ids
    final followed = await _db
        .from('follows')
        .select('followed_profile_id')
        .eq('follower_id', user.id);

    final ids = (followed as List)
        .map((e) => e['followed_profile_id'] as String?)
        .whereType<String>()
        .toList();

    if (ids.isEmpty) return <Map<String, dynamic>>[];

    // 2) posts.user_id references profiles.id in your setup (same uuid)
    query = await _db
        .from('posts')
        .select('*, profiles(full_name)')
        .eq('visibility', 'public')
        .inFilter('user_id', ids)
        .order('created_at', ascending: false)
        .limit(limit);
  }

  return (query as List).cast<Map<String, dynamic>>();
}

}