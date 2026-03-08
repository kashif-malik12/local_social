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
import '../../../widgets/global_app_bar.dart';
import '../../../widgets/global_bottom_nav.dart';
import '../../../widgets/post_media_view.dart';
import '../../../widgets/tagged_content.dart';
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
  bool _showMyProfileActions = false;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Widget _buildProfileHeader({
    required BuildContext context,
    required String name,
    required String type,
    required String location,
    required String bio,
    required bool canOpenLists,
  }) {
    return Container(
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
            name,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          if (type.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Type: $type', style: const TextStyle(fontSize: 12)),
          ],
          if (location.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Location: $location', style: const TextStyle(fontSize: 12)),
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
          if (!_isMe) ...[
            const SizedBox(height: 16),
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
                onPressed:
                    (_loading || _followStatus == FollowStatus.pending) ? null : _toggleFollow,
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
        ],
      ),
    );
  }

  String _profileTypeLabel() {
    final type = (_profile?['profile_type'] ?? _profile?['account_type'] ?? '').toString();
    if (type != 'org') return type;

    final orgKind = (_profile?['org_kind'] ?? '').toString();
    switch (orgKind) {
      case 'government':
        return 'Organization • Government';
      case 'nonprofit':
        return 'Organization • Non-profit';
      case 'news_agency':
        return 'Organization • News agency';
      default:
        return 'Organization';
    }
  }

  Widget _buildProfileSidebar(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFE6DDCE)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Profile actions',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 14),
              if (_isMe) ...[
                _buildSidebarAction(
                  context: context,
                  icon: Icons.person_add_alt_1_outlined,
                  title: 'Follow requests',
                  subtitle: _pendingRequests > 0
                      ? '$_pendingRequests pending requests'
                      : 'Review incoming requests',
                  onTap: () => context.push('/follow-requests'),
                ),
                _buildSidebarAction(
                  context: context,
                  icon: Icons.edit_outlined,
                  title: 'Edit profile',
                  subtitle: 'Update your details and location',
                  onTap: () async {
                    final router = GoRouter.of(context);
                    await router.push('/profile/edit');
                    if (!mounted) return;
                    await _loadAll();
                  },
                ),
                _buildSidebarAction(
                  context: context,
                  icon: Icons.groups_outlined,
                  title: 'Followers',
                  subtitle: '$_followersCount people follow you',
                  onTap: () => context.push('/p/${widget.profileId}/followers'),
                ),
                _buildSidebarAction(
                  context: context,
                  icon: Icons.group_outlined,
                  title: 'Following',
                  subtitle: '$_followingCount profiles you follow',
                  onTap: () => context.push('/p/${widget.profileId}/following'),
                ),
                _buildSidebarAction(
                  context: context,
                  icon: Icons.inventory_2_outlined,
                  title: 'My products',
                  subtitle: 'Edit or delete your marketplace ads',
                  onTap: () => context.push('/profile/my-products'),
                ),
                _buildSidebarAction(
                  context: context,
                  icon: Icons.work_outline,
                  title: 'My gigs',
                  subtitle: 'Edit or delete your service ads',
                  onTap: () => context.push('/profile/my-gigs'),
                ),
                if ((_profile?['is_restaurant'] == true))
                  _buildSidebarAction(
                    context: context,
                    icon: Icons.restaurant_menu_outlined,
                    title: 'My foods',
                    subtitle: 'Edit or delete your food ads',
                    onTap: () => context.push('/profile/my-foods'),
                  ),
              ] else ...[
                _buildSidebarAction(
                  context: context,
                  icon: Icons.groups_outlined,
                  title: 'Followers',
                  subtitle: 'Visible only on your own profile',
                  onTap: null,
                ),
                _buildSidebarAction(
                  context: context,
                  icon: Icons.group_outlined,
                  title: 'Following',
                  subtitle: 'Visible only on your own profile',
                  onTap: null,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  List<PopupMenuEntry<String>> _buildProfileMenuItems() {
    if (_isMe) {
      return [
        const PopupMenuItem(value: 'follow_requests', child: Text('Follow requests')),
        const PopupMenuItem(value: 'edit_profile', child: Text('Edit profile')),
        const PopupMenuItem(value: 'followers', child: Text('Followers')),
        const PopupMenuItem(value: 'following', child: Text('Following')),
        const PopupMenuItem(value: 'my_products', child: Text('My products')),
        const PopupMenuItem(value: 'my_gigs', child: Text('My gigs')),
        if ((_profile?['is_restaurant'] == true))
          const PopupMenuItem(value: 'my_foods', child: Text('My foods')),
      ];
    }

    return const [
      PopupMenuItem(value: 'report_user', child: Text('Report user')),
    ];
  }

  Future<void> _handleProfileMenuAction(String value) async {
    switch (value) {
      case 'follow_requests':
        await context.push('/follow-requests');
        return;
      case 'edit_profile':
        await context.push('/profile/edit');
        if (!mounted) return;
        await _loadAll();
        return;
      case 'followers':
        await context.push('/p/${widget.profileId}/followers');
        return;
      case 'following':
        await context.push('/p/${widget.profileId}/following');
        return;
      case 'my_products':
        await context.push('/profile/my-products');
        return;
      case 'my_gigs':
        await context.push('/profile/my-gigs');
        return;
      case 'my_foods':
        await context.push('/profile/my-foods');
        return;
      case 'report_user':
        await _reportUser();
        return;
    }
  }

  Widget _buildProfileLeftSidebar({
    required BuildContext context,
    required String name,
    required String type,
    required String location,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFE6DDCE)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Profile overview',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 14),
              Text(
                name,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              if (type.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Type: $type',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (location.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  'Location: $location',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFE6DDCE)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Connections',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 14),
              _clickableStat(
                enabled: _isMe,
                onTap: _isMe ? () => context.push('/p/${widget.profileId}/followers') : null,
                child: _StatTile(label: 'Followers', value: _followersCount),
              ),
              const SizedBox(height: 10),
              _clickableStat(
                enabled: _isMe,
                onTap: _isMe ? () => context.push('/p/${widget.profileId}/following') : null,
                child: _StatTile(label: 'Following', value: _followingCount),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSidebarAction({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Opacity(
          opacity: onTap == null ? 0.55 : 1,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.45),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.12),
                  child: Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProfileMainContent({
    required BuildContext context,
    required String name,
    required String type,
    required String location,
    required String bio,
    required bool canOpenLists,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildProfileHeader(
          context: context,
          name: name,
          type: type,
          location: location,
          bio: bio,
          canOpenLists: canOpenLists,
        ),
        if (_isMe) ...[
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.35),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'This is your profile',
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE6DDCE)),
            ),
            child: Column(
              children: [
                InkWell(
                  onTap: () {
                    setState(() => _showMyProfileActions = !_showMyProfileActions);
                  },
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: Row(
                      children: [
                        const Icon(Icons.tune_rounded),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Profile actions',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        Icon(
                          _showMyProfileActions
                              ? Icons.keyboard_arrow_up_rounded
                              : Icons.keyboard_arrow_down_rounded,
                        ),
                      ],
                    ),
                  ),
                ),
                if (_showMyProfileActions) ...[
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        _buildSidebarAction(
                          context: context,
                          icon: Icons.person_add_alt_1_outlined,
                          title: 'Follow requests',
                          subtitle: _pendingRequests > 0
                              ? '$_pendingRequests pending requests'
                              : 'Review incoming requests',
                          onTap: () => context.push('/follow-requests'),
                        ),
                        _buildSidebarAction(
                          context: context,
                          icon: Icons.edit_outlined,
                          title: 'Edit profile',
                          subtitle: 'Update your details and location',
                          onTap: () async {
                            await context.push('/profile/edit');
                            if (!mounted) return;
                            await _loadAll();
                          },
                        ),
                        _buildSidebarAction(
                          context: context,
                          icon: Icons.groups_outlined,
                          title: 'Followers',
                          subtitle: '$_followersCount people follow you',
                          onTap: () => context.push('/p/${widget.profileId}/followers'),
                        ),
                        _buildSidebarAction(
                          context: context,
                          icon: Icons.group_outlined,
                          title: 'Following',
                          subtitle: '$_followingCount profiles you follow',
                          onTap: () => context.push('/p/${widget.profileId}/following'),
                        ),
                        _buildSidebarAction(
                          context: context,
                          icon: Icons.inventory_2_outlined,
                          title: 'My products',
                          subtitle: 'Edit or delete your marketplace ads',
                          onTap: () => context.push('/profile/my-products'),
                        ),
                        _buildSidebarAction(
                          context: context,
                          icon: Icons.work_outline,
                          title: 'My gigs',
                          subtitle: 'Edit or delete your service ads',
                          onTap: () => context.push('/profile/my-gigs'),
                        ),
                        if ((_profile?['is_restaurant'] == true))
                          _buildSidebarAction(
                            context: context,
                            icon: Icons.restaurant_menu_outlined,
                            title: 'My foods',
                            subtitle: 'Edit or delete your food ads',
                            onTap: () => context.push('/profile/my-foods'),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
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
                    TaggedContent(content: p.content),
                    if ((p.imageUrl ?? '').isNotEmpty ||
                        (p.secondImageUrl ?? '').isNotEmpty ||
                        (p.videoUrl ?? '').isNotEmpty) ...[
                      const SizedBox(height: 10),
                      PostMediaView(
                        imageUrl: p.imageUrl,
                        secondImageUrl: p.secondImageUrl,
                        videoUrl: p.videoUrl,
                      ),
                    ],
                    const SizedBox(height: 8),
                    if (p.postType == 'market' ||
                        p.postType == 'service_offer' ||
                        p.postType == 'service_request' ||
                        p.postType == 'food_ad' ||
                        p.postType == 'food')
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () {
                              if (p.postType == 'market') {
                                context.push('/marketplace/product/${p.id}');
                                return;
                              }
                              if (p.postType == 'service_offer' ||
                                  p.postType == 'service_request') {
                                context.push('/gigs/service/${p.id}');
                                return;
                              }
                              context.push('/foods/${p.id}');
                            },
                            icon: Icon(
                              p.postType == 'market'
                                  ? Icons.open_in_new
                                  : (p.postType == 'food_ad' || p.postType == 'food')
                                      ? Icons.restaurant
                                      : Icons.work_outline,
                              size: 18,
                            ),
                            label: Text(
                              p.postType == 'market'
                                  ? 'Open product'
                                  : (p.postType == 'food_ad' || p.postType == 'food')
                                      ? 'Open food'
                                      : 'Open gig',
                            ),
                          ),
                        ],
                      ),
                    if (_isMe && (p.postType == 'food_ad' || p.postType == 'food')) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FilledButton.tonalIcon(
                          onPressed: () => context.push('/profile/my-foods'),
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          label: const Text('Manage food ad'),
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    _buildReactionsRow(p),
                    const SizedBox(height: 8),
                    if (p.locationName != null)
                      Text('Location: ${p.locationName}', style: const TextStyle(fontSize: 12)),
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
    );
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
          .where((post) {
            final type = (post.postType ?? '').trim();
            return type != 'market' &&
                type != 'service_offer' &&
                type != 'service_request';
          })
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

  Future<(Uint8List, String)?> _pickPortfolioFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null) return null;

    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null) {
      throw Exception('No image bytes. Try again.');
    }

    return (bytes, (file.extension ?? 'jpg').toLowerCase());
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

  Future<void> _replacePortfolioImage(PortfolioItem item) async {
    if (!_isMe) return;
    if (_portfolioActionLoading) return;

    setState(() => _portfolioActionLoading = true);

    try {
      final picked = await _pickPortfolioFile();
      if (picked == null) return;

      final svc = PortfolioService(_db);
      await svc.replacePortfolioImage(
        itemId: item.id,
        profileId: widget.profileId,
        bytes: picked.$1,
        fileExt: picked.$2,
      );

      await _loadPortfolio();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Portfolio update error: $e')),
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
               crossAxisCount: 3,
               crossAxisSpacing: 8,
               mainAxisSpacing: 8,
               childAspectRatio: 1.0,
             ),
             itemBuilder: (_, i) {
               final item = _portfolio[i];
               return GestureDetector(
                 onTap: () => _openImage(item.imageUrl),
                 child: ClipRRect(
                   borderRadius: BorderRadius.circular(12),
                   child: Stack(
                     children: [
                       Container(
                         color: Colors.grey.shade200,
                         padding: const EdgeInsets.all(6),
                         width: double.infinity,
                         height: double.infinity,
                         child: Image.network(
                           item.imageUrl,
                           fit: BoxFit.contain,
                           alignment: Alignment.center,
                         ),
                       ),
                       if (_isMe)
                         Positioned(
                           top: 8,
                           right: 8,
                           child: Row(
                             mainAxisSize: MainAxisSize.min,
                             children: [
                               _buildPortfolioActionButton(
                                 icon: Icons.edit_outlined,
                                 tooltip: 'Replace photo',
                                 onTap: _portfolioActionLoading
                                     ? null
                                     : () => _replacePortfolioImage(item),
                               ),
                               const SizedBox(width: 6),
                               _buildPortfolioActionButton(
                                 icon: Icons.delete_outline,
                                 tooltip: 'Remove photo',
                                 onTap: _portfolioActionLoading
                                     ? null
                                     : () => _confirmDeletePortfolio(item.id),
                               ),
                             ],
                           ),
                         ),
                     ],
                   ),
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
        bottomNavigationBar: const GlobalBottomNav(),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('Profile error:\n$_error'),
        ),
      );
    }

    final name = (_profile?['full_name'] ?? 'Profile').toString();
    final bio = (_profile?['bio'] ?? '').toString();
    final type = _profileTypeLabel();
    final city = (_profile?['city'] ?? '').toString();
    final zipcode = (_profile?['zipcode'] ?? '').toString();
    final location = city.isNotEmpty ? city : zipcode;

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
              onSelected: _handleProfileMenuAction,
              itemBuilder: (_) => _buildProfileMenuItems(),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadAll,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 1100;

            if (!isWide) {
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildProfileMainContent(
                    context: context,
                    name: name,
                    type: type,
                    location: location,
                    bio: bio,
                    canOpenLists: canOpenLists,
                  ),
                ],
              );
            }

            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 250,
                    child: _buildProfileLeftSidebar(
                      context: context,
                      name: name,
                      type: type,
                      location: location,
                    ),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: _buildProfileMainContent(
                        context: context,
                        name: name,
                        type: type,
                        location: location,
                        bio: bio,
                        canOpenLists: canOpenLists,
                      ),
                    ),
                  ),
                  const SizedBox(width: 18),
                  SizedBox(
                    width: 320,
                    child: _buildProfileSidebar(context),
                  ),
                ],
              ),
            );
          },
        ),
      ),
      bottomNavigationBar: const GlobalBottomNav(),
    );
  }

  Widget _buildPortfolioActionButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.black.withOpacity(0.58),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Tooltip(
          message: tooltip,
          child: Padding(
            padding: const EdgeInsets.all(7),
            child: Icon(icon, color: Colors.white, size: 18),
          ),
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
