import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app/chat_singletons.dart';
import 'router.dart' show appRouterProvider;

class App extends ConsumerStatefulWidget {
  const App({super.key});

  @override
  ConsumerState<App> createState() => _AppState();
}

class _AppState extends ConsumerState<App> {
  StreamSubscription<AuthState>? _authSub;
  bool _badgeInitialized = false;

  @override
  void initState() {
    super.initState();

    // If app restarts while already logged in, init immediately
    if (Supabase.instance.client.auth.currentUser != null) {
      unreadBadgeController.init();
      _badgeInitialized = true;
    }

    // Listen for login/logout and init/dispose badge controller
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((event) async {
      final session = event.session;

      if (session != null) {
        // logged in
        if (!_badgeInitialized) {
          await unreadBadgeController.init();
          _badgeInitialized = true;
        } else {
          // already initialized: just refresh once
          await unreadBadgeController.refresh();
        }
      } else {
        // logged out
        if (_badgeInitialized) {
          unreadBadgeController.dispose();
          _badgeInitialized = false;
        }
      }
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      routerConfig: router,
    );
  }
}