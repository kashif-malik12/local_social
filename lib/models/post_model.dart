class Post {
  final String id;
  final String userId;
  final String content;

  final String? imageUrl;
  final String? secondImageUrl;
  final String? videoUrl;
  final String shareScope;
  final String? sharedPostId;
  final Post? sharedPost;

  final String visibility;
  final String? locationName;

  final double latitude;
  final double longitude;

  final DateTime createdAt;

  final String? authorName;
  final String? authorAvatarUrl;
  final String? authorType;
  final String? authorOrgKind;
  final String? authorCity;
  final String? authorZipcode;
  final String? authorBusinessType;
  final String? authorBusinessName;
  final String? authorJobTitle;

  final String? postType;
  final String? marketCategory;
  final String? marketIntent;
  final String? marketTitle;
  final double? marketPrice;
  final double? marketPriceMax;
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
    this.secondImageUrl,
    this.videoUrl,
    this.shareScope = 'none',
    this.sharedPostId,
    this.sharedPost,
    this.locationName,
    this.authorName,
    this.authorAvatarUrl,
    this.authorType,
    this.authorOrgKind,
    this.authorCity,
    this.authorZipcode,
    this.authorBusinessType,
    this.authorBusinessName,
    this.authorJobTitle,
    this.postType,
    this.marketCategory,
    this.marketIntent,
    this.marketTitle,
    this.marketPrice,
    this.marketPriceMax,
    this.distanceKm,
  });

  factory Post.fromMap(Map<String, dynamic> map) {
    final rawProfile = map['profiles'];
    final profile = rawProfile is List
        ? (rawProfile.isNotEmpty && rawProfile.first is Map
            ? Map<String, dynamic>.from(rawProfile.first as Map)
            : null)
        : (rawProfile is Map ? Map<String, dynamic>.from(rawProfile) : null);
    final nestedSharedPost = map['shared_post'];

    final String? authorName =
        (map['author_name'] as String?) ??
        profile?['full_name'] as String?;

    final String? authorAvatarUrl =
        (map['author_avatar_url'] as String?) ??
        profile?['avatar_url'] as String?;

    final String? authorCity =
        (map['author_city'] as String?) ??
        profile?['city'] as String?;

    final String? authorOrgKind =
        (map['author_org_kind'] as String?) ??
        profile?['org_kind'] as String?;

    final String? authorZipcode =
        (map['author_zipcode'] as String?) ??
        profile?['zipcode'] as String?;

    final String? authorBusinessType = profile?['business_type'] as String?;

    final String? authorBusinessName =
        (map['author_business_name'] as String?) ??
        profile?['business_name'] as String?;

    final String? authorJobTitle = profile?['job_title'] as String?;

    return Post(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      content: (map['content'] ?? '') as String,
      imageUrl: map['image_url'] as String?,
      secondImageUrl: map['second_image_url'] as String?,
      videoUrl: map['video_url'] as String?,
      shareScope: (map['share_scope'] as String?) ?? 'none',
      sharedPostId: map['shared_post_id'] as String?,
      sharedPost: nestedSharedPost is Map
          ? Post.fromMap(Map<String, dynamic>.from(nestedSharedPost))
          : null,
      visibility: (map['visibility'] as String?) ?? 'public',
      locationName: map['location_name'] as String?,
      latitude: ((map['latitude'] as num?) ?? 0).toDouble(),
      longitude: ((map['longitude'] as num?) ?? 0).toDouble(),
      createdAt: DateTime.parse(map['created_at'] as String),
      authorName: authorName,
      authorAvatarUrl: authorAvatarUrl,
      authorType: map['author_profile_type'] as String?,
      authorOrgKind: authorOrgKind,
      authorCity: authorCity,
      authorZipcode: authorZipcode,
      authorBusinessType: authorBusinessType,
      authorBusinessName: authorBusinessName,
      authorJobTitle: authorJobTitle,
      postType: map['post_type'] as String?,
      marketCategory: map['market_category'] as String?,
      marketIntent: map['market_intent'] as String?,
      marketTitle: map['market_title'] as String?,
      marketPrice: (map['market_price'] as num?)?.toDouble(),
      marketPriceMax: (map['market_price_max'] as num?)?.toDouble(),
      distanceKm: (map['distance_km'] as num?)?.toDouble(),
    );
  }
}
