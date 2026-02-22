import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../models/post_model.dart';
import '../../../services/reaction_service.dart';
import '../../../services/follow_service.dart';
import '../../../widgets/youtube_preview.dart'; // ✅ NEW

class ProfileDetailScreen extends StatefulWidget {
  final String profileId; // ✅ in your app this equals auth uid
  const ProfileDetailScreen({super.key, required this.profileId});

  @override
  State<ProfileDetailScreen> createState() => _ProfileDetailScreenState();
}

class _ProfileDetailScreenState extends State<ProfileDetailScreen> {
  final _db = Supabase.instance.client;

  bool _loading = true;
  String? _error;

  Map<String, dynamic>? _profile;
  bool _isMe = false;
  FollowStatus _followStatus = FollowStatus.none;

  int _followersCount = 0;
  int _followingCount = 0;

  // ✅ Follow requests badge (only for me)
  int _pendingRequests = 0;
  RealtimeChannel? _reqChannel;

  // ✅ Posts on profile
  bool _postsLoading = true;
  String? _postsError;
  List<Post> _posts = [];

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    final ch = _reqChannel;
    _reqChannel = null;
    if (ch != null) {
      _db.removeChannel(ch);
    }
    super.dispose();
  }

  Future<void> _loadAll() async {
    await Future.wait([
      _loadProfileAndFollow(),
      _loadPosts(),
    ]);
  }

  Future<void> _refreshPendingRequests() async {
    final me = _db.auth.currentUser?.id;
    if (me == null) return;

    final rows = await _db
        .from('follows')
        .select('follower_id')
        .eq('followed_profile_id', me)
        .eq('status', 'pending');

    if (!mounted) return;
    setState(() => _pendingRequests = (rows as List).length);
  }

  void _subscribeRequestsRealtime() {
    final me = _db.auth.currentUser?.id;
    if (me == null) return;
    if (_reqChannel != null) return;

    _reqChannel = _db.channel('follow-requests-$me')
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'follows',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'followed_profile_id',
          value: me,
        ),
        callback: (_) => _refreshPendingRequests(),
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'follows',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'followed_profile_id',
          value: me,
        ),
        callback: (_) => _refreshPendingRequests(),
      )
      ..subscribe();
  }

  Future<void> _loadProfileAndFollow() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final myUserId = _db.auth.currentUser!.id;

      // ✅ Your schema: profiles.id == auth uid
      final p = await _db
          .from('profiles')
          .select('*')
          .eq('id', widget.profileId)
          .single();
      _profile = p;

      _isMe = (widget.profileId == myUserId);

      final follow = FollowService(_db);

      // ✅ Follow state (only when not me)
      if (!_isMe) {
        _followStatus = await follow.getMyStatus(widget.profileId);
      } else {
        _followStatus = FollowStatus.none;
      }

      // ✅ Counts should be accepted only
      _followersCount = await follow.followersCount(widget.profileId);
      _followingCount = await follow.followingCount(widget.profileId);

      // ✅ Pending requests badge (only for me)
      if (_isMe) {
        await _refreshPendingRequests();
        _subscribeRequestsRealtime();
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadPosts() async {
    setState(() {
      _postsLoading = true;
      _postsError = null;
    });

    try {
      final rows = await _db
          .from('posts')
          .select('*, profiles(full_name, avatar_url)')
          .eq('user_id', widget.profileId)
          .order('created_at', ascending: false);

      final list = (rows as List)
          .map((e) => Post.fromMap(e as Map<String, dynamic>))
          .toList();

      if (mounted) setState(() => _posts = list);
    } catch (e) {
      if (mounted) setState(() => _postsError = e.toString());
    } finally {
      if (mounted) setState(() => _postsLoading = false);
    }
  }

  Future<void> _toggleFollow() async {
    if (_isMe) return;

    setState(() => _loading = true);

    try {
      final follow = FollowService(_db);

      if (_followStatus == FollowStatus.accepted ||
          _followStatus == FollowStatus.pending ||
          _followStatus == FollowStatus.declined) {
        await follow.cancelOrUnfollow(widget.profileId);
        _followStatus = FollowStatus.none;
      } else {
        await follow.requestFollow(widget.profileId);
        _followStatus = FollowStatus.pending;
      }

      _followersCount = await follow.followersCount(widget.profileId);
      _followingCount = await follow.followingCount(widget.profileId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Follow error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _followButtonText() {
    switch (_followStatus) {
      case FollowStatus.accepted:
        return 'Unfollow';
      case FollowStatus.pending:
        return 'Requested';
      case FollowStatus.declined:
        return 'Request again';
      case FollowStatus.none:
        return 'Request follow';
    }
  }

  // ✅ Likes + Comments row (for each post)
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

  Widget _followRequestsButtonWithBadge(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () => context.push('/follow-requests'),
        icon: Stack(
          clipBehavior: Clip.none,
          children: [
            const Icon(Icons.person_add_alt_1),
            if (_pendingRequests > 0)
              Positioned(
                right: -6,
                top: -6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _pendingRequests > 99 ? '99+' : '$_pendingRequests',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
        label: const Text('Follow Requests'),
      ),
    );
  }

  // ✅ Stat tile wrapper: only clickable if enabled
  Widget _clickableStat({
    required bool enabled,
    required VoidCallback? onTap,
    required Widget child,
  }) {
    if (!enabled) {
      return Opacity(opacity: 0.65, child: child);
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _profile == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Profile')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('Profile error:\n$_error'),
        ),
      );
    }

    final name = (_profile?['full_name'] ?? 'Profile').toString();
    final bio = (_profile?['bio'] ?? '').toString();
    final type =
        (_profile?['profile_type'] ?? _profile?['account_type'] ?? '').toString();

    // ✅ Allow opening follower/following lists ONLY on my own profile
    final canOpenLists = _isMe;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/feed');
            }
          },
        ),
        title: Text(name),
      ),
      body: RefreshIndicator(
        onRefresh: _loadAll,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(name, style: Theme.of(context).textTheme.headlineSmall),
            if (type.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('Type: $type', style: const TextStyle(fontSize: 12)),
            ],
            if (bio.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(bio),
            ],
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: _clickableStat(
                    enabled: canOpenLists,
                    onTap: canOpenLists
                        ? () => context.push('/p/${widget.profileId}/followers')
                        : null,
                    child: _StatTile(label: 'Followers', value: _followersCount),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _clickableStat(
                    enabled: canOpenLists,
                    onTap: canOpenLists
                        ? () => context.push('/p/${widget.profileId}/following')
                        : null,
                    child: _StatTile(label: 'Following', value: _followingCount),
                  ),
                ),
              ],
            ),

            if (!canOpenLists) ...[
              const SizedBox(height: 8),
              Text(
                'Followers/Following lists are private.',
                style: TextStyle(color: Theme.of(context).hintColor, fontSize: 12),
              ),
            ],

            const SizedBox(height: 16),

            if (!_isMe)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: (_loading || _followStatus == FollowStatus.pending)
                      ? null
                      : _toggleFollow,
                  child: Text(_followButtonText()),
                ),
              )
            else
              Column(
                children: [
                  const Text('This is your profile', textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  _followRequestsButtonWithBadge(context),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final router = GoRouter.of(context);
                        await router.push('/profile/edit');
                        if (!mounted) return;
                        await _loadAll();
                      },
                      icon: const Icon(Icons.edit),
                      label: const Text('Edit Profile'),
                    ),
                  ),
                ],
              ),

            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: Text('Posts', style: Theme.of(context).textTheme.titleMedium),
                ),
                IconButton(
                  tooltip: 'Refresh posts',
                  onPressed: _postsLoading ? null : _loadPosts,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 8),

            if (_postsLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_postsError != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text('Posts error:\n$_postsError'),
              )
            else if (_posts.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('No posts yet.'),
              )
            else
              ..._posts.map(
                (p) => Card(
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p.content),

                        // ✅ NEW: YouTube preview
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
                          Text('📍 ${p.locationName}',
                              style: const TextStyle(fontSize: 12)),
                        Text(
                          p.createdAt.toLocal().toString(),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final int value;
  const _StatTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text('$value', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(label),
        ],
      ),
    );
  }
}