// lib/screens/notifications_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/notification_model.dart';
import '../services/notification_service.dart';
import '../services/follow_service.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
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
        SnackBar(content: Text('Load more failed: $e')),
      );
    }
  }

  Future<void> _markAllRead() async {
    try {
      await _svc.markAllRead();
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
        SnackBar(content: Text('Failed: $e')),
      );
    }
  }

  Future<void> _onTap(AppNotification n) async {
    // mark read (best-effort)
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

    // navigation
    if ((n.type == 'follow_request' || n.type == 'follow' || n.type == 'follow_accepted') &&
        n.actorId != null) {
      if (!mounted) return;
      context.push('/p/${n.actorId}');
      return;
    }

    if ((n.type == 'like' || n.type == 'comment') && n.postId != null) {
      if (!mounted) return;
      context.push('/post/${n.postId}');
      return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Nothing to open')),
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
        const SnackBar(content: Text('Request accepted')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _actingIds.remove(n.id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Accept failed: $e')),
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
        const SnackBar(content: Text('Request declined')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _actingIds.remove(n.id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Decline failed: $e')),
      );
    }
  }

  String _titleFor(AppNotification n) {
    final name = (n.actorName?.trim().isNotEmpty ?? false) ? n.actorName!.trim() : 'Someone';

    switch (n.type) {
      case 'follow_request':
        return '$name requested to follow you';
      case 'follow_accepted':
        return '$name accepted your follow request';
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

  Widget _avatar(String? url) {
    if (url == null || url.trim().isEmpty) {
      return const CircleAvatar(child: Icon(Icons.person));
    }
    return CircleAvatar(backgroundImage: NetworkImage(url));
  }

  @override
  Widget build(BuildContext context) {
    final unread = _items.where((e) => e.readAt == null).length;

    return Scaffold(
      appBar: AppBar(
        title: Text(unread > 0 ? 'Notifications ($unread)' : 'Notifications'),
        actions: [
          if (_items.isNotEmpty && unread > 0)
            TextButton(onPressed: _markAllRead, child: const Text('Mark all read')),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(16), child: Text(_error!)))
              : RefreshIndicator(
                  onRefresh: () => _refreshFirstPage(),
                  child: ListView.separated(
                    controller: _scrollCtrl,
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: _items.length + 1,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      if (index == _items.length) {
                        if (!_hasMore) return const SizedBox(height: 80);
                        return Padding(
                          padding: const EdgeInsets.all(16),
                          child: Center(
                            child: _loadingMore
                                ? const CircularProgressIndicator()
                                : const Text('Pull or scroll to load more'),
                          ),
                        );
                      }

                      final n = _items[index];
                      final isActing = _actingIds.contains(n.id);
                      final isActionableRequest = n.type == 'follow_request' && n.readAt == null;
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
                          style: isUnread ? const TextStyle(fontWeight: FontWeight.w600) : null,
                        ),
                        subtitle: Text(_formatTime(n.createdAt)),
                        trailing: isActionableRequest
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  TextButton(
                                    onPressed: isActing ? null : () => _declineRequest(n),
                                    child: const Text('Decline'),
                                  ),
                                  const SizedBox(width: 6),
                                  ElevatedButton(
                                    onPressed: isActing ? null : () => _acceptRequest(n),
                                    child: isActing
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(strokeWidth: 2),
                                          )
                                        : const Text('Accept'),
                                  ),
                                ],
                              )
                            : const Icon(Icons.chevron_right),
                        onTap: isActionableRequest ? null : () => _onTap(n),
                      );
                    },
                  ),
                ),
    );
  }
}