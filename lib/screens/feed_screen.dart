// lib/screens/feed_screen.dart
//
// ✅ Updated to implement:
// (1) Unread notifications badge in AppBar
// (2) Global realtime subscription (starts in FeedScreen initState)
// (3) YouTube thumbnail preview in feed (tap opens player modal)

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/post_model.dart';
import '../services/post_service.dart';
import '../services/reaction_service.dart';
import '../widgets/youtube_preview.dart';
import '../widgets/global_app_bar.dart';

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  bool _loading = true;
  String? _error;
  List<Post> _posts = [];

  // ✅ Filters
  String _selectedScope = 'all'; // 'all' or 'following'
  String _selectedPostType = 'all';
  String _selectedAuthorType = 'all';

  // ✅ Notifications badge + realtime
  int _unreadNotifs = 0;
  RealtimeChannel? _notifChannel;
  Timer? _notifDebounce;

  @override
  void initState() {
    super.initState();
    _load();
    _initNotificationsUnread();
  }

  @override
  void dispose() {
    _notifDebounce?.cancel();
    final ch = _notifChannel;
    _notifChannel = null;
    if (ch != null) {
      Supabase.instance.client.removeChannel(ch);
    }
    super.dispose();
  }

  // -----------------------------
  // Notifications unread + realtime
  // -----------------------------
  Future<void> _initNotificationsUnread() async {
    await _refreshUnreadNotifs();
    _subscribeUnreadNotifsRealtime();
  }

  Future<void> _refreshUnreadNotifs() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) {
      if (mounted) setState(() => _unreadNotifs = 0);
      return;
    }

    try {
      final rows = await Supabase.instance.client
          .from('notifications')
          .select('id')
          .eq('recipient_id', uid)
          .isFilter('read_at', null);

      if (!mounted) return;
      setState(() => _unreadNotifs = (rows as List).length);
    } catch (_) {
      // keep silent; badge not critical to block feed
    }
  }

  void _subscribeUnreadNotifsRealtime() {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;

    // avoid double subscription
    if (_notifChannel != null) return;

    final db = Supabase.instance.client;
    final channel = db.channel('notif-unread-$uid');

    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'recipient_id',
            value: uid,
          ),
          callback: (payload) {
            // quick bump for instant UX
            if (mounted) setState(() => _unreadNotifs = _unreadNotifs + 1);

            // debounce a refresh to stay correct in edge cases
            _notifDebounce?.cancel();
            _notifDebounce = Timer(const Duration(milliseconds: 450), () {
              _refreshUnreadNotifs();
            });
          },
        )
        .subscribe();

    _notifChannel = channel;
  }

  Widget _notifBell() {
    return IconButton(
      tooltip: 'Notifications',
      onPressed: () async {
        await context.push('/notifications');
        await _refreshUnreadNotifs();
      },
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(Icons.notifications),
          if (_unreadNotifs > 0)
            Positioned(
              right: -6,
              top: -4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                constraints: const BoxConstraints(minWidth: 18),
                child: Text(
                  _unreadNotifs > 99 ? '99+' : _unreadNotifs.toString(),
                  textAlign: TextAlign.center,
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
  }

  Future<void> _onBeforeLogout() async {
    // Clean up realtime channel before logout (prevents warnings)
    final ch = _notifChannel;
    _notifChannel = null;
    if (ch != null) {
      await Supabase.instance.client.removeChannel(ch);
    }
  }

  // -----------------------------
  // Feed load
  // -----------------------------
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final service = PostService(Supabase.instance.client);

      final raw = await service.fetchPublicFeed(
        scope: _selectedScope,
        postType: _selectedPostType,
        authorType: _selectedAuthorType,
      );

      setState(() {
        _posts = raw.map((e) => Post.fromMap(e)).toList();
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _posts = [];
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ✅ Likes + comments row
  Widget _buildReactionsRow(Post p) {
    final react = ReactionService(Supabase.instance.client);

    return FutureBuilder<List<dynamic>>(
      future: Future.wait([
        react.isLiked(p.id),
        react.likesCount(p.id),
        react.commentsCount(p.id),
      ]),
      builder: (context, snap) {
        final liked = snap.hasData ? snap.data![0] as bool : false;
        final likeCount = snap.hasData ? snap.data![1] as int : 0;
        final commentCount = snap.hasData ? snap.data![2] as int : 0;

        return Row(
          children: [
            TextButton.icon(
              onPressed: () async {
                try {
                  if (liked) {
                    await react.unlike(p.id);
                  } else {
                    await react.like(p.id);
                  }
                  if (mounted) setState(() {});
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Like error: $e')),
                  );
                }
              },
              icon: Icon(liked ? Icons.favorite : Icons.favorite_border),
              label: Text('$likeCount'),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: () => context.push('/post/${p.id}/comments'),
              icon: const Icon(Icons.comment_outlined),
              label: Text('$commentCount'),
            ),
          ],
        );
      },
    );
  }

  String? _getAuthorBadgeType(Post post) {
    if (post.authorType == 'business') return 'BUSINESS';
    if (post.authorType == 'org') return 'ORG';
    return null;
  }

  Widget _buildFilters() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          DropdownButton<String>(
            value: _selectedScope,
            items: const [
              DropdownMenuItem(value: 'all', child: Text('Public (All)')),
              DropdownMenuItem(value: 'following', child: Text('Following')),
            ],
            onChanged: (v) {
              if (v == null) return;
              setState(() => _selectedScope = v);
              _load();
            },
          ),
          DropdownButton<String>(
            value: _selectedPostType,
            items: const [
              DropdownMenuItem(value: 'all', child: Text('All posts')),
              DropdownMenuItem(value: 'post', child: Text('General')),
              DropdownMenuItem(value: 'market', child: Text('Market')),
              DropdownMenuItem(value: 'service_offer', child: Text('Service offer')),
              DropdownMenuItem(value: 'service_request', child: Text('Service request')),
              DropdownMenuItem(value: 'lost_found', child: Text('Lost & found')),
            ],
            onChanged: (v) {
              if (v == null) return;
              setState(() => _selectedPostType = v);
              _load();
            },
          ),
          DropdownButton<String>(
            value: _selectedAuthorType,
            items: const [
              DropdownMenuItem(value: 'all', child: Text('All authors')),
              DropdownMenuItem(value: 'person', child: Text('People')),
              DropdownMenuItem(value: 'business', child: Text('Businesses')),
              DropdownMenuItem(value: 'org', child: Text('Organizations')),
            ],
            onChanged: (v) {
              if (v == null) return;
              setState(() => _selectedAuthorType = v);
              _load();
            },
          ),
          TextButton.icon(
            onPressed: () {
              setState(() {
                _selectedScope = 'all';
                _selectedPostType = 'all';
                _selectedAuthorType = 'all';
              });
              _load();
            },
            icon: const Icon(Icons.refresh),
            label: const Text('Reset'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // ✅ Sticky + reusable app bar
      appBar: GlobalAppBar(
        title: 'Local Feed ✅',
        notifBell: _notifBell(),
        showBackIfPossible: false, // feed is home/root
        homeRoute: '/feed',
        onBeforeLogout: _onBeforeLogout,
      ),

      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('Feed error:\n$_error'),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () async {
                    await _load();
                    await _refreshUnreadNotifs();
                  },
                  child: ListView.builder(
                    itemCount: _posts.length + 1,
                    itemBuilder: (_, i) {
                      if (i == 0) return _buildFilters();

                      final p = _posts[i - 1];
                      final badgeText = _getAuthorBadgeType(p);

                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              InkWell(
                                onTap: () => context.push('/p/${p.userId}'),
                                borderRadius: BorderRadius.circular(8),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  child: Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 18,
                                        backgroundImage: (p.authorAvatarUrl != null &&
                                                p.authorAvatarUrl!.isNotEmpty)
                                            ? NetworkImage(p.authorAvatarUrl!)
                                            : null,
                                        child: (p.authorAvatarUrl == null ||
                                                p.authorAvatarUrl!.isEmpty)
                                            ? const Icon(Icons.person, size: 18)
                                            : null,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          p.authorName ?? 'Unknown',
                                          style: const TextStyle(fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      if (p.distanceKm != null) ...[
                                        Text(
                                          '${p.distanceKm!.toStringAsFixed(1)} km',
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                        const SizedBox(width: 8),
                                      ],
                                      if (badgeText != null)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(20),
                                            border: Border.all(),
                                          ),
                                          child: Text(badgeText, style: const TextStyle(fontSize: 12)),
                                        ),
                                    ],
                                  ),
                                ),
                              ),

                              const SizedBox(height: 6),
                              Text(p.content),

                              // ✅ YouTube preview
                              if (p.videoUrl != null && p.videoUrl!.isNotEmpty) ...[
                                YoutubePreview(videoUrl: p.videoUrl!),
                              ],

                              if (p.imageUrl != null) ...[
                                const SizedBox(height: 10),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.network(p.imageUrl!, fit: BoxFit.cover),
                                ),
                              ],

                              const SizedBox(height: 6),
                              _buildReactionsRow(p),

                              const SizedBox(height: 8),
                              if (p.locationName != null)
                                Text('📍 ${p.locationName}', style: const TextStyle(fontSize: 12)),
                              Text(
                                p.createdAt.toLocal().toString(),
                                style: const TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final res = await context.push('/create-post');
          if (!mounted) return;
          if (res == true) _load();
        },
        icon: const Icon(Icons.add),
        label: const Text('Post'),
      ),
    );
  }
}