import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app/chat_singletons.dart';
import '../core/localization/app_locale_controller.dart';
import '../core/localization/app_localizations.dart';
import '../features/notifications/providers/notification_unread_provider.dart';
import '../services/presence_service.dart';
import 'router.dart' show appRouterNavigatorKey, appRouterProvider;

class App extends ConsumerStatefulWidget {
  const App({super.key});

  @override
  ConsumerState<App> createState() => _AppState();
}

class _AppState extends ConsumerState<App> {
  StreamSubscription<AuthState>? _authSub;
  bool _badgeInitialized = false;
  bool _notificationBadgeInitialized = false;

  @override
  void initState() {
    super.initState();

    // If app restarts while already logged in, mark as initialized immediately
    // so the auth listener (which fires initialSession) doesn't also call init().
    // The actual heavy work is deferred to after the first frame.
    if (Supabase.instance.client.auth.currentUser != null) {
      _badgeInitialized = true;
      _notificationBadgeInitialized = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(appLocaleProvider.notifier).refreshFromProfile();
        unreadBadgeController.init();
        ref.read(notificationUnreadProvider.notifier).init();
        PresenceService.instance.start();
      });
    }

    // Listen for login/logout and init/dispose badge controller
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((event) async {
      final session = event.session;

      if (event.event == AuthChangeEvent.passwordRecovery) {
        final context = appRouterNavigatorKey.currentContext;
        if (context != null) {
          // ignore: use_build_context_synchronously
          context.go('/reset-password');
        }
      }

      if (session != null) {
        // logged in
        PresenceService.instance.start();
        await ref.read(appLocaleProvider.notifier).refreshFromProfile();
        if (!_badgeInitialized) {
          await unreadBadgeController.init();
          _badgeInitialized = true;
        } else {
          // already initialized: just refresh once
          await unreadBadgeController.refresh();
        }

        if (!_notificationBadgeInitialized) {
          await ref.read(notificationUnreadProvider.notifier).init();
          _notificationBadgeInitialized = true;
        } else {
          await ref.read(notificationUnreadProvider.notifier).refresh();
        }
      } else {
        // logged out
        PresenceService.instance.stop();
        ref.read(appLocaleProvider.notifier).reset();
        if (_badgeInitialized) {
          unreadBadgeController.dispose();
          _badgeInitialized = false;
        }
        if (_notificationBadgeInitialized) {
          await ref.read(notificationUnreadProvider.notifier).disposeRealtime();
          _notificationBadgeInitialized = false;
        }
      }
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    PresenceService.instance.stop();
    if (_notificationBadgeInitialized) {
      ref.read(notificationUnreadProvider.notifier).disposeRealtime();
      _notificationBadgeInitialized = false;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    final locale = ref.watch(appLocaleProvider);
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF0F766E),
      primary: const Color(0xFF0F766E),
      secondary: const Color(0xFFCC7A00),
      surface: const Color(0xFFFFFCF7),
      brightness: Brightness.light,
    );
    final baseTheme = ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: const Color(0xFFF5F1E8),
      cardTheme: CardThemeData(
        elevation: 0,
        color: const Color(0xFFFFFCF7),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        margin: EdgeInsets.zero,
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        backgroundColor: const Color(0xFFF5F1E8),
        foregroundColor: const Color(0xFF12211D),
        surfaceTintColor: Colors.transparent,
        titleTextStyle: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          color: Color(0xFF12211D),
          letterSpacing: -0.4,
        ),
      ),
      chipTheme: ChipThemeData(
        disabledColor: const Color(0xFFE7E0D2),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        labelStyle: const TextStyle(fontWeight: FontWeight.w600),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        // Use color (WidgetStateProperty) to control background per state —
        // avoids the default white hover/press overlay from Material 3.
        color: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return const Color(0xFFE7E0D2);
          }
          if (states.contains(WidgetState.selected)) {
            if (states.contains(WidgetState.pressed)) {
              return const Color(0xFF0F766E).withValues(alpha: 0.26);
            }
            if (states.contains(WidgetState.hovered)) {
              return const Color(0xFF0F766E).withValues(alpha: 0.22);
            }
            return const Color(0xFF0F766E).withValues(alpha: 0.16);
          }
          if (states.contains(WidgetState.pressed)) {
            return const Color(0xFFDDCCB5);
          }
          if (states.contains(WidgetState.hovered)) {
            return const Color(0xFFE6D8C5);
          }
          return const Color(0xFFF0E6D5);
        }),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
          // Dark overlay so hover darkens slightly instead of flashing white
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return Colors.black.withValues(alpha: 0.12);
            }
            if (states.contains(WidgetState.hovered)) {
              return Colors.black.withValues(alpha: 0.07);
            }
            if (states.contains(WidgetState.focused)) {
              return Colors.black.withValues(alpha: 0.10);
            }
            return Colors.transparent;
          }),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          side: BorderSide(color: colorScheme.outlineVariant),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          // Teal tint on hover instead of white
          overlayColor: const Color(0xFF0F766E).withValues(alpha: 0.07),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFFFFCF7),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.4),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF1F2937),
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      dividerColor: const Color(0xFFE6DDCE),
    );

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      theme: baseTheme,
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }
}
