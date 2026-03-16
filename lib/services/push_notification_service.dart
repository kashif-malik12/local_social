import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/firebase_web_config.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await PushNotificationService.initializeFirebaseIfSupported();
}

class PushNotificationService {
  PushNotificationService._();

  static final PushNotificationService instance = PushNotificationService._();
  static const AndroidNotificationChannel _androidChannel = AndroidNotificationChannel(
    'default',
    'Default notifications',
    description: 'Foreground and push notifications for Allonssy',
    importance: Importance.high,
  );

  StreamSubscription<AuthState>? _authSubscription;
  StreamSubscription<String>? _tokenRefreshSubscription;
  String? _lastAuthEventUserId;
  String? _lastSyncedUserId;
  String? _lastSyncedToken;
  Future<void>? _initFuture;
  Future<void>? _syncFuture;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  static bool get _firebaseSupportedOnThisPlatform {
    if (kIsWeb) return FirebaseWebConfig.isConfigured;
    return defaultTargetPlatform == TargetPlatform.android;
  }

  static Future<void> initializeFirebaseIfSupported() async {
    if (!_firebaseSupportedOnThisPlatform) return;
    if (Firebase.apps.isEmpty) {
      if (kIsWeb) {
        await Firebase.initializeApp(
          options: FirebaseOptions(
            apiKey: FirebaseWebConfig.apiKey,
            appId: FirebaseWebConfig.appId,
            messagingSenderId: FirebaseWebConfig.messagingSenderId,
            projectId: FirebaseWebConfig.projectId,
            authDomain: FirebaseWebConfig.authDomain,
            storageBucket: FirebaseWebConfig.storageBucket,
            measurementId: FirebaseWebConfig.measurementId.isEmpty
                ? null
                : FirebaseWebConfig.measurementId,
          ),
        );
      } else {
        await Firebase.initializeApp();
      }
    }
  }

  Future<void> init() async {
    if (_initFuture != null) {
      return _initFuture!;
    }
    _initFuture = _initInternal();
    return _initFuture!;
  }

  Future<void> _initInternal() async {
    if (!_firebaseSupportedOnThisPlatform) return;

    await initializeFirebaseIfSupported();
    if (!kIsWeb) {
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      await _initLocalNotifications();
    }

    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

    _authSubscription ??=
        Supabase.instance.client.auth.onAuthStateChange.listen((event) async {
          final user = event.session?.user;
          if (user != null) {
            if (_lastAuthEventUserId == user.id && _syncFuture != null) {
              return;
            }
            _lastAuthEventUserId = user.id;
            debugPrint('FCM auth change: user logged in, scheduling token sync');
            await syncCurrentUserTokenWithRetry();
          } else {
            debugPrint('FCM auth change: user logged out');
            _lastAuthEventUserId = null;
            _lastSyncedUserId = null;
            _lastSyncedToken = null;
          }
        });

    FirebaseMessaging.onMessage.listen((message) {
      debugPrint('FCM foreground message: ${message.messageId}');
      _showForegroundNotification(message);
    });

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      debugPrint('FCM opened app message: ${message.messageId}');
    });

    _tokenRefreshSubscription ??=
        FirebaseMessaging.instance.onTokenRefresh.listen((token) async {
      _lastSyncedToken = null;
      debugPrint('FCM token refreshed');
      await _syncToken(token);
    });

    await syncCurrentUserTokenWithRetry();
  }

  Future<void> syncCurrentUserTokenWithRetry() async {
    if (_syncFuture != null) {
      return _syncFuture!;
    }
    _syncFuture = _syncCurrentUserTokenWithRetryInternal();
    try {
      await _syncFuture;
    } finally {
      _syncFuture = null;
    }
  }

  Future<void> _syncCurrentUserTokenWithRetryInternal() async {
    for (var attempt = 1; attempt <= 4; attempt++) {
      final token = await _fetchToken();
      if (token != null && token.isNotEmpty) {
        await _syncToken(token);
        return;
      }
      debugPrint('FCM token unavailable on attempt $attempt');
      await Future<void>.delayed(Duration(seconds: attempt * 2));
    }
  }

  Future<void> syncCurrentUserToken() async {
    if (!_firebaseSupportedOnThisPlatform) return;
    final token = await _fetchToken();
    if (token == null || token.isEmpty) return;
    await _syncToken(token);
  }

  Future<String?> _fetchToken() async {
    if (!_firebaseSupportedOnThisPlatform) return null;
    try {
      final token = kIsWeb
          ? await FirebaseMessaging.instance.getToken(
              vapidKey: FirebaseWebConfig.vapidKey,
            )
          : await FirebaseMessaging.instance.getToken();
      debugPrint('FCM getToken result: ${token == null ? "null" : "received"}');
      return token;
    } catch (error) {
      debugPrint('FCM getToken failed: $error');
      return null;
    }
  }

  Future<void> _syncToken(String token) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    if (_lastSyncedUserId == user.id && _lastSyncedToken == token) {
      return;
    }

    try {
      await Supabase.instance.client.from('device_push_tokens').upsert({
        'user_id': user.id,
        'platform': kIsWeb ? 'web' : 'android',
        'token': token,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        'last_seen_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'token');

      debugPrint('FCM token synced for user ${user.id}');
      _lastSyncedUserId = user.id;
      _lastSyncedToken = token;
    } catch (error) {
      debugPrint('Failed to sync FCM token: $error');
    }
  }

  Future<void> _initLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: androidSettings);
    await _localNotifications.initialize(settings);

    await _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_androidChannel);
  }

  Future<void> _showForegroundNotification(RemoteMessage message) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;

    final notification = message.notification;
    if (notification == null) return;

    await _localNotifications.show(
      notification.hashCode,
      notification.title ?? 'Allonssy',
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _androidChannel.id,
          _androidChannel.name,
          channelDescription: _androidChannel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
      ),
    );
  }

  Future<void> dispose() async {
    await _authSubscription?.cancel();
    _authSubscription = null;
    await _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = null;
    _lastAuthEventUserId = null;
    _initFuture = null;
    _syncFuture = null;
  }
}
