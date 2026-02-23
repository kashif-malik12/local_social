// lib/app/router.dart
//
// ✅ Updated with Notifications + Chat routes
// ✅ Added Admin Guard for /admin/review

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app/go_router_refresh_stream.dart';

// ✅ Screens
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/register_screen.dart';
import '../features/home/presentation/home_screen.dart';
import '../features/profile/presentation/complete_profile_screen.dart';
import '../features/profile/presentation/profile_detail_screen.dart';
import '../features/profile/presentation/follow_list_screen.dart';
import '../features/profile/presentation/follow_requests_screen.dart';
import '../features/moderation/presentation/admin_review_screen.dart';

import '../screens/feed_screen.dart';
import '../screens/create_post_screen.dart';
import '../screens/comments_screen.dart';
import '../screens/post_detail_screen.dart';
import '../screens/search_screen.dart';
import '../screens/notifications_screen.dart';

// ✅ Chat screens
import '../features/chat/presentation/chat_list_screen.dart';
import '../features/chat/presentation/chat_screen.dart';
import '../features/chat/presentation/chat_start_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final auth = Supabase.instance.client.auth;

  return GoRouter(
    initialLocation: '/login',
    refreshListenable: GoRouterRefreshStream(auth.onAuthStateChange),

    redirect: (context, state) async {
      final auth = Supabase.instance.client.auth;
      final session = auth.currentSession;
      final user = auth.currentUser;

      final loggedIn = session != null && user != null;

      final loc = state.matchedLocation;
      final isAuth = loc == '/login' || loc == '/register';
      final isOnboarding = loc == '/complete-profile';
      final isProfile = loc == '/profile';
      final isAdminRoute = loc == '/admin/review';

      // ❌ Not logged in → must be on auth pages
      if (!loggedIn) {
        return isAuth ? null : '/login';
      }

      // 🔁 Logged in → block auth pages
      if (loggedIn && isAuth) return '/feed';

      // 🔐 Admin guard
      if (isAdminRoute) {
        final profile = await Supabase.instance.client
            .from('profiles')
            .select('is_admin')
            .eq('id', user!.id)
            .maybeSingle();

        final isAdmin = profile?['is_admin'] == true;

        if (!isAdmin) {
          return '/feed';
        }

        return null; // allow admin
      }

      // Allow /profile always
      if (isProfile) return null;

      // ✅ Profile completeness check
      final profile = await Supabase.instance.client
          .from('profiles')
          .select('full_name, account_type, latitude, longitude')
          .eq('id', user!.id)
          .maybeSingle();

      final fullName = profile?['full_name'] as String?;
      final accountType = profile?['account_type'] as String?;
      final lat = (profile?['latitude'] as num?)?.toDouble();
      final lng = (profile?['longitude'] as num?)?.toDouble();

      final incomplete = fullName == null ||
          fullName.trim().isEmpty ||
          accountType == null ||
          lat == null ||
          lng == null;

      if (incomplete) {
        return isOnboarding ? null : '/complete-profile';
      } else {
        return isOnboarding ? '/feed' : null;
      }
    },

    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),

      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterScreen(),
      ),

      GoRoute(
        path: '/complete-profile',
        builder: (context, state) => const CompleteProfileScreen(),
      ),

      GoRoute(
        path: '/home',
        builder: (context, state) => const HomeScreen(),
      ),

      GoRoute(
        path: '/feed',
        builder: (context, state) => const FeedScreen(),
      ),

      GoRoute(
        path: '/create-post',
        builder: (context, state) => const CreatePostScreen(),
      ),

      // 🔐 Admin Moderation Panel
      GoRoute(
        path: '/admin/review',
        builder: (context, state) => const AdminReviewScreen(),
      ),

      // ✅ Notifications
      GoRoute(
        path: '/notifications',
        builder: (context, state) => const NotificationsScreen(),
      ),

      GoRoute(
        path: '/follow-requests',
        builder: (context, state) => const FollowRequestsScreen(),
      ),

      // ✅ My profile
      GoRoute(
        path: '/profile',
        builder: (context, state) {
          final uid = Supabase.instance.client.auth.currentUser!.id;
          return ProfileDetailScreen(profileId: uid);
        },
      ),

      // ✅ Chat
      GoRoute(
        path: '/chats',
        builder: (context, state) => const ChatListScreen(),
      ),

      GoRoute(
        path: '/chat/:conversationId',
        builder: (context, state) {
          final id = state.pathParameters['conversationId']!;
          return ChatScreen(conversationId: id);
        },
      ),

      GoRoute(
        path: '/chat/user/:userId',
        builder: (context, state) {
          final userId = state.pathParameters['userId']!;
          return ChatStartScreen(otherUserId: userId);
        },
      ),

      GoRoute(
        path: '/profile/edit',
        builder: (context, state) => const CompleteProfileScreen(),
      ),

      GoRoute(
        path: '/search',
        builder: (context, state) => const SearchScreen(),
      ),

      // ✅ Visit any profile
      GoRoute(
        path: '/p/:id',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return ProfileDetailScreen(profileId: id);
        },
      ),

      GoRoute(
        path: '/p/:id/followers',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return FollowListScreen(
            profileId: id,
            mode: FollowListMode.followers,
          );
        },
      ),

      GoRoute(
        path: '/p/:id/following',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return FollowListScreen(
            profileId: id,
            mode: FollowListMode.following,
          );
        },
      ),

      GoRoute(
        path: '/post/:id',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return PostDetailScreen(postId: id);
        },
      ),

      GoRoute(
        path: '/post/:id/comments',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return CommentsScreen(postId: id);
        },
      ),
    ],
  );
});