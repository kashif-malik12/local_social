class PortfolioItem {
  final String id;
  final String profileId;
  final String imageUrl;
  final DateTime createdAt;

  PortfolioItem({
    required this.id,
    required this.profileId,
    required this.imageUrl,
    required this.createdAt,
  });

  factory PortfolioItem.fromMap(Map<String, dynamic> map) {
    return PortfolioItem(
      id: map['id'] as String,
      profileId: map['profile_id'] as String,
      imageUrl: map['image_url'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}