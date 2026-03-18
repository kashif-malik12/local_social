import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app/chat_singletons.dart';
import '../core/localization/app_localizations.dart';
import '../features/moderation/providers/admin_access_provider.dart';
import '../features/notifications/providers/notification_unread_provider.dart';

class GlobalBottomNav extends ConsumerWidget {
  final VoidCallback? onOpenFilters;
  final Future<void> Function()? onBeforeLogout;

  const GlobalBottomNav({
    super.key,
    this.onOpenFilters,
    this.onBeforeLogout,
  });

  bool _isMobile(BuildContext context) => MediaQuery.of(context).size.width < 1100;

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

  Widget _navItem({
    required BuildContext context,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    int badgeCount = 0,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(icon),
                  if (badgeCount > 0)
                    Positioned(
                      right: -10,
                      top: -8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        constraints: const BoxConstraints(minWidth: 18),
                        decoration: BoxDecoration(
                          color: const Color(0xFFD92D20),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          badgeCount > 99 ? '99+' : '$badgeCount',
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
              const SizedBox(height: 4),
              Text(
                label,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _quickLinkButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }

  Future<void> _openOptions(BuildContext context) async {
    final l10n = context.l10n;
    final currentPath = GoRouterState.of(context).uri.path;
    final isAdmin = await ProviderScope.containerOf(context).read(adminAccessProvider.future);

    if (!context.mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        final maxHeight = MediaQuery.of(sheetContext).size.height * 0.82;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.tr('options'),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.tonalIcon(
                        onPressed: () {
                          Navigator.of(sheetContext).pop();
                          if (onOpenFilters != null && currentPath == '/feed') {
                            onOpenFilters!();
                          } else {
                            context.go('/feed');
                          }
                        },
                        icon: const Icon(Icons.tune_rounded),
                        label: Text(l10n.tr('filters')),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _quickLinkButton(
                          icon: Icons.storefront_outlined,
                          label: l10n.tr('marketplace'),
                          onPressed: () {
                            Navigator.of(sheetContext).pop();
                            context.push('/marketplace');
                          },
                        ),
                        _quickLinkButton(
                          icon: Icons.miscellaneous_services_outlined,
                          label: l10n.tr('gigs'),
                          onPressed: () {
                            Navigator.of(sheetContext).pop();
                            context.push('/gigs');
                          },
                        ),
                        _quickLinkButton(
                          icon: Icons.fastfood,
                          label: l10n.tr('foods'),
                          onPressed: () {
                            Navigator.of(sheetContext).pop();
                            context.push('/foods');
                          },
                        ),
                        _quickLinkButton(
                          icon: Icons.business,
                          label: l10n.tr('businesses'),
                          onPressed: () {
                            Navigator.of(sheetContext).pop();
                            context.push('/businesses');
                          },
                        ),
                        _quickLinkButton(
                          icon: Icons.restaurant_menu,
                          label: l10n.tr('restaurants'),
                          onPressed: () {
                            Navigator.of(sheetContext).pop();
                            context.push('/restaurants');
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.person_outline),
                      title: Text(l10n.tr('my_profile')),
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        context.push('/profile');
                      },
                    ),
                    if (isAdmin)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.admin_panel_settings_outlined),
                        title: Text(l10n.tr('admin_portal')),
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          context.push('/adminlive');
                        },
                      ),
                    const Divider(height: 24),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.info_outline),
                      title: const Text('About Us'),
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        context.push('/about');
                      },
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.description_outlined),
                      title: const Text('Terms & Conditions'),
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        context.push('/terms');
                      },
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.shield_outlined),
                      title: const Text('Privacy Policy'),
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        context.push('/privacy');
                      },
                    ),
                    const Divider(height: 24),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.logout),
                      title: Text(l10n.tr('logout')),
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        _logout(context);
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    if (!_isMobile(context)) {
      return const SizedBox.shrink();
    }

    final surface = Theme.of(context).colorScheme.surface;
    final unreadNotifications = ref.watch(notificationUnreadProvider);
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: surface,
          border: Border(top: BorderSide(color: Colors.black.withValues(alpha: 0.08))),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            _navItem(
              context: context,
              icon: Icons.home_outlined,
              label: l10n.tr('home'),
              onTap: () => context.go('/feed'),
            ),
            _navItem(
              context: context,
              icon: Icons.search,
              label: l10n.tr('search'),
              onTap: () => context.go('/search'),
            ),
            ValueListenableBuilder<int>(
              valueListenable: unreadBadgeController.unread,
              builder: (_, unread, _) {
                return _navItem(
                  context: context,
                  icon: Icons.chat_bubble_outline,
                  label: l10n.tr('chat'),
                  badgeCount: unread,
                  onTap: () {
                    unreadBadgeController.refresh();
                    context.go('/chats');
                  },
                );
              },
            ),
            _navItem(
              context: context,
              icon: Icons.notifications_outlined,
              label: l10n.tr('alerts'),
              badgeCount: unreadNotifications,
              onTap: () {
                ref.read(notificationUnreadProvider.notifier).refresh();
                context.go('/notifications');
              },
            ),
            _navItem(
              context: context,
              icon: Icons.menu_rounded,
              label: l10n.tr('options'),
              onTap: () => _openOptions(context),
            ),
          ],
        ),
      ),
    );
  }
}
