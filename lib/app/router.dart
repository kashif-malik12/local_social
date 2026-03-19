// lib/app/router.dart
//
// ✅ Updated with Notifications + Chat routes
// ✅ Added Admin Guard for /adminlive

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app/go_router_refresh_stream.dart';

// ✅ Screens
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/register_screen.dart';
import '../features/auth/presentation/forgot_password_screen.dart';
import '../features/auth/presentation/reset_password_screen.dart';
import '../features/home/presentation/home_screen.dart';
import '../features/profile/presentation/complete_profile_screen.dart';
import '../features/profile/presentation/feed_filter_setup_screen.dart';
import '../features/profile/presentation/profile_detail_screen.dart';
import '../features/profile/presentation/follow_list_screen.dart';
import '../features/profile/presentation/follow_requests_screen.dart';
import '../features/profile/presentation/managed_ads_screen.dart';
import '../features/profile/presentation/profile_settings_screen.dart';
import '../features/moderation/presentation/admin_review_screen.dart';

import '../screens/feed_screen.dart';
import '../screens/legal_screen.dart';
import '../screens/child_safety_screen.dart';
import '../screens/delete_account_screen.dart';
import '../screens/create_post_screen.dart';
import '../screens/quick_camera_post_screen.dart';
import '../screens/comments_screen.dart';
import '../screens/post_detail_screen.dart';
import '../screens/search_screen.dart';
import '../screens/notifications_screen.dart';
import '../screens/marketplace_screen.dart';
import '../screens/marketplace_product_detail_screen.dart';
import '../screens/gigs_screen.dart';
import '../screens/gig_detail_screen.dart';
import '../screens/food_ad_detail_screen.dart';
import '../screens/foods_screen.dart';
import '../screens/restaurants_screen.dart';
import '../screens/businesses_screen.dart';
import '../widgets/main_shell.dart';

// ✅ Chat screens
import '../features/chat/presentation/chat_list_screen.dart';
import '../features/chat/presentation/chat_screen.dart';
import '../features/chat/presentation/chat_start_screen.dart';
import '../features/chat/presentation/offer_chat_screen.dart';
import '../features/chat/presentation/offer_chat_start_screen.dart';

final appRouterNavigatorKey = GlobalKey<NavigatorState>();
final appRouteObserver = RouteObserver<ModalRoute<void>>();

// Branch navigator keys for the persistent tab shell
final _feedNavKey = GlobalKey<NavigatorState>(debugLabel: 'feed');
final _searchNavKey = GlobalKey<NavigatorState>(debugLabel: 'search');
final _chatNavKey = GlobalKey<NavigatorState>(debugLabel: 'chat');
final _notifNavKey = GlobalKey<NavigatorState>(debugLabel: 'notif');

