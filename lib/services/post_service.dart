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
    .select('profile_type')
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


  Future<List<Map<String, dynamic>>> fetchPublicFeed({int limit = 50}) async {
    final res = await _db
        .from('posts')
        .select('*, profiles(full_name, account_type)')
        .eq('visibility', 'public')
        .order('created_at', ascending: false)
        .limit(limit);

    return (res as List).cast<Map<String, dynamic>>();
  }
}
