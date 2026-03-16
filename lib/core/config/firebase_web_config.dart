class FirebaseWebConfig {
  static const apiKey = String.fromEnvironment('FIREBASE_WEB_API_KEY');
  static const appId = String.fromEnvironment('FIREBASE_APP_ID', defaultValue: '1:460437609061:web:8b0b6e5c136fab52d8c48c');
  static const messagingSenderId = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID', defaultValue: '460437609061');
  static const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID', defaultValue: 'allonssy');
  static const authDomain = String.fromEnvironment('FIREBASE_AUTH_DOMAIN', defaultValue: 'allonssy.firebaseapp.com');
  static const storageBucket = String.fromEnvironment('FIREBASE_STORAGE_BUCKET', defaultValue: 'allonssy.firebasestorage.app');
  static const measurementId = '';
  static const vapidKey = String.fromEnvironment('FIREBASE_VAPID_KEY', defaultValue: 'BDRzNky38hzb9oSPWtvbcZhxYX38kdUPGpwAjZ4IdL4gswTWaG0JO5Sjw-oceCmOj_x0ZMgETyg7mRtpClaHIrY');

  static bool get isConfigured =>
      apiKey.isNotEmpty &&
      appId.isNotEmpty &&
      messagingSenderId.isNotEmpty &&
      projectId.isNotEmpty &&
      vapidKey.isNotEmpty;
}
