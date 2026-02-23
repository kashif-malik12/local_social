import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/chat_singletons.dart';

class GlobalAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;

  /// Pass your custom bell widget (with badge) from any screen that has it.
  final Widget? notifBell;

  /// If true, shows back button when the route can pop.
  final bool showBackIfPossible;

  /// Override where the title click goes.
  final String homeRoute;

  /// Optional hook to run before logout (e.g., remove realtime channels).
  final Future<void> Function()? onBeforeLogout;

  const GlobalAppBar({
    super.key,
    required this.title,
    this.notifBell,
    this.showBackIfPossible = true,
    this.homeRoute = '/feed',
    this.onBeforeLogout,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      automaticallyImplyLeading: false,
      leading: (showBackIfPossible && context.canPop())
          ? IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.pop(),
            )
          : null,

      // ✅ Clickable app title -> go to home
      title: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => context.go(homeRoute),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title),
              const SizedBox(width: 6),
              const Icon(Icons.home, size: 18),
            ],
          ),
        ),
      ),

      actions: [
        if (notifBell != null) notifBell!,

        // ✅ Chat icon + unread badge
        ValueListenableBuilder<int>(
          valueListenable: unreadBadgeController.unread,
          builder: (context, count, _) {
            return IconButton(
              tooltip: 'Messages',
              onPressed: () => context.push('/chats'),
              icon: Stack(
                clipBehavior: Clip.none,
                children: [
                  const Icon(Icons.chat_bubble_outline),
                  if (count > 0)
                    Positioned(
                      right: -2,
                      top: -2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          count > 99 ? '99+' : '$count',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),

        IconButton(
          tooltip: 'My profile',
          icon: const Icon(Icons.person),
          onPressed: () => context.go('/profile'),
        ),

        IconButton(
          tooltip: 'Search',
          icon: const Icon(Icons.search),
          onPressed: () => context.push('/search'),
        ),

        IconButton(
          tooltip: 'Logout',
          icon: const Icon(Icons.logout),
          onPressed: () async {
            // optional cleanup hook
            if (onBeforeLogout != null) {
              await onBeforeLogout!();
            }

            // Optional: clear badge controller on logout
            unreadBadgeController.dispose();

            await Supabase.instance.client.auth.signOut();
            if (!context.mounted) return;
            context.go('/login');
          },
        ),
      ],
    );
  }
}