import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app/chat_singletons.dart';
import '../core/localization/app_localizations.dart';
import '../features/moderation/providers/admin_access_provider.dart';
import '../features/notifications/providers/notification_unread_provider.dart';
import 'brand_wordmark.dart';

class GlobalAppBar extends ConsumerWidget implements PreferredSizeWidget {
  final String title;
  final Widget? notifBell;
  final bool showBackIfPossible;
  final String homeRoute;
  final Future<void> Function()? onBeforeLogout;
  final List<Widget>? actions;
  final String searchRoute;
  final String chatsRoute;
  final String myProfileRoute;
  final String notificationsRoute;
  final bool showDefaultActions;

  const GlobalAppBar({
    super.key,
    required this.title,
    this.notifBell,
    this.showBackIfPossible = false,
    this.homeRoute = '/feed',
    this.onBeforeLogout,
    this.actions,
    this.searchRoute = '/search',
    this.chatsRoute = '/chats',
    this.myProfileRoute = '/profile',
    this.notificationsRoute = '/notifications',
    this.showDefaultActions = true,
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
        SnackBar(
          content: Text(
            context.l10n.tr('logout_failed', args: {'error': '$e'}),
          ),
        ),
      );
    }
  }

  PopupMenuButton<String> _buildMoreMenu(
    BuildContext context,
    ThemeData theme,
    bool isAdmin,
  ) {
    final l10n = context.l10n;
    return PopupMenuButton<String>(
      tooltip: l10n.tr('more'),
      onSelected: (value) {
        if (value == 'profile') {
          context.push(myProfileRoute);
        } else if (value == 'admin') {
          context.push('/adminlive');
        } else if (value == 'about') {
          context.push('/about');
        } else if (value == 'terms') {
          context.push('/terms');
        } else if (value == 'privacy') {
          context.push('/privacy');
        } else if (value == 'logout') {
          _logout(context);
        } else if (value == 'home') {
          context.go(homeRoute);
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem<String>(
          value: 'home',
          child: Text(l10n.tr('home')),
        ),
        PopupMenuItem<String>(
          value: 'profile',
          child: Text(l10n.tr('my_profile')),
        ),
        if (isAdmin)
          PopupMenuItem<String>(
            value: 'admin',
            child: Text(l10n.tr('admin_portal')),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'about',
          child: Text('About Us'),
        ),
        const PopupMenuItem<String>(
          value: 'terms',
          child: Text('Terms & Conditions'),
        ),
        const PopupMenuItem<String>(
          value: 'privacy',
          child: Text('Privacy Policy'),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'logout',
          child: Text(l10n.tr('logout')),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.only(right: 6),
        child: Material(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: const Padding(
            padding: EdgeInsets.all(10),
            child: Icon(Icons.more_horiz_rounded),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final canPop = GoRouter.of(context).canPop();
    final showBack = showBackIfPossible && canPop;
    final theme = Theme.of(context);
    final showNavActions = showDefaultActions && MediaQuery.of(context).size.width >= 1100;
    final isAdmin = ref.watch(adminAccessProvider).valueOrNull == true;

    return AppBar(
      scrolledUnderElevation: 0,
      leading: showBack
          ? IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.pop(),
            )
          : null,
      title: InkWell(
        onTap: () => context.go(homeRoute),
        child: title == 'Allonssy!'
            ? const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  BrandMark(size: 26),
                  SizedBox(width: 8),
                  BrandWordmark(
                    fontSize: 22,
                    color: Color(0xFF12211D),
                    accentColor: Color(0xFF0F766E),
                    letterSpacing: -0.6,
                    showIcon: false,
                  ),
                ],
              )
            : Text(title),
      ),
      actions: [
        ...?actions,
        if (showNavActions) ...[
          _actionIcon(
            context: context,
            tooltip: l10n.tr('home'),
            icon: const Icon(Icons.home_outlined),
            onPressed: () => context.go(homeRoute),
          ),
          _actionIcon(
            context: context,
            tooltip: l10n.tr('search'),
            icon: const Icon(Icons.search),
            onPressed: () => context.push(searchRoute),
          ),
          ValueListenableBuilder<int>(
            valueListenable: unreadBadgeController.unread,
            builder: (_, unread, _) {
              return _actionIcon(
                context: context,
                tooltip: l10n.tr('messages'),
                onPressed: () {
                  unreadBadgeController.refresh();
                  context.push(chatsRoute);
                },
                icon: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(Icons.chat_bubble_outline),
                    if (unread > 0)
                      Positioned(
                        right: -7,
                        top: -6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          constraints: const BoxConstraints(minWidth: 18),
                          decoration: BoxDecoration(
                            color: const Color(0xFFD92D20),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: theme.colorScheme.surface,
                              width: 1.4,
                            ),
                          ),
                          child: Text(
                            unread > 99 ? '99+' : '$unread',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              height: 1,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
          if (notifBell != null)
            notifBell!
          else
            Consumer(
              builder: (context, ref, _) {
                final unread = ref.watch(notificationUnreadProvider);
                return _actionIcon(
                  context: context,
                  tooltip: l10n.tr('notifications'),
                  onPressed: () {
                    ref.read(notificationUnreadProvider.notifier).refresh();
                    context.push(notificationsRoute);
                  },
                  icon: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      const Icon(Icons.notifications_outlined),
                      if (unread > 0)
                        Positioned(
                          right: -7,
                          top: -6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                            constraints: const BoxConstraints(minWidth: 18),
                            decoration: BoxDecoration(
                              color: const Color(0xFFD92D20),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: theme.colorScheme.surface,
                                width: 1.4,
                              ),
                            ),
                            child: Text(
                              unread > 99 ? '99+' : '$unread',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                height: 1,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          _buildMoreMenu(context, theme, isAdmin),
        ],
      ],
    );
  }

  Widget _actionIcon({
    required BuildContext context,
    required String tooltip,
    required Widget icon,
    required VoidCallback onPressed,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: IconButton(
          tooltip: tooltip,
          visualDensity: VisualDensity.compact,
          onPressed: onPressed,
          icon: icon,
        ),
      ),
    );
  }
}
