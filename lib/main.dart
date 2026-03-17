import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app.dart';
import 'core/auth/release_auth_storage.dart';
import 'core/config/env.dart';
import 'core/localization/app_localizations.dart';
import 'services/push_notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    if (kIsWeb) {
      usePathUrlStrategy();
    }

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    }

    final authStorage = createReleaseAuthStorage(
      'sb-${Uri.parse(Env.supabaseUrl).host.split(".").first}-auth-token',
    );

    await Supabase.initialize(
      url: Env.supabaseUrl,
      anonKey: Env.supabaseAnonKey,
      authOptions: FlutterAuthClientOptions(
        localStorage: authStorage,
        pkceAsyncStorage: createReleasePkceStorage(),
      ),
      // Enforce a 10 s request timeout so a slow / unreachable VPS never
      // causes an ANR by blocking Supabase.initialize() indefinitely.
      httpClient: _TimeoutHttpClient(),
    );

    runApp(const ProviderScope(child: App()));
    // Defer Firebase / FCM init to after the first frame so the app
    // paints immediately instead of blocking on SDK initialization.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(PushNotificationService.instance.init());
    });
  } catch (error, stackTrace) {
    runApp(_StartupErrorApp(error: error, stackTrace: stackTrace));
  }
}

/// HTTP client that enforces a 10-second timeout on every request.
/// Prevents Supabase.initialize() from hanging indefinitely when the VPS
/// is slow to complete a TLS handshake (common on Android emulator).
class _TimeoutHttpClient extends http.BaseClient {
  final http.Client _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _inner.send(request).timeout(const Duration(seconds: 10));
}

class _StartupErrorApp extends StatelessWidget {
  const _StartupErrorApp({
    required this.error,
    required this.stackTrace,
  });

  final Object error;
  final StackTrace stackTrace;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(
        backgroundColor: const Color(0xFFF5F1E8),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: SingleChildScrollView(
              child: DefaultTextStyle(
                style: const TextStyle(color: Color(0xFF12211D)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Startup failed',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(error.toString()),
                    const SizedBox(height: 16),
                    Text(
                      stackTrace.toString(),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
