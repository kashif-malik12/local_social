// lib/screens/notifications_screen.dart
//
// ✅ Updated:
// - Pull-to-refresh (RefreshIndicator)
// - Uses your GoRouter paths:
//   - follow -> /p/:id
//   - like/comment -> /post/:id  (post detail)
// - Realtime subscription refreshes list (debounced)
// - Mark all read
// - Unread dot indicator on each tile

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/notification_model.dart';
import '../services/notification_service.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _db = Supabase.instance.client;
  late final NotificationService _svc;

  bool _loading = true;
  String? _error;
  List<AppNotification> _items = [];

  RealtimeChannel? _channel;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _svc = NotificationService(_db);
    _load();

    _channel = _svc.subscribeToMyNotifications(() {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 350), () async {
        await _load(silent: true);
      });
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    final ch = _channel;
    _channel = null;
    if (ch != null) {
      _svc.unsubscribe(ch);
    }
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else {
      setState(() => _error = null);
    }

    try {
      final rows = await _svc.fetchLatest(limit: 80);
      final items = rows.map(AppNotification.fromMap).toList();

      if (!mounted) return;
      setState(() {
        _items = items;
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

  Future<void> _markAllRead() async {
    try {
      await _svc.markAllRead();
      final now = DateTime.now();

      if (!mounted) return;
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
        SnackBar(content: Text('Failed to mark all read: $e')),
      );
    }
  }

  Future<void> _onTap(AppNotification n) async {
    // mark read (don’t block navigation if it fails)
    if (n.readAt == null) {
      try {
        await _svc.markRead(n.id);

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
                readAt: DateTime.now(),
                actorName: x.actorName,
                actorAvatarUrl: x.actorAvatarUrl,
              );
            }).toList();
          });
        }
      } catch (_) {}
    }

    // Navigate based on your router
    if (n.type == 'follow' && n.actorId != null) {
      context.push('/p/${n.actorId}');
      return;
    }

    if (n.type == 'like' && n.postId != null) {
      context.push('/post/${n.postId}');
      return;
    }

    if (n.type == 'comment' && n.postId != null) {
      context.push('/post/${n.postId}');
      return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Nothing to open for this notification')),
    );
  }

  String _titleFor(AppNotification n) {
    final name = (n.actorName?.trim().isNotEmpty ?? false) ? n.actorName!.trim() : 'Someone';
    switch (n.type) {
      case 'follow':
        return '$name started following you';
      case 'like':
        return '$name liked your post';
      case 'comment':
        return '$name commented on your post';
      default:
        return '$name sent an update';
    }
  }

  String _formatTime(DateTime dt) {
    String two(int v) => v.toString().padLeft(2, '0');
    final d = dt.toLocal();
    return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
  }

  String _subtitleFor(AppNotification n) {
    final time = _formatTime(n.createdAt);
    switch (n.type) {
      case 'follow':
        return time;
      case 'like':
      case 'comment':
        return 'Tap to open • $time';
      default:
        return time;
    }
  }

  Widget _avatar(String? url) {
    if (url == null || url.trim().isEmpty) {
      return const CircleAvatar(child: Icon(Icons.person));
    }
    return CircleAvatar(
      backgroundImage: NetworkImage(url),
      onBackgroundImageError: (_, __) {},
      child: const SizedBox.shrink(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final unread = _items.where((e) => e.readAt == null).length;

    return Scaffold(
      appBar: AppBar(
        title: Text(unread > 0 ? 'Notifications ($unread)' : 'Notifications'),
        actions: [
          if (_items.isNotEmpty && unread > 0)
            TextButton(
              onPressed: _markAllRead,
              child: const Text('Mark all read'),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Failed to load notifications',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: () => _load(),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => _load(),
                  child: _items.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: const [
                            SizedBox(height: 120),
                            Center(child: Text('No notifications yet')),
                          ],
                        )
                      : ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: _items.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final n = _items[index];
                            final isUnread = n.readAt == null;

                            return ListTile(
                              leading: Stack(
                                children: [
                                  _avatar(n.actorAvatarUrl),
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
                              title: Text(
                                _titleFor(n),
                                style: isUnread
                                    ? const TextStyle(fontWeight: FontWeight.w600)
                                    : null,
                              ),
                              subtitle: Text(_subtitleFor(n)),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => _onTap(n),
                            );
                          },
                        ),
                ),
    );
  }
}