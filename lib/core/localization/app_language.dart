enum AppLanguage {
  english('en'),
  french('fr');

  const AppLanguage(this.code);

  final String code;

  static AppLanguage fromCode(String? code) {
    switch ((code ?? '').toLowerCase()) {
      case 'fr':
        return AppLanguage.french;
      case 'en':
        return AppLanguage.english;
      default:
        return AppLanguage.french;
    }
  }
}
