// lib/models/post_model.dart

class Post {
  final String id;
  final String userId;
  final String content;
  final String? imageUrl;
  final String visibility;
  final String? locationName;
  final double latitude;
  final double longitude;
  final DateTime createdAt;

  // Author info (can come from joined select OR RPC)
  final String? authorName;
  final String? authorAvatarUrl;
  final String? authorType;

  // Post type + distance (distance comes from RPC)
  final String? postType;
  final double? distanceKm;

  Post({
    required this.id,
    required this.userId,
    required this.content,
    required this.visibility,
    required this.latitude,
    required this.longitude,
    required this.createdAt,
    this.imageUrl,
    this.locationName,
    this.authorName,
    this.authorAvatarUrl,
    this.authorType,
    this.postType,
    this.distanceKm,
  });

  factory Post.fromMap(Map<String, dynamic> map) {
    // When using: select('*, profiles(full_name, avatar_url)')
    // Supabase returns a nested "profiles" object.
    final profile = map['profiles'];

    // ✅ Works for BOTH:
    // - RPC: author_name / author_avatar_url
    // - Join: profiles.full_name / profiles.avatar_url
    final String? authorName =
        (map['author_name'] as String?) ??
        (profile is Map ? profile['full_name'] as String? : null);

    final String? authorAvatarUrl =
        (map['author_avatar_url'] as String?) ??
        (profile is Map ? profile['avatar_url'] as String? : null);

    return Post(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      content: (map['content'] ?? '') as String,
      imageUrl: map['image_url'] as String?,
      visibility: (map['visibility'] as String?) ?? 'public',
      locationName: map['location_name'] as String?,
      latitude: ((map['latitude'] as num?) ?? 0).toDouble(),
      longitude: ((map['longitude'] as num?) ?? 0).toDouble(),
      createdAt: DateTime.parse(map['created_at'] as String),

      authorName: authorName,
      authorAvatarUrl: authorAvatarUrl,
      authorType: map['author_profile_type'] as String?,

      postType: map['post_type'] as String?,

      // RPC returns distance_km; joined select usually doesn't
      distanceKm: (map['distance_km'] as num?)?.toDouble(),
    );
  }
}