final appRouterProvider = Provider<GoRouter>((ref) {
  final auth = Supabase.instance.client.auth;

  return GoRouter(
    navigatorKey: appRouterNavigatorKey,
    observers: [appRouteObserver],
    initialLocation: '/login',
    refreshListenable: GoRouterRefreshStream(auth.onAuthStateChange),

    redirect: (context, state) async {
      final auth = Supabase.instance.client.auth;
      final session = auth.currentSession;
      final user = auth.currentUser;

      final loggedIn = session != null && user != null;

      final path = state.uri.path;
      final isPublicPage =
          path == '/about' ||
          path == '/terms' ||
          path == '/privacy' ||
          path == '/delete-account' ||
          path == '/child-safety';

      final isAuth =
          path == '/login' || path == '/register' || path == '/forgot-password';
      final isOnboarding = path == '/complete-profile';
      final isFeedSetup = path == '/feed-setup';
      final isProfile = path == '/profile';
      final isResetPassword = path == '/reset-password';
      final isAdminRoute =
          path.startsWith('/adminlive') || path.startsWith('/admin/review');

      // ❌ Not logged in → must be on auth pages or public pages
      if (!loggedIn) {
        return (isAuth || isResetPassword || isPublicPage) ? null : '/login';
      }

      // 🔐 Admin routes — require is_admin = true in DB
      if (isAdminRoute) {
        try {
          final row = await Supabase.instance.client
              .from('profiles')
              .select('is_admin')
              .eq('id', user.id)
              .maybeSingle()
              .timeout(const Duration(seconds: 5));
          if (row?['is_admin'] != true) return '/feed';
        } catch (_) {
          return '/feed';
        }
        return null;
      }

      // Allow /profile always
      if (isProfile || isResetPassword) return null;

      // ✅ Profile completeness check (5 s timeout so a slow network never
      // freezes navigation indefinitely; on timeout we proceed to /feed).
      Map<String, dynamic>? profile;
      bool profileFetchFailed = false;
      try {
        profile = await Supabase.instance.client
            .from('profiles')
            .select('full_name, account_type, latitude, longitude, is_disabled, feed_filters')
            .eq('id', user.id)
            .maybeSingle()
            .timeout(const Duration(seconds: 5));
      } on PostgrestException {
        try {
          profile = await Supabase.instance.client
              .from('profiles')
              .select('full_name, account_type, latitude, longitude, feed_filters')
              .eq('id', user.id)
              .maybeSingle()
              .timeout(const Duration(seconds: 5));
        } catch (_) {
          profileFetchFailed = true;
        }
      } catch (_) {
        // Network timeout or other error — don't block navigation.
        profileFetchFailed = true;
      }

      // Fetch failed (timeout/network) → go to feed and re-check later.
      if (profileFetchFailed && !isOnboarding && !isFeedSetup) {
        return path == '/feed' ? null : '/feed';
      }

      // profile == null means no row exists (new Google/OAuth user) → must complete profile.
      if (profile == null && !isOnboarding && !isFeedSetup) {
        return '/complete-profile';
      }

      if (profile?['is_disabled'] == true) {
        await auth.signOut();
        return '/login?error=disabled';
      }

      final fullName = profile?['full_name'] as String?;
      final accountType = profile?['account_type'] as String?;
      final lat = (profile?['latitude'] as num?)?.toDouble();
      final lng = (profile?['longitude'] as num?)?.toDouble();

      final incomplete = fullName == null ||
          fullName.trim().isEmpty ||
          accountType == null ||
          lat == null ||
          lng == null;

      final hasFeedFilters = (profile?['feed_filters'] is Map) ||
          (user.userMetadata?['feed_filters'] is Map);

      if (incomplete) {
        return isOnboarding ? null : '/complete-profile';
      } else {
        if (!hasFeedFilters) {
          return isFeedSetup ? null : '/feed-setup';
        }
        if (isOnboarding || isFeedSetup) return '/feed';
        // Logged in with complete profile but still on an auth page → go to feed
        if (isAuth) return '/feed';
        return null;
      }
    },

    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => LoginScreen(
          errorCode: state.uri.queryParameters['error'],
        ),
      ),

      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterScreen(),
      ),

      GoRoute(
        path: '/forgot-password',
        builder: (context, state) => const ForgotPasswordScreen(),
      ),

      GoRoute(
        path: '/reset-password',
        builder: (context, state) => const ResetPasswordScreen(),
      ),

      GoRoute(
        path: '/complete-profile',
        builder: (context, state) => const CompleteProfileScreen(),
      ),

      GoRoute(
        path: '/feed-setup',
        builder: (context, state) => const FeedFilterSetupScreen(),
      ),

      GoRoute(
        path: '/home',
        builder: (context, state) => const HomeScreen(),
      ),

      // ── Legal / public pages (no auth required) ──────────────────────────
      GoRoute(
        path: '/about',
        builder: (context, state) => const LegalScreen(page: LegalPage.about),
      ),
      GoRoute(
        path: '/terms',
        builder: (context, state) => const LegalScreen(page: LegalPage.terms),
      ),
      GoRoute(
        path: '/privacy',
        builder: (context, state) => const LegalScreen(page: LegalPage.privacy),
      ),
      GoRoute(
        path: '/delete-account',
        builder: (context, state) => const DeleteAccountScreen(),
      ),
      GoRoute(
        path: '/child-safety',
        builder: (context, state) => const ChildSafetyScreen(),
      ),

      // ── Persistent tab shell ─────────────────────────────────────────────
      // Feed, Search, Chat, Notifications are kept alive in an IndexedStack.
      // Switching between them is instant and state is preserved.
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            MainShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            navigatorKey: _feedNavKey,
            routes: [
              GoRoute(
                path: '/feed',
                builder: (context, state) => const FeedScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _searchNavKey,
            routes: [
              GoRoute(
                path: '/search',
                builder: (context, state) => const SearchScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _chatNavKey,
            routes: [
              GoRoute(
                path: '/chats',
                builder: (context, state) => const ChatListScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _notifNavKey,
            routes: [
              GoRoute(
                path: '/notifications',
                builder: (context, state) => const NotificationsScreen(),
              ),
            ],
          ),
        ],
      ),
      // ─────────────────────────────────────────────────────────────────────

      GoRoute(
        path: '/marketplace',
        builder: (context, state) => const MarketplaceScreen(),
      ),

      GoRoute(
        path: '/marketplace/product/:id',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          final initialTab = state.uri.queryParameters['tab'] == 'qa' ? 1 : 0;
          return MarketplaceProductDetailScreen(postId: id, initialTab: initialTab);
        },
      ),


      GoRoute(
        path: '/gigs',
        builder: (context, state) => const GigsScreen(),
      ),

      GoRoute(
        path: '/gigs/service/:id',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          final initialTab = state.uri.queryParameters['tab'] == 'qa' ? 1 : 0;
          return GigDetailScreen(postId: id, initialTab: initialTab);
        },
      ),

      GoRoute(
        path: '/restaurants',
        builder: (context, state) => const RestaurantsScreen(),
      ),

      GoRoute(
        path: '/businesses',
        builder: (context, state) => const BusinessesScreen(),
      ),

      GoRoute(
        path: '/foods',
        builder: (context, state) => const FoodsScreen(),
      ),

      GoRoute(
        path: '/foods/:id',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          final initialTab = state.uri.queryParameters['tab'] == 'qa' ? 1 : 0;
          return FoodAdDetailScreen(postId: id, initialTab: initialTab);
        },
      ),

      GoRoute(
        path: '/create-post',
        builder: (context, state) => const CreatePostScreen(),
      ),

      GoRoute(
        path: '/quick-camera-post/:mode',
        builder: (context, state) {
          final mode = state.pathParameters['mode'] == 'video'
              ? QuickCaptureMode.video
              : QuickCaptureMode.photo;
          return QuickCameraPostScreen(mode: mode);
        },
      ),

      // 🔐 Admin Moderation Panel
      GoRoute(
        path: '/adminlive',
        builder: (context, state) => const AdminLiveScreen(),
      ),

      GoRoute(
        path: '/admin/review',
        builder: (context, state) => const AdminLiveScreen(),
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

      // ✅ Chat sub-screens (chat list is inside the shell branch above)
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
        path: '/offer-chat/:conversationId',
        builder: (context, state) {
          final id = state.pathParameters['conversationId']!;
          return OfferChatScreen(conversationId: id);
        },
      ),

      GoRoute(
        path: '/offer-chat/post/:postId/user/:userId',
        builder: (context, state) {
          final postId = state.pathParameters['postId']!;
          final userId = state.pathParameters['userId']!;
          return OfferChatStartScreen(
            postId: postId,
            otherUserId: userId,
          );
        },
      ),

      GoRoute(
        path: '/profile/edit',
        builder: (context, state) => const CompleteProfileScreen(),
      ),

      GoRoute(
        path: '/profile/settings',
        builder: (context, state) => const ProfileSettingsScreen(),
      ),

      GoRoute(
        path: '/profile/my-products',
        builder: (context, state) => const ManagedAdsScreen(mode: ManagedAdsMode.products),
      ),

      GoRoute(
        path: '/profile/my-gigs',
        builder: (context, state) => const ManagedAdsScreen(mode: ManagedAdsMode.gigs),
      ),

      GoRoute(
        path: '/profile/my-foods',
        builder: (context, state) => const ManagedAdsScreen(mode: ManagedAdsMode.foods),
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
        path: '/p/:id/connections',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return FollowListScreen(
            profileId: id,
            mode: FollowListMode.connections,
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
