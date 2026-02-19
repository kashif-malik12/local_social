import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/register_screen.dart';
import '../features/home/presentation/home_screen.dart';
import '../features/profile/presentation/complete_profile_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/login',
  redirect: (context, state) async {
  final session = Supabase.instance.client.auth.currentSession;
  final loggedIn = session != null;

  final isAuth = state.matchedLocation == '/login' ||
      state.matchedLocation == '/register';

  final isOnboarding = state.matchedLocation == '/complete-profile';

  if (!loggedIn && !isAuth) return '/login';
  if (loggedIn && isAuth) return '/home';

  if (loggedIn) {
    final user = Supabase.instance.client.auth.currentUser!;
    final profile = await Supabase.instance.client
        .from('profiles')
        .select('full_name, account_type')
        .eq('id', user.id)
        .maybeSingle();

    final fullName = profile?['full_name'] as String?;
    final accountType = profile?['account_type'] as String?;

    final incomplete =
        fullName == null || fullName.trim().isEmpty || accountType == null;

    if (incomplete && !isOnboarding) return '/complete-profile';
    if (!incomplete && isOnboarding) return '/home';
  }

  return null;
},


    routes: [
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(path: '/register', builder: (context, state) => const RegisterScreen()),
      GoRoute(path: '/complete-profile', builder: (context, state) => const CompleteProfileScreen()),
      GoRoute(path: '/home', builder: (context, state) => const HomeScreen()),
    ],
  );
});