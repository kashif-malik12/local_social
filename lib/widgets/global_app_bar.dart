import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class GlobalAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;

  // existing features
  final Widget? notifBell;
  final bool showBackIfPossible;
  final String homeRoute;
  final Future<void> Function()? onBeforeLogout;

  // ✅ optional extra actions (e.g., Report user)
  final List<Widget>? actions;

  // ✅ routes for icons (override if needed)
  final String searchRoute;
  final String chatsRoute;
  final String myProfileRoute;

  const GlobalAppBar({
    super.key,
    required this.title,
    this.notifBell,
    this.showBackIfPossible = false,
    this.homeRoute = '/feed',
    this.onBeforeLogout,
    this.actions,

    // defaults — change if your app uses different ones
    this.searchRoute = '/search',
    this.chatsRoute = '/chats',
    this.myProfileRoute = '/profile',
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  Future<void> _logout(BuildContext context) async {
    try {
      if (onBeforeLogout != null) {
        await onBeforeLogout!();
      }
      await Supabase.instance.client.auth.signOut();
      if (context.mounted) context.go('/login');
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Logout failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final canPop = GoRouter.of(context).canPop();
    final showBack = showBackIfPossible && canPop;

    return AppBar(
      leading: showBack
          ? IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.pop(),
            )
          : null,
      title: InkWell(
        onTap: () => context.go(homeRoute),
        child: Text(title),
      ),
      actions: [
        // ✅ extra actions first (like report user ⋮)
        ...?actions,

        // 🔎 Search
        IconButton(
          tooltip: 'Search',
          icon: const Icon(Icons.search),
          onPressed: () => context.push(searchRoute),
        ),

        // 💬 Messages / Chats
        IconButton(
          tooltip: 'Messages',
          icon: const Icon(Icons.chat_bubble_outline),
          onPressed: () => context.push(chatsRoute),
        ),

        // 👤 My profile
        IconButton(
          tooltip: 'My profile',
          icon: const Icon(Icons.person_outline),
          onPressed: () => context.push(myProfileRoute),
        ),

        // 🔔 Notifications bell (optional custom widget with badge)
        if (notifBell != null) notifBell!,

        // 🚪 Logout
        IconButton(
          tooltip: 'Logout',
          icon: const Icon(Icons.logout),
          onPressed: () => _logout(context),
        ),
      ],
    );
  }
}