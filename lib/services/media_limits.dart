class MediaLimits {
  static const int maxPhotoBytes = 20 * 1024 * 1024; // 20 MB
  static const int maxVideoBytes = 150 * 1024 * 1024; // 150 MB

  // Lower quality a bit to keep uploads lighter while staying acceptable visually.
  static const int postImageQuality = 78;
  static const int avatarImageQuality = 72;
}
