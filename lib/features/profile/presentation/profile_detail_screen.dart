import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../models/post_model.dart';
import '../../../models/portfolio_item.dart';
import '../../../services/reaction_service.dart';
import '../../../services/follow_service.dart';
import '../../../services/portfolio_service.dart';
import '../../../widgets/youtube_preview.dart';
import '../../../widgets/global_app_bar.dart';
import '../../../widgets/report_post_sheet.dart'; // ✅ NEW
import '../../../widgets/report_user_sheet.dart'; // ✅ NEW

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

  // ✅ Messaging permission (mutual follow)
  bool _canMessage = false;
  bool _canMessageLoading = true;

  int _followersCount = 0;
  int _followingCount = 0;

  // ✅ Follow requests badge (only for me)
  int _pendingRequests = 0;
  RealtimeChannel? _reqChannel;

  // ✅ Posts on profile
  bool _postsLoading = true;
  String? _postsError;
  List<Post> _posts = [];

  // ✅ Portfolio (business/org only)
  bool _portfolioLoading = true;
  String? _portfolioError;
  List<PortfolioItem> _portfolio = [];
  bool _portfolioActionLoading = false;

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

    // ✅ After profile loads (we need profile_type), load portfolio
    await _loadPortfolioIfEligible();
  }

  // =========================
  // ✅ REPORT USER
  // =========================
  Future<void> _reportUser() async {
    final reported = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ReportUserSheet(reportedUserId: widget.profileId),
    );

    if (reported == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Thanks — we’ll review it.')),
      );
    }
  }

  // =========================
  // ✅ REPORT POST
  // =========================
  Future<void> _reportPost(Post post) async {
    final reported = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ReportPostSheet(postId: post.id),
    );

    if (reported == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Thanks — we’ll review it.')),
      );
    }
  }

  // =========================
  // ✅ MESSAGING PERMISSION
  // =========================
  Future<void> _loadCanMessage() async {
    if (!mounted) return;
    setState(() {
      _canMessage = false;
      _canMessageLoading = true;
    });

    if (_isMe) {
      if (!mounted) return;
      setState(() {
        _canMessage = false;
        _canMessageLoading = false;
      });
      return;
    }

    try {
      final res = await _db.rpc('can_message_me', params: {
        'p_other_user_id': widget.profileId,
      });

      if (!mounted) return;
      setState(() {
        _canMessage = (res as bool);
        _canMessageLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _canMessage = false;
        _canMessageLoading = false;
      });
    }
  }

  // =========================
  // ✅ FOLLOW REQUESTS BADGE
  // =========================
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

  // =========================
  // ✅ LOAD PROFILE + FOLLOW
  // =========================
  Future<void> _loadProfileAndFollow() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final myUserId = _db.auth.currentUser!.id;

      final p =
          await _db.from('profiles').select('*').eq('id', widget.profileId).single();
      _profile = p;

      _isMe = (widget.profileId == myUserId);

      // ✅ Messaging permission (mutual follow)
      await _loadCanMessage();

      final follow = FollowService(_db);

      if (!_isMe) {
        _followStatus = await follow.getMyStatus(widget.profileId);
      } else {
        _followStatus = FollowStatus.none;
      }

      _followersCount = await follow.followersCount(widget.profileId);
      _followingCount = await follow.followingCount(widget.profileId);

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

  // =========================
  // ✅ POSTS
  // =========================
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

  // =========================
  // ✅ FOLLOW TOGGLE
  // =========================
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

      await _loadCanMessage();
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

  // =========================
  // ✅ PORTFOLIO
  // =========================
  bool _canHavePortfolio() {
    final type = (_profile?['profile_type'] ?? _profile?['account_type'] ?? '').toString();
    return type == 'business' || type == 'org';
  }

  Future<void> _loadPortfolioIfEligible() async {
    if (!_canHavePortfolio()) {
      if (!mounted) return;
      setState(() {
        _portfolioLoading = false;
        _portfolioError = null;
        _portfolio = [];
      });
      return;
    }
    await _loadPortfolio();
  }

  Future<void> _loadPortfolio() async {
    setState(() {
      _portfolioLoading = true;
      _portfolioError = null;
    });

    try {
      final svc = PortfolioService(_db);
      final items = await svc.fetchPortfolio(widget.profileId);

      if (!mounted) return;
      setState(() {
        _portfolio = items;
        _portfolioLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _portfolioError = e.toString();
        _portfolioLoading = false;
      });
    }
  }

  Future<void> _pickAndUploadPortfolioImage() async {
    if (!_isMe) return;
    if (_portfolioActionLoading) return;
    if (_portfolio.length >= 5) return;

    setState(() => _portfolioActionLoading = true);

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
      if (result == null) return;

      final file = result.files.single;
      final Uint8List? bytes = file.bytes;
      if (bytes == null) {
        throw Exception('No image bytes. Try again.');
      }

      final ext = (file.extension ?? 'jpg').toLowerCase();

      final svc = PortfolioService(_db);
      await svc.addPortfolioImage(
        profileId: widget.profileId,
        bytes: bytes,
        fileExt: ext,
      );

      await _loadPortfolio();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Portfolio upload error: $e')),
      );
    } finally {
      if (mounted) setState(() => _portfolioActionLoading = false);
    }
  }

  void _openImage(String url) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        child: InteractiveViewer(
          child: Image.network(url),
        ),
      ),
    );
  }

  Future<void> _confirmDeletePortfolio(String itemId) async {
    if (!_isMe) return;
    if (_portfolioActionLoading) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove photo?'),
        content: const Text('This will remove it from your portfolio.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    setState(() => _portfolioActionLoading = true);

    try {
      final svc = PortfolioService(_db);
      await svc.deletePortfolioItem(itemId: itemId);
      await _loadPortfolio();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Portfolio delete error: $e')),
      );
    } finally {
      if (mounted) setState(() => _portfolioActionLoading = false);
    }
  }

  Widget _buildPortfolioSection(BuildContext context) {
    if (!_canHavePortfolio()) return const SizedBox.shrink();

    final canAdd = _isMe && _portfolio.length < 5;

    if (_portfolioLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_portfolioError != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text('Portfolio error:\n$_portfolioError'),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Portfolio', style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            Text('${_portfolio.length}/5',
                style: TextStyle(color: Theme.of(context).hintColor)),
            const SizedBox(width: 8),
            if (canAdd)
              ElevatedButton.icon(
                onPressed: _portfolioActionLoading ? null : _pickAndUploadPortfolioImage,
                icon: _portfolioActionLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add),
                label: const Text('Add'),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (_portfolio.isEmpty)
          Text(
            _isMe ? 'Add up to 5 photos to your portfolio.' : 'No portfolio photos yet.',
            style: TextStyle(color: Theme.of(context).hintColor),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _portfolio.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemBuilder: (_, i) {
              final item = _portfolio[i];
              return GestureDetector(
                onTap: () => _openImage(item.imageUrl),
                onLongPress: _isMe ? () => _confirmDeletePortfolio(item.id) : null,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(item.imageUrl, fit: BoxFit.cover),
                ),
              );
            },
          ),
        const SizedBox(height: 24),
        const Divider(),
        const SizedBox(height: 12),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _profile == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_error != null) {
      return Scaffold(
        appBar: const GlobalAppBar(title: 'Local Feed ✅'),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('Profile error:\n$_error'),
        ),
      );
    }

    final name = (_profile?['full_name'] ?? 'Profile').toString();
    final bio = (_profile?['bio'] ?? '').toString();
    final type = (_profile?['profile_type'] ?? _profile?['account_type'] ?? '').toString();

    final canOpenLists = _isMe;

    return Scaffold(
      appBar: GlobalAppBar(
        title: 'Local Feed ✅',
        showBackIfPossible: true,
        homeRoute: '/feed',
        actions: [
          if (!_isMe)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (value) async {
                if (value == 'report_user') {
                  await _reportUser();
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'report_user',
                  child: Text('Report user'),
                ),
              ],
            ),
        ],
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
                    onTap: canOpenLists ? () => context.push('/p/${widget.profileId}/followers') : null,
                    child: _StatTile(label: 'Followers', value: _followersCount),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _clickableStat(
                    enabled: canOpenLists,
                    onTap: canOpenLists ? () => context.push('/p/${widget.profileId}/following') : null,
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
              Column(
                children: [
                  if (!_canMessageLoading && _canMessage) ...[
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => context.push('/chat/user/${widget.profileId}'),
                        icon: const Icon(Icons.message_outlined),
                        label: const Text('Message'),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: (_loading || _followStatus == FollowStatus.pending) ? null : _toggleFollow,
                      child: Text(_followButtonText()),
                    ),
                  ),
                  if (!_canMessageLoading && !_canMessage) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Message is available after you both follow each other.',
                      style: TextStyle(color: Theme.of(context).hintColor, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
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

            _buildPortfolioSection(context),

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
                        // ✅ header row with report post menu (if not my post)
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                p.authorName ?? (_isMe ? 'You' : 'Unknown'),
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                            if (_db.auth.currentUser?.id != p.userId)
                              PopupMenuButton<String>(
                                icon: const Icon(Icons.more_vert),
                                onSelected: (value) async {
                                  if (value == 'report_post') {
                                    await _reportPost(p);
                                  }
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                    value: 'report_post',
                                    child: Text('Report post'),
                                  ),
                                ],
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),

                        Text(p.content),

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