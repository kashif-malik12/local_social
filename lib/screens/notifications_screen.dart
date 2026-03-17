// lib/screens/notifications_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/localization/app_localizations.dart';
import '../features/notifications/providers/notification_unread_provider.dart';
import '../models/notification_model.dart';
import '../services/notification_service.dart';
import '../services/follow_service.dart';
import '../widgets/global_app_bar.dart';
import '../widgets/global_bottom_nav.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  final _db = Supabase.instance.client;
  late final NotificationService _svc;
  late final FollowService _followSvc;

  final _scrollCtrl = ScrollController();

  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;

  List<AppNotification> _items = [];

  static const int _pageSize = 25;
  int _offset = 0;

  RealtimeChannel? _channel;
  Timer? _debounce;

  // ✅ Prevent double taps on Accept/Decline
  final Set<String> _actingIds = {};

  @override
  void initState() {
    super.initState();
    _svc = NotificationService(_db);
    _followSvc = FollowService(_db);

    _scrollCtrl.addListener(_onScroll);
    _refreshFirstPage();

    _channel = _svc.subscribeToMyNotifications(() {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 350), () async {
        await _refreshFirstPage(silent: true);
      });
    });
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    _debounce?.cancel();
    final ch = _channel;
    _channel = null;
    if (ch != null) _svc.unsubscribe(ch);
    super.dispose();
  }

  void _onScroll() {
    if (!_hasMore || _loadingMore || _loading) return;
    if (_scrollCtrl.position.pixels >= _scrollCtrl.position.maxScrollExtent - 250) {
      _loadMore();
    }
  }

  Future<void> _refreshFirstPage({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else {
      if (mounted) setState(() => _error = null);
    }

    try {
      _offset = 0;
      final rows = await _svc.fetchPage(from: 0, to: _pageSize - 1);
      final page = rows.map(AppNotification.fromMap).toList();

      if (!mounted) return;
      setState(() {
        _items = page;
        _hasMore = page.length == _pageSize;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    setState(() => _loadingMore = true);

    try {
      final nextFrom = _offset + _pageSize;
      final nextTo = nextFrom + _pageSize - 1;

      final rows = await _svc.fetchPage(from: nextFrom, to: nextTo);
      final page = rows.map(AppNotification.fromMap).toList();

      if (!mounted) return;
      setState(() {
        _offset = nextFrom;
        _items.addAll(page);
        _hasMore = page.length == _pageSize;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.tr('load_more_failed', args: {'error': '$e'})),
        ),
      );
    }
  }

  Future<void> _markAllRead() async {
    try {
      await _svc.markAllRead();
      ref.read(notificationUnreadProvider.notifier).clear();
      final now = DateTime.now();
      setState(() {
        _items = _items
            .map((n) => n.readAt == null
                ? AppNotification(
                    id: n.id,
                    recipientId: n.recipientId,
                    type: n.type,
                    createdAt: n.createdAt,
                    actorId: n.actorId,
                    postId: n.postId,
                    commentId: n.commentId,
                    postType: n.postType,
                    postOwnerId: n.postOwnerId,
                    readAt: now,
                    actorName: n.actorName,
                    actorAvatarUrl: n.actorAvatarUrl,
                  )
                : n)
            .toList();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.tr('failed_generic', args: {'error': '$e'})),
        ),
      );
    }
  }

  Future<void> _onTap(AppNotification n) async {
    // mark read (best-effort)
    if (n.readAt == null) {
      try {
        await _svc.markRead(n.id);
        ref.read(notificationUnreadProvider.notifier).decrement();
        if (mounted) {
          setState(() {
            _items = _items.map((x) {
              if (x.id != n.id) return x;
              return AppNotification(
                id: x.id,
                recipientId: x.recipientId,
                type: x.type,
                createdAt: x.createdAt,
                actorId: x.actorId,
                postId: x.postId,
                commentId: x.commentId,
                postType: x.postType,
                postOwnerId: x.postOwnerId,
                readAt: DateTime.now(),
                actorName: x.actorName,
                actorAvatarUrl: x.actorAvatarUrl,
              );
            }).toList();
          });
        }
      } catch (_) {}
    }

    // navigation
    if ((n.type == 'follow_request' || n.type == 'follow' || n.type == 'follow_accepted') &&
        n.actorId != null) {
      if (!mounted) return;
      context.push('/p/${n.actorId}');
      return;
    }

    if ((n.type == 'like' || n.type == 'comment' || n.type == 'share' || n.type == 'comment_like' || n.type == 'comment_reply') && n.postId != null) {
      String targetPostId = n.postId!;
      if (n.type == 'share' && n.actorId != null) {
        final sharedWrapper = await _db
            .from('posts')
            .select('id')
            .eq('user_id', n.actorId!)
            .eq('shared_post_id', n.postId!)
            .maybeSingle();
        final resolvedId = (sharedWrapper?['id'] ?? '').toString();
        if (resolvedId.isNotEmpty) {
          targetPostId = resolvedId;
        }
      }

      final post = await _db
          .from('posts')
          .select('post_type')
          .eq('id', targetPostId)
          .maybeSingle();

      final postType = (post?['post_type'] as String?) ?? '';
      if (!mounted) return;

      if (postType == 'market') {
        context.push('/marketplace/product/$targetPostId?tab=qa');
        return;
      }
      if (postType == 'service_offer' || postType == 'service_request') {
        context.push('/gigs/service/$targetPostId?tab=qa');
        return;
      }
      if (postType == 'food_ad' || postType == 'food') {
        context.push('/foods/$targetPostId?tab=qa');
        return;
      }

      if (n.type == 'comment_like' || n.type == 'comment_reply') {
        context.push('/post/$targetPostId/comments');
      } else {
        context.push('/post/$targetPostId');
      }
      return;
    }

    if (n.type == 'mention' && n.postId != null) {
      final post = await _db
          .from('posts')
          .select('post_type')
          .eq('id', n.postId!)
          .maybeSingle();

      final postType = (post?['post_type'] as String?) ?? '';
      if (!mounted) return;

      if (postType == 'market') {
        context.push('/marketplace/product/${n.postId}?tab=qa');
        return;
      }
      if (postType == 'service_offer' || postType == 'service_request') {
        context.push('/gigs/service/${n.postId}?tab=qa');
        return;
      }
      if (postType == 'food_ad' || postType == 'food') {
        context.push('/foods/${n.postId}?tab=qa');
        return;
      }

      if (n.commentId != null && n.commentId!.isNotEmpty) {
        context.push('/post/${n.postId}/comments');
      } else {
        context.push('/post/${n.postId}');
      }
      return;
    }

    if ((n.type == 'offer_message' ||
            n.type == 'offer_sent' ||
            n.type == 'offer_accepted' ||
            n.type == 'offer_rejected') &&
        n.postId != null &&
        n.actorId != null) {
      if (!mounted) return;
      context.push('/offer-chat/post/${n.postId}/user/${n.actorId}');
      return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.tr('nothing_to_open'))),
    );
  }

  Future<void> _acceptRequest(AppNotification n) async {
    final requesterId = n.actorId;
    if (requesterId == null) return;

    if (_actingIds.contains(n.id)) return;
    setState(() => _actingIds.add(n.id));

    try {
      await _followSvc.acceptRequest(requesterId);

      // mark read (best effort)
      try {
        await _svc.markRead(n.id);
        ref.read(notificationUnreadProvider.notifier).decrement();
      } catch (_) {}

      // remove immediately
      if (mounted) {
        setState(() {
          _items.removeWhere((x) => x.id == n.id);
          _actingIds.remove(n.id);
        });
      }

      await _refreshFirstPage(silent: true);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.tr('request_accepted'))),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _actingIds.remove(n.id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.tr('accept_failed', args: {'error': '$e'})),
        ),
      );
    }
  }

  Future<void> _declineRequest(AppNotification n) async {
    final requesterId = n.actorId;
    if (requesterId == null) return;

    if (_actingIds.contains(n.id)) return;
    setState(() => _actingIds.add(n.id));

    try {
      await _followSvc.declineRequest(requesterId);

      // mark read (best effort)
      try {
        await _svc.markRead(n.id);
        ref.read(notificationUnreadProvider.notifier).decrement();
      } catch (_) {}

      // remove immediately
      if (mounted) {
        setState(() {
          _items.removeWhere((x) => x.id == n.id);
          _actingIds.remove(n.id);
        });
      }

      await _refreshFirstPage(silent: true);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.tr('request_declined'))),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _actingIds.remove(n.id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.tr('decline_failed', args: {'error': '$e'})),
        ),
      );
    }
  }

  String _titleFor(AppNotification n) {
    final l10n = context.l10n;
    final name = _displayActorName(n);
    final anonymous = l10n.tr('someone');

    switch (n.type) {
      case 'follow_request':
        return l10n.tr('notif_follow_request', args: {'name': name});
      case 'follow_accepted':
        return l10n.tr('notif_follow_accepted', args: {'name': name});
      case 'follow':
        return l10n.tr('notif_follow', args: {'name': name});
      case 'like':
        return l10n.tr('notif_like', args: {'name': name});
      case 'comment':
        if (_isListingNotification(n)) {
          return l10n.tr('notif_listing_question', args: {'name': name});
        }
        return l10n.tr('notif_comment', args: {'name': name});
      case 'comment_like':
        return l10n.tr('notif_comment_like', args: {'name': name});
      case 'comment_reply':
        if (_isListingNotification(n)) {
          return l10n.tr('notif_listing_reply', args: {'name': name});
        }
        return l10n.tr('notif_comment_reply', args: {'name': name});
      case 'share':
        return l10n.tr('notif_share', args: {'name': name});
      case 'mention':
        return n.commentId != null && n.commentId!.isNotEmpty
            ? l10n.tr('notif_tagged_comment', args: {'name': name})
            : l10n.tr('notif_tagged_post', args: {'name': name});
      case 'offer_message':
        return l10n.tr('notif_offer_message', args: {'name': anonymous});
      case 'offer_sent':
        return l10n.tr('notif_offer_sent', args: {'name': anonymous});
      case 'offer_accepted':
        return l10n.tr('notif_offer_accepted', args: {'name': anonymous});
      case 'offer_rejected':
        return l10n.tr('notif_offer_rejected', args: {'name': anonymous});
      default:
        return l10n.tr('notif_generic_update', args: {'name': name});
    }
  }

  bool _isListingNotification(AppNotification n) {
    return n.postType == 'market' ||
        n.postType == 'service_offer' ||
        n.postType == 'service_request' ||
        n.postType == 'food_ad' ||
        n.postType == 'food';
  }

  String _displayActorName(AppNotification n) {
    final actualName = (n.actorName?.trim().isNotEmpty ?? false)
        ? n.actorName!.trim()
        : context.l10n.tr('someone');
    if (!_isListingNotification(n)) return actualName;
    if (n.type == 'comment_reply' && n.actorId != null && n.actorId == n.postOwnerId) {
      if (n.postType == 'market' || n.postType == 'food_ad' || n.postType == 'food') {
        return context.l10n.tr('seller');
      }
      return context.l10n.tr('author');
    }
    return actualName;
  }

  String _formatTime(DateTime dt) {
    String two(int v) => v.toString().padLeft(2, '0');
    final d = dt.toLocal();
    return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
  }

  Widget _avatar(String? url) {
    if (url == null || url.trim().isEmpty) {
      return const CircleAvatar(child: Icon(Icons.person));
    }
    return CircleAvatar(backgroundImage: NetworkImage(url));
  }

  Widget _buildNotificationCard(AppNotification n) {
    final isActing = _actingIds.contains(n.id);
    final isActionableRequest = n.type == 'follow_request' && n.readAt == null;
    final isUnread = n.readAt == null;
    final statusColor = isUnread ? const Color(0xFF0B5D56) : const Color(0xFF6B7280);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isUnread ? const Color(0xFFEAF7F3) : Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isUnread ? const Color(0xFF0F766E).withValues(alpha: 0.55) : const Color(0xFFE6DDCE),
          width: isUnread ? 1.4 : 1,
        ),
        boxShadow: isUnread
            ? [
                BoxShadow(
                  color: const Color(0xFF0F766E).withValues(alpha: 0.08),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: isActionableRequest ? null : () => _onTap(n),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Stack(
                children: [
                  SizedBox(
                    width: 44,
                    height: 44,
                    child: _avatar(n.actorAvatarUrl),
                  ),
                  if (isUnread)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Theme.of(context).colorScheme.primary,
                          border: Border.all(
                            color: Theme.of(context).scaffoldBackgroundColor,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _titleFor(n),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isUnread ? const Color(0xFF0B5D56) : const Color(0xFF12211D),
                              fontWeight: isUnread ? FontWeight.w700 : FontWeight.w600,
                              fontSize: 14,
                              height: 1.25,
                            ),
                          ),
                        ),
                        if (isUnread) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFD8EFE8),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: const Color(0xFF8EC5B7)),
                            ),
                            child: Text(
                              context.l10n.tr('unread'),
                              style: TextStyle(
                                color: Color(0xFF0B5D56),
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                height: 1,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        Icon(
                          Icons.schedule_rounded,
                          size: 14,
                          color: statusColor,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          _formatTime(n.createdAt),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: isUnread ? FontWeight.w600 : FontWeight.w500,
                            color: statusColor,
                          ),
                        ),
                      ],
                    ),
                    if (isUnread && !isActionableRequest) ...[
                      const SizedBox(height: 8),
                      Text(
                        context.l10n.tr('tap_to_open'),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: statusColor,
                        ),
                      ),
                    ],
                    if (isActionableRequest) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton(
                            onPressed: isActing ? null : () => _declineRequest(n),
                            child: Text(context.l10n.tr('decline')),
                          ),
                          FilledButton(
                            onPressed: isActing ? null : () => _acceptRequest(n),
                            child: isActing
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : Text(context.l10n.tr('accept')),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (!isActionableRequest)
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Icon(Icons.chevron_right),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final unread = _items.where((e) => e.readAt == null).length;

    return Scaffold(
      appBar: GlobalAppBar(
        title: unread > 0 ? '${l10n.tr('notifications')} ($unread)' : l10n.tr('notifications'),
        showBackIfPossible: true,
        homeRoute: '/feed',
        actions: [
          if (_items.isNotEmpty && unread > 0)
            TextButton(onPressed: _markAllRead, child: Text(l10n.tr('mark_all_read'))),
        ],
      ),
      bottomNavigationBar: const GlobalBottomNav(),
      body: RefreshIndicator(
        onRefresh: () => _refreshFirstPage(),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 920),
            child: ListView(
              controller: _scrollCtrl,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFFFCF7), Color(0xFFF4EBDD)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: const Color(0xFFE6DDCE)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        unread > 0
                            ? '${l10n.tr('notifications')} ($unread)'
                            : l10n.tr('notifications'),
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        l10n.tr('notifications_intro'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_error != null)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(_error!),
                  )
                else if (_items.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: const Color(0xFFE6DDCE)),
                    ),
                    child: Center(child: Text(l10n.tr('no_notifications_yet'))),
                  )
                else
                  ..._items.map(_buildNotificationCard),
                if (_items.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 24),
                    child: Center(
                      child: !_hasMore
                          ? const SizedBox.shrink()
                          : _loadingMore
                              ? const CircularProgressIndicator()
                              : Text(l10n.tr('scroll_down_load_more')),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
