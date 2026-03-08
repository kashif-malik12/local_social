// lib/screens/feed_screen.dart
//
// ✅ Updated to implement:
// (1) Unread notifications badge in AppBar
// (2) Global realtime subscription (starts in FeedScreen initState)
// (3) YouTube thumbnail preview in feed (tap opens player modal)
// (4) Cursor-based pagination (infinite scroll) + footer loader
//
// Notes:
// - Uses PostService.fetchPublicFeed(limit, beforeCreatedAt, beforeId)
// - Page size is 20 (tweakable)
// - De-dupes by post.id in case realtime inserts happen while scrolling.

import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app/chat_singletons.dart';
import '../core/food_categories.dart';
import '../models/post_model.dart';
import '../core/business_categories.dart';
import '../core/market_categories.dart';
import '../core/restaurant_categories.dart';
import '../core/service_categories.dart';
import '../services/post_service.dart';
import '../services/reaction_service.dart';
import '../widgets/youtube_preview.dart';
import '../widgets/global_bottom_nav.dart';
import '../widgets/global_app_bar.dart';
import '../widgets/mobile_video_feed.dart';
import '../widgets/post_media_view.dart';
import '../widgets/tagged_content.dart';
import '../widgets/report_post_sheet.dart'; // ✅ NEW

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  static const String _feedFiltersKey = 'feed_filters';

  // Feed state
  bool _loading = true;
  String? _error;
  List<Post> _posts = [];
  final Map<String, String> _authorBadgeLabels = {};
  final Map<String, String> _authorLocationLabels = {};
  final Map<String, String> _authorOrgKinds = {};
  final Set<String> _followingIds = {};
  final Set<String> _followerIds = {};
  final Set<String> _mutualConnectionIds = {};

  // ✅ Pagination state
  static const int _pageSize = 20;
  final ScrollController _scroll = ScrollController();
  bool _loadingMore = false;
  bool _hasMore = true;
  bool _showScrollTop = false;
  DateTime? _cursorCreatedAt;
  String? _cursorId;

  // ✅ Filters
  bool _generalPostsEnabled = true;
  String _generalPostsScope = 'all';
  bool _marketplaceEnabled = true;
  String _marketplaceScope = 'all';
  final Set<String> _selectedMarketplaceIntents = {'buying', 'selling'};
  final Set<String> _selectedMarketplaceCategories = {};
  bool _gigsEnabled = true;
  String _gigsScope = 'all';
  final Set<String> _selectedGigTypes = {'service_offer', 'service_request'};
  final Set<String> _selectedGigCategories = {};
  bool _lostFoundEnabled = true;
  String _lostFoundScope = 'all';
  bool _foodAdsEnabled = true;
  String _foodAdsScope = 'all';
  final Set<String> _selectedFoodCategories = {};
  bool _organizationsEnabled = false;
  String _organizationsScope = 'all';
  final Set<String> _selectedOrganizationKinds = {};
  int? _publicDistanceLimitKm;

  // ✅ Notifications badge + realtime
  int _unreadNotifs = 0;
  RealtimeChannel? _notifChannel;
  Timer? _notifDebounce;
  Map<String, dynamic>? _myProfileSummary;
  int _profileCompleteness = 0;
  int _pendingOfferConversations = 0;
  int _unreadOfferMessages = 0;
  List<Map<String, dynamic>> _topPosts = [];
  final PageController _mobileFeedPager = PageController();
  int _mobileFeedPage = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _initFeed();
    _initNotificationsUnread();
    _loadSidebarData();
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _mobileFeedPager.dispose();

    _notifDebounce?.cancel();
    final ch = _notifChannel;
    _notifChannel = null;
    if (ch != null) {
      Supabase.instance.client.removeChannel(ch);
    }
    super.dispose();
  }

  // -----------------------------
  // Infinite scroll trigger
  // -----------------------------
  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    final shouldShowTop = pos.pixels > 900;
    if (shouldShowTop != _showScrollTop && mounted) {
      setState(() => _showScrollTop = shouldShowTop);
    }
    if (pos.pixels >= pos.maxScrollExtent - 350) {
      _loadMore();
    }
  }

  Future<void> _initFeed() async {
    await _restoreSavedFilters();
    await _load(reset: true);
  }

  Future<void> _restoreSavedFilters() async {
    final user = Supabase.instance.client.auth.currentUser;
    final data = user?.userMetadata?[_feedFiltersKey];
    if (data is! Map) return;

    if (!mounted) return;
    setState(() {
      _generalPostsEnabled = data['general_enabled'] != false;
      _generalPostsScope = (data['general_scope'] as String?) ?? 'all';
      _marketplaceEnabled = data['market_enabled'] != false;
      _marketplaceScope = (data['market_scope'] as String?) ?? 'all';
      _selectedMarketplaceIntents
        ..clear()
        ..addAll(((data['market_intents'] as List?) ?? const []).map((e) => e.toString()));
      _selectedMarketplaceCategories
        ..clear()
        ..addAll(((data['market_categories'] as List?) ?? const []).map((e) => e.toString()));
      _gigsEnabled = data['gigs_enabled'] != false;
      _gigsScope = (data['gigs_scope'] as String?) ?? 'all';
      _selectedGigTypes
        ..clear()
        ..addAll(((data['gig_types'] as List?) ?? const []).map((e) => e.toString()));
      _selectedGigCategories
        ..clear()
        ..addAll(((data['gig_categories'] as List?) ?? const []).map((e) => e.toString()));
      _lostFoundEnabled = data['lost_found_enabled'] != false;
      _lostFoundScope = (data['lost_found_scope'] as String?) ?? 'all';
      _foodAdsEnabled = data['food_enabled'] != false;
      _foodAdsScope = (data['food_scope'] as String?) ?? 'all';
      _selectedFoodCategories
        ..clear()
        ..addAll(((data['food_categories'] as List?) ?? const []).map((e) => e.toString()));
      _organizationsEnabled = data['org_enabled'] == true;
      _organizationsScope = (data['org_scope'] as String?) ?? 'all';
      _selectedOrganizationKinds
        ..clear()
        ..addAll(((data['org_kinds'] as List?) ?? const []).map((e) => e.toString()));
      _publicDistanceLimitKm = (data['public_distance_km'] as num?)?.toInt();
    });
  }

  Future<void> _saveFilters() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    final payload = <String, dynamic>{
      _feedFiltersKey: {
        'general_enabled': _generalPostsEnabled,
        'general_scope': _generalPostsScope,
        'market_enabled': _marketplaceEnabled,
        'market_scope': _marketplaceScope,
        'market_intents': _selectedMarketplaceIntents.toList(),
        'market_categories': _selectedMarketplaceCategories.toList(),
        'gigs_enabled': _gigsEnabled,
        'gigs_scope': _gigsScope,
        'gig_types': _selectedGigTypes.toList(),
        'gig_categories': _selectedGigCategories.toList(),
        'lost_found_enabled': _lostFoundEnabled,
        'lost_found_scope': _lostFoundScope,
        'food_enabled': _foodAdsEnabled,
        'food_scope': _foodAdsScope,
        'food_categories': _selectedFoodCategories.toList(),
        'org_enabled': _organizationsEnabled,
        'org_scope': _organizationsScope,
        'org_kinds': _selectedOrganizationKinds.toList(),
        'public_distance_km': _publicDistanceLimitKm,
      },
    };

    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(data: payload),
      );
    } catch (_) {
      // non-blocking
    }
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
          .filter('recipient_id', 'eq', uid)
          .isFilter('read_at', null);

      if (!mounted) return;
      setState(() => _unreadNotifs = (rows as List).length);
    } catch (_) {
      // badge not critical
    }
  }

  void _subscribeUnreadNotifsRealtime() {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;

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
          callback: (_) {
            if (mounted) setState(() => _unreadNotifs = _unreadNotifs + 1);

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
                  color: const Color(0xFFD92D20),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.surface,
                    width: 1.2,
                  ),
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
    final ch = _notifChannel;
    _notifChannel = null;
    if (ch != null) {
      await Supabase.instance.client.removeChannel(ch);
    }
  }

  // -----------------------------
  // Feed load (reset + paginate)
  // -----------------------------

  String _intentLabel(String? intent) {
    switch (intent) {
      case 'buying':
        return 'Buying';
      case 'selling':
        return 'Selling';
      default:
        return (intent ?? '').trim();
    }
  }

  bool _matchesMarketIntent(Post post, String intent) {
    final declaredIntent = post.marketIntent;
    if (declaredIntent == 'buying' || declaredIntent == 'selling') {
      return declaredIntent == intent;
    }

    final text = post.content.toLowerCase();
    if (intent == 'selling') {
      return text.contains('sell') ||
          text.contains('for sale') ||
          text.contains('wts');
    }

    if (intent == 'buying') {
      return text.contains('buy') ||
          text.contains('looking for') ||
          text.contains('wtb');
    }

    return true;
  }

  bool _matchesVisibilityScope(Post post, String scope) {
    switch (scope) {
      case 'public':
        return post.visibility == 'public';
      case 'following':
        return post.visibility == 'followers';
      case 'all':
      default:
        return post.visibility == 'public' || post.visibility == 'followers';
    }
  }

  bool _isGeneralPost(Post post) {
    final type = (post.postType ?? '').trim();
    return type.isEmpty || type == 'post';
  }

  bool _isMarketplacePost(Post post) => (post.postType ?? '').trim() == 'market';

  bool _isGigPost(Post post) {
    final type = (post.postType ?? '').trim();
    return type == 'service_offer' || type == 'service_request';
  }

  bool _isLostFoundPost(Post post) => (post.postType ?? '').trim() == 'lost_found';

  bool _isFoodPost(Post post) {
    final type = (post.postType ?? '').trim();
    return type == 'food_ad' || type == 'food';
  }

  bool _matchesMarketplaceFilters(Post post) {
    if (!_isMarketplacePost(post) || !_matchesVisibilityScope(post, _marketplaceScope)) {
      return false;
    }

    if (_selectedMarketplaceCategories.isEmpty) {
      return false;
    }

    if (_selectedMarketplaceIntents.isNotEmpty &&
        !_selectedMarketplaceIntents.any((intent) => _matchesMarketIntent(post, intent))) {
      return false;
    }

    final category = (post.marketCategory ?? '').trim();
    if (!_selectedMarketplaceCategories.contains(category)) return false;

    return true;
  }

  bool _matchesGigFilters(Post post) {
    if (!_isGigPost(post) || !_matchesVisibilityScope(post, _gigsScope)) {
      return false;
    }

    if (_selectedGigCategories.isEmpty) {
      return false;
    }

    if (_selectedGigTypes.isNotEmpty &&
        !_selectedGigTypes.contains((post.postType ?? '').trim())) {
      return false;
    }

    final category = (post.marketCategory ?? '').trim();
    if (!_selectedGigCategories.contains(category)) return false;

    return true;
  }

  bool _matchesSelectedFilters(Post post) {
    final myId = Supabase.instance.client.auth.currentUser?.id;
    if (myId != null && post.userId == myId) {
      return true;
    }

    var matchedSection = false;

    if (_generalPostsEnabled &&
        _isGeneralPost(post) &&
        _matchesVisibilityScope(post, _generalPostsScope)) {
      matchedSection = true;
    }

    if (!matchedSection && _marketplaceEnabled && _matchesMarketplaceFilters(post)) {
      matchedSection = true;
    }

    if (!matchedSection && _gigsEnabled && _matchesGigFilters(post)) {
      matchedSection = true;
    }

    if (!matchedSection &&
        _lostFoundEnabled &&
        _isLostFoundPost(post) &&
        _matchesVisibilityScope(post, _lostFoundScope)) {
      matchedSection = true;
    }

    if (!matchedSection &&
        _foodAdsEnabled &&
        _isFoodPost(post) &&
        _matchesVisibilityScope(post, _foodAdsScope)) {
      if (_selectedFoodCategories.isNotEmpty) {
        matchedSection = _selectedFoodCategories.contains((post.marketCategory ?? '').trim());
      }
    }

    if (_organizationsEnabled &&
        !matchedSection &&
        (post.authorType ?? '').trim() == 'org' &&
        _matchesVisibilityScope(post, _organizationsScope) &&
        _isGeneralPost(post)) {
      if (_selectedOrganizationKinds.isNotEmpty) {
        final orgKind = ((post.authorOrgKind ?? _authorOrgKinds[post.userId]) ?? '').trim();
        matchedSection = orgKind.isEmpty || _selectedOrganizationKinds.contains(orgKind);
      }
    }

    if (!matchedSection) return false;

    if (_publicDistanceLimitKm != null && (post.visibility ?? 'public') == 'public') {
      final distance = post.distanceKm;
      if (distance == null || distance > _publicDistanceLimitKm!) {
        return false;
      }
    }

    return true;
  }

  Future<void> _load({required bool reset}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
        _posts = [];
        _hasMore = true;
        _loadingMore = false;
        _cursorCreatedAt = null;
        _cursorId = null;
      });
    } else {
      setState(() => _loadingMore = true);
    }

    try {
      final service = PostService(Supabase.instance.client);

      final raw = await service.fetchPublicFeed(
        scope: 'all',
        postType: 'all',
        authorType: 'all',
        limit: _pageSize,
        beforeCreatedAt: _cursorCreatedAt,
        beforeId: _cursorId,
      );

      final me = Supabase.instance.client.auth.currentUser?.id;
      List<Map<String, dynamic>> ownRows = const [];
      List<Map<String, dynamic>> followedRows = const [];
      List<Map<String, dynamic>> orgRows = const [];
      _followingIds.clear();
      _followerIds.clear();
      _mutualConnectionIds.clear();
      if (me != null) {
        var ownQuery = Supabase.instance.client
            .from('posts')
            .select(PostService.postSelect)
            .eq('user_id', me);

        if (_cursorCreatedAt != null) {
          final ts = _cursorCreatedAt!.toIso8601String();
          if (_cursorId != null && _cursorId!.isNotEmpty) {
            ownQuery = ownQuery.or(
              'created_at.lt.$ts,and(created_at.eq.$ts,id.lt.$_cursorId)',
            );
          } else {
            ownQuery = ownQuery.lt('created_at', ts);
          }
        }

        final ownData = await ownQuery
            .order('created_at', ascending: false)
            .order('id', ascending: false)
            .limit(_pageSize);
        ownRows = (ownData as List).cast<Map<String, dynamic>>();

        final followed = await Supabase.instance.client
            .from('follows')
            .select('followed_profile_id')
            .eq('follower_id', me)
            .eq('status', 'accepted');

        final followedIds = (followed as List)
            .map((e) => e['followed_profile_id'] as String?)
            .whereType<String>()
            .toSet()
            .toList();
        _followingIds
          ..clear()
          ..addAll(followedIds);

        final followers = await Supabase.instance.client
            .from('follows')
            .select('follower_id')
            .eq('followed_profile_id', me)
            .eq('status', 'accepted');

        final followerIds = (followers as List)
            .map((e) => e['follower_id'] as String?)
            .whereType<String>()
            .toSet();

        _followerIds
          ..clear()
          ..addAll(followerIds);
        _mutualConnectionIds
          ..clear()
          ..addAll(_followingIds.intersection(_followerIds));

        if (followedIds.isNotEmpty) {
          var followedQuery = Supabase.instance.client
              .from('posts')
              .select(PostService.postSelect)
              .inFilter('user_id', followedIds);

          if (_cursorCreatedAt != null) {
            final ts = _cursorCreatedAt!.toIso8601String();
            if (_cursorId != null && _cursorId!.isNotEmpty) {
              followedQuery = followedQuery.or(
                'created_at.lt.$ts,and(created_at.eq.$ts,id.lt.$_cursorId)',
              );
            } else {
              followedQuery = followedQuery.lt('created_at', ts);
            }
          }

          final followedData = await followedQuery
              .order('created_at', ascending: false)
              .order('id', ascending: false)
              .limit(_pageSize);
          followedRows = (followedData as List).cast<Map<String, dynamic>>();
        }
      }

      if (_organizationsEnabled) {
        dynamic orgQuery = Supabase.instance.client
            .from('posts')
            .select(PostService.postSelect)
            .eq('author_profile_type', 'org');

        if (_organizationsScope == 'public') {
          orgQuery = orgQuery.eq('visibility', 'public');
        } else if (_organizationsScope == 'following') {
          if (me == null) {
            orgRows = const [];
            orgQuery = null;
          } else {
          final followed = await Supabase.instance.client
              .from('follows')
              .select('followed_profile_id')
              .eq('follower_id', me)
              .eq('status', 'accepted');
          final ids = (followed as List)
              .map((e) => e['followed_profile_id'] as String?)
              .whereType<String>()
              .toSet()
              .toList();
          if (!ids.contains(me)) ids.add(me);
          if (ids.isEmpty) {
            orgRows = const [];
            orgQuery = null;
          } else {
            orgQuery = orgQuery.inFilter('user_id', ids);
          }
          }
        } else {
          orgQuery = orgQuery.inFilter('visibility', ['public', 'followers']);
        }

        if (orgQuery != null && _cursorCreatedAt != null) {
          final ts = _cursorCreatedAt!.toIso8601String();
          if (_cursorId != null && _cursorId!.isNotEmpty) {
            orgQuery = orgQuery.or(
              'created_at.lt.$ts,and(created_at.eq.$ts,id.lt.$_cursorId)',
            );
          } else {
            orgQuery = orgQuery.lt('created_at', ts);
          }
        }

        if (orgQuery != null) {
          final orgData = await orgQuery
              .order('created_at', ascending: false)
              .order('id', ascending: false)
              .limit(_pageSize);
          orgRows = (orgData as List).cast<Map<String, dynamic>>();
        }
      }

      final mergedRaw = <Map<String, dynamic>>[];
      final seenIds = <String>{};
      for (final row in [...raw, ...ownRows, ...followedRows, ...orgRows]) {
        final id = (row['id'] ?? '').toString();
        if (id.isEmpty || !seenIds.add(id)) continue;
        mergedRaw.add(row);
      }
      mergedRaw.sort((a, b) {
        final aCreated = DateTime.tryParse((a['created_at'] ?? '').toString()) ?? DateTime(1970);
        final bCreated = DateTime.tryParse((b['created_at'] ?? '').toString()) ?? DateTime(1970);
        final timeCompare = bCreated.compareTo(aCreated);
        if (timeCompare != 0) return timeCompare;
        return ((b['id'] ?? '').toString()).compareTo((a['id'] ?? '').toString());
      });

      final hydratedRows = await service.attachSharedPosts(mergedRaw);
      final fetchedPosts = hydratedRows.map((e) => Post.fromMap(e)).toList();
      await _loadAuthorBadges(fetchedPosts);
      final incoming = fetchedPosts.where(_matchesSelectedFilters).toList();

      // If backend returned fewer than a page, no more pages
      final gotFullPage = mergedRaw.length >= _pageSize;
      if (!gotFullPage) _hasMore = false;

      // Update cursor from the oldest item returned by backend
      if (fetchedPosts.isNotEmpty) {
        final last = fetchedPosts.last;
        _cursorCreatedAt = last.createdAt;
        _cursorId = last.id;
      }

      // De-dupe by id (safe with realtime inserts)
      final existingIds = _posts.map((p) => p.id).toSet();
      final merged = <Post>[
        ..._posts,
        ...incoming.where((p) => !existingIds.contains(p.id)),
      ];

      if (!mounted) return;
      setState(() {
        _posts = merged;
        _error = null;
      });
      await _loadSidebarData();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore) return;
    await _load(reset: false);
  }

  // ✅ Likes + comments row
  Widget _buildReactionsRow(Post p) {
    final type = (p.postType ?? '').trim();
    final isMarketplacePost = type == 'market';
    final isGigPost = type == 'service_offer' || type == 'service_request';
    final react = ReactionService(Supabase.instance.client);
    final postService = PostService(Supabase.instance.client);

    if (isMarketplacePost || isGigPost) {
      return FutureBuilder<int>(
        future: react.commentsCount(p.id),
        builder: (context, snap) {
          final qaCount = snap.hasData ? snap.data! : 0;
          final qaRoute = isMarketplacePost
              ? '/marketplace/product/${p.id}?tab=qa'
              : '/gigs/service/${p.id}?tab=qa';
          return Row(
            children: [
              TextButton.icon(
                onPressed: () => context.push(qaRoute),
                icon: const Icon(Icons.forum_outlined),
                label: Text('Q&A $qaCount'),
              ),
              if (_canSharePost(p)) ...[
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () async {
                    try {
                      await postService.sharePost(
                        originalPostId: p.id,
                        originalAuthorId: p.userId,
                        originalVisibility: p.visibility,
                        originalLatitude: p.latitude,
                        originalLongitude: p.longitude,
                        originalLocationName: p.locationName,
                      );
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Post shared')),
                      );
                      await _load(reset: true);
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Share error: $e')),
                      );
                    }
                  },
                  icon: const Icon(Icons.share_outlined),
                  label: const Text('Share'),
                ),
              ],
            ],
          );
        },
      );
    }

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
            if (_canSharePost(p)) ...[
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: () async {
                  try {
                    await postService.sharePost(
                      originalPostId: p.id,
                      originalAuthorId: p.userId,
                      originalVisibility: p.visibility,
                      originalLatitude: p.latitude,
                      originalLongitude: p.longitude,
                      originalLocationName: p.locationName,
                    );
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Post shared')),
                    );
                    await _load(reset: true);
                  } catch (e) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Share error: $e')),
                    );
                  }
                },
                icon: const Icon(Icons.share_outlined),
                label: const Text('Share'),
              ),
            ],
          ],
        );
      },
    );
  }

  bool _canSharePost(Post post) {
    final me = Supabase.instance.client.auth.currentUser?.id;
    if (me == null) return false;
    if ((post.sharedPostId ?? '').isNotEmpty) return false;
    if (post.userId == me) return false;

    switch (post.shareScope) {
      case 'public':
        return true;
      case 'followers':
        return _followingIds.contains(post.userId);
      case 'connections':
        return _mutualConnectionIds.contains(post.userId);
      default:
        return false;
    }
  }

  String? _getAuthorBadgeType(Post post) {
    return _authorBadgeLabels[post.userId];
  }

  Future<void> _loadAuthorBadges(List<Post> posts) async {
    final ids = posts.map((p) => p.userId).toSet().toList();

    if (ids.isEmpty) {
      if (!mounted) return;
      setState(() {
        _authorBadgeLabels.clear();
        _authorLocationLabels.clear();
      });
      return;
    }

    try {
      final rows = await Supabase.instance.client
          .from('profiles')
          .select(
            'id, profile_type, account_type, org_kind, is_restaurant, restaurant_type, business_type, city, zipcode',
          )
          .inFilter('id', ids);

      final labels = <String, String>{};
      final locations = <String, String>{};
      final orgKinds = <String, String>{};
      for (final row in (rows as List).cast<Map<String, dynamic>>()) {
        final id = (row['id'] ?? '').toString();
        if (id.isEmpty) continue;

        final city = (row['city'] ?? '').toString().trim();
        final zipcode = (row['zipcode'] ?? '').toString().trim();
        final location = city.isNotEmpty ? city : zipcode;
        if (location.isNotEmpty) {
          locations[id] = location;
        }

        final type =
            ((row['profile_type'] ?? row['account_type']) ?? '').toString();

        final orgKind = (row['org_kind'] ?? '').toString().trim();
        if (orgKind.isNotEmpty) {
          orgKinds[id] = orgKind;
        }

        if (type == 'org') {
          labels[id] = 'ORGANIZATION';
          continue;
        }

        if (type != 'business') continue;

        final isRestaurant = row['is_restaurant'] == true;
        if (isRestaurant) {
          final restaurantType = (row['restaurant_type'] ?? '').toString();
          labels[id] = restaurantType.isNotEmpty
              ? restaurantCategoryLabel(restaurantType)
              : 'Restaurant';
          continue;
        }

        final businessType = (row['business_type'] ?? '').toString();
        labels[id] = businessType.isNotEmpty
            ? businessCategoryLabel(businessType)
            : 'Business';
      }

      if (!mounted) return;
      setState(() {
        _authorBadgeLabels
          ..clear()
          ..addAll(labels);
        _authorLocationLabels
          ..clear()
          ..addAll(locations);
        _authorOrgKinds
          ..clear()
          ..addAll(orgKinds);
      });
    } catch (_) {
      // Badge enrichment is optional. Keep existing feed if this fails.
    }
  }

  Future<void> _loadSidebarData() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;

    try {
      final results = await Future.wait<dynamic>([
        Supabase.instance.client
            .from('profiles')
            .select(
              'id, full_name, bio, avatar_url, zipcode, city, latitude, longitude, profile_type',
            )
            .eq('id', uid)
            .maybeSingle(),
        Supabase.instance.client.rpc('get_offer_chat_list'),
        Supabase.instance.client
            .from('posts')
            .select('id, content, market_title, post_type, image_url')
            .eq('visibility', 'public')
            .order('created_at', ascending: false)
            .limit(12),
      ]);

      final profile = results[0] as Map<String, dynamic>?;
      final offerRows = (results[1] as List).cast<Map<String, dynamic>>();
      final topPostRows = (results[2] as List).cast<Map<String, dynamic>>();
      final pendingOffers = offerRows
          .where((row) => (row['current_offer_status'] ?? '') == 'pending')
          .length;
      final unreadOffers = offerRows.fold<int>(
        0,
        (sum, row) => sum + (((row['unread_count'] as num?)?.toInt()) ?? 0),
      );
      final react = ReactionService(Supabase.instance.client);
      final ranked = <Map<String, dynamic>>[];
      for (final row in topPostRows) {
        final id = (row['id'] ?? '').toString();
        if (id.isEmpty) continue;
        final likes = await react.likesCount(id);
        final comments = await react.commentsCount(id);
        ranked.add({
          ...row,
          'engagement': likes + comments,
        });
      }
      ranked.sort((a, b) => ((b['engagement'] as int?) ?? 0).compareTo((a['engagement'] as int?) ?? 0));

      if (!mounted) return;
      setState(() {
        _myProfileSummary = profile;
        _profileCompleteness = _calculateProfileCompleteness(profile);
        _pendingOfferConversations = pendingOffers;
        _unreadOfferMessages = unreadOffers;
        _topPosts = ranked.take(10).toList();
      });
    } catch (_) {
      // Sidebar enrichment is optional.
    }
  }

  int _calculateProfileCompleteness(Map<String, dynamic>? profile) {
    if (profile == null) return 0;
    final checks = <bool>[
      (profile['full_name'] ?? '').toString().trim().isNotEmpty,
      (profile['bio'] ?? '').toString().trim().isNotEmpty,
      (profile['avatar_url'] ?? '').toString().trim().isNotEmpty,
      (profile['zipcode'] ?? '').toString().trim().isNotEmpty,
      (profile['city'] ?? '').toString().trim().isNotEmpty,
      profile['latitude'] != null,
      profile['longitude'] != null,
      (profile['profile_type'] ?? '').toString().trim().isNotEmpty,
    ];
    final filled = checks.where((v) => v).length;
    return ((filled / checks.length) * 100).round();
  }

  bool _isPrivateListing(Post post) {
    return post.postType == 'market' ||
        post.postType == 'service_offer' ||
        post.postType == 'service_request';
  }

  String _feedHeaderLabel(Post post) {
    switch (post.postType) {
      case 'market':
        return 'Marketplace listing';
      case 'service_offer':
        return 'Service offer';
      case 'service_request':
        return 'Service request';
      default:
        return post.authorName ?? 'Unknown';
    }
  }

  String? _detailRouteForPost(Post post) {
    switch (post.postType) {
      case 'market':
        return '/marketplace/product/${post.id}';
      case 'service_offer':
      case 'service_request':
        return '/gigs/service/${post.id}';
      case 'food_ad':
      case 'food':
        return '/foods/${post.id}';
      default:
        return null;
    }
  }

  Widget _buildFilters() {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFFFCF7), Color(0xFFF1E9D8)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFE6DDCE)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x12000000),
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Discover nearby',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _feedWhatShowing(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: _openFilterSheet,
                  icon: const Icon(Icons.tune_rounded, size: 18),
                  label: const Text('Filters'),
                ),
                FilledButton.icon(
                  onPressed: () async {
                    final res = await context.push('/create-post');
                    if (!mounted) return;
                    if (res == true) _load(reset: true);
                  },
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Post'),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildQuickLinkButton(
                  icon: Icons.storefront_outlined,
                  label: 'Marketplace',
                  onPressed: () => context.push('/marketplace'),
                ),
                _buildQuickLinkButton(
                  icon: Icons.miscellaneous_services_outlined,
                  label: 'Gigs',
                  onPressed: () => context.push('/gigs'),
                ),
                _buildQuickLinkButton(
                  icon: Icons.fastfood,
                  label: 'Foods',
                  onPressed: () => context.push('/foods'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildQuickLinkButton(
                  icon: Icons.business,
                  label: 'Businesses',
                  onPressed: () => context.push('/businesses'),
                ),
                _buildQuickLinkButton(
                  icon: Icons.restaurant_menu,
                  label: 'Restaurants',
                  onPressed: () => context.push('/restaurants'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeedSummaryBanner() {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFFFCF7), Color(0xFFF4EBDD)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFE6DDCE)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x12000000),
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFF0F766E).withOpacity(0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.radar_outlined,
                color: Color(0xFF0F766E),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Current feed view',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: const Color(0xFF0F766E),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _feedWhatShowing(),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openFilterSheet() async {
    var draftGeneralEnabled = _generalPostsEnabled;
    var draftGeneralScope = _generalPostsScope;
    var draftMarketplaceEnabled = _marketplaceEnabled;
    var draftMarketplaceScope = _marketplaceScope;
    final draftMarketplaceIntents = {..._selectedMarketplaceIntents};
    final draftMarketplaceCategories = {..._selectedMarketplaceCategories};
    var draftGigsEnabled = _gigsEnabled;
    var draftGigsScope = _gigsScope;
    final draftGigTypes = {..._selectedGigTypes};
    final draftGigCategories = {..._selectedGigCategories};
    var draftLostFoundEnabled = _lostFoundEnabled;
    var draftLostFoundScope = _lostFoundScope;
    var draftFoodAdsEnabled = _foodAdsEnabled;
    var draftFoodAdsScope = _foodAdsScope;
    final draftFoodCategories = {..._selectedFoodCategories};
    var draftOrganizationsEnabled = _organizationsEnabled;
    var draftOrganizationsScope = _organizationsScope;
    final draftOrganizationKinds = {..._selectedOrganizationKinds};
    int? draftPublicDistanceLimitKm = _publicDistanceLimitKm;
    bool hasInvalidRequiredSelections() {
      return (draftMarketplaceEnabled && draftMarketplaceCategories.isEmpty) ||
          (draftGigsEnabled && draftGigCategories.isEmpty) ||
          (draftFoodAdsEnabled && draftFoodCategories.isEmpty) ||
          (draftOrganizationsEnabled && draftOrganizationKinds.isEmpty);
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  12,
                  12,
                  12,
                  MediaQuery.of(context).viewInsets.bottom + 12,
                ),
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                      Center(
                        child: Container(
                          width: 42,
                          height: 4,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.outlineVariant,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Feed filters',
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              setSheetState(() {
                                draftGeneralEnabled = true;
                                draftGeneralScope = 'all';
                                draftMarketplaceEnabled = true;
                                draftMarketplaceScope = 'all';
                                draftMarketplaceIntents
                                  ..clear()
                                  ..addAll({'buying', 'selling'});
                                draftMarketplaceCategories.clear();
                                draftGigsEnabled = true;
                                draftGigsScope = 'all';
                                draftGigTypes
                                  ..clear()
                                  ..addAll({'service_offer', 'service_request'});
                                draftGigCategories.clear();
                                draftLostFoundEnabled = true;
                                draftLostFoundScope = 'all';
                                draftFoodAdsEnabled = true;
                                draftFoodAdsScope = 'all';
                                draftFoodCategories.clear();
                                draftOrganizationsEnabled = false;
                                draftOrganizationsScope = 'all';
                                draftOrganizationKinds.clear();
                                draftPublicDistanceLimitKm = null;
                              });
                            },
                            child: const Text('Reset'),
                          ),
                          IconButton(
                            tooltip: 'Close',
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _buildFilterSectionCard(
                        title: 'General posts',
                        subtitle: 'Normal feed posts only.',
                        enabled: draftGeneralEnabled,
                        onEnabledChanged: (value) {
                          setSheetState(() => draftGeneralEnabled = value);
                        },
                        child: _buildScopeChips(
                          selected: draftGeneralScope,
                          onSelected: (value) {
                            setSheetState(() => draftGeneralScope = value);
                          },
                        ),
                      ),
                      const SizedBox(height: 10),
                      _buildFilterSectionCard(
                        title: 'Marketplace posts',
                        subtitle: 'Buying, selling, and product categories.',
                        enabled: draftMarketplaceEnabled,
                        onEnabledChanged: (value) {
                          setSheetState(() => draftMarketplaceEnabled = value);
                        },
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildScopeChips(
                              selected: draftMarketplaceScope,
                              onSelected: (value) {
                                setSheetState(() => draftMarketplaceScope = value);
                              },
                            ),
                            const SizedBox(height: 12),
                            _buildMultiSelectSection(
                              title: 'Marketplace type',
                              options: const [
                                ('buying', 'Buying'),
                                ('selling', 'Selling'),
                              ],
                              selected: draftMarketplaceIntents,
                              setSheetState: setSheetState,
                            ),
                            const SizedBox(height: 12),
                            _buildMultiSelectSection(
                              title: 'Marketplace categories',
                              options: marketMainCategories
                                  .map((c) => (c, marketCategoryLabel(c)))
                                  .toList(),
                              selected: draftMarketplaceCategories,
                              setSheetState: setSheetState,
                            ),
                            if (draftMarketplaceCategories.isEmpty) ...[
                              const SizedBox(height: 8),
                              _buildFilterWarning('Select at least one category.'),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      _buildFilterSectionCard(
                        title: 'Gig posts',
                        subtitle: 'Service offers, requests, and service categories.',
                        enabled: draftGigsEnabled,
                        onEnabledChanged: (value) {
                          setSheetState(() => draftGigsEnabled = value);
                        },
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildScopeChips(
                              selected: draftGigsScope,
                              onSelected: (value) {
                                setSheetState(() => draftGigsScope = value);
                              },
                            ),
                            const SizedBox(height: 12),
                            _buildMultiSelectSection(
                              title: 'Gig type',
                              options: const [
                                ('service_offer', 'Offering'),
                                ('service_request', 'Requesting'),
                              ],
                              selected: draftGigTypes,
                              setSheetState: setSheetState,
                            ),
                            const SizedBox(height: 12),
                            _buildMultiSelectSection(
                              title: 'Service categories',
                              options: serviceMainCategories
                                  .map((c) => (c, serviceCategoryLabel(c)))
                                  .toList(),
                              selected: draftGigCategories,
                              setSheetState: setSheetState,
                            ),
                            if (draftGigCategories.isEmpty) ...[
                              const SizedBox(height: 8),
                              _buildFilterWarning('Select at least one category.'),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      _buildFilterSectionCard(
                        title: 'Lost & found',
                        subtitle: 'Show or hide lost-and-found posts.',
                        enabled: draftLostFoundEnabled,
                        onEnabledChanged: (value) {
                          setSheetState(() => draftLostFoundEnabled = value);
                        },
                        child: _buildScopeChips(
                          selected: draftLostFoundScope,
                          onSelected: (value) {
                            setSheetState(() => draftLostFoundScope = value);
                          },
                        ),
                      ),
                      const SizedBox(height: 10),
                      _buildFilterSectionCard(
                        title: 'Food ads',
                        subtitle: 'Food posts with separate food categories.',
                        enabled: draftFoodAdsEnabled,
                        onEnabledChanged: (value) {
                          setSheetState(() => draftFoodAdsEnabled = value);
                        },
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildScopeChips(
                              selected: draftFoodAdsScope,
                              onSelected: (value) {
                                setSheetState(() => draftFoodAdsScope = value);
                              },
                            ),
                            const SizedBox(height: 12),
                            _buildMultiSelectSection(
                              title: 'Food categories',
                              options: foodMainCategories
                                  .map((c) => (c, foodCategoryLabel(c)))
                                  .toList(),
                              selected: draftFoodCategories,
                              setSheetState: setSheetState,
                            ),
                            if (draftFoodCategories.isEmpty) ...[
                              const SizedBox(height: 8),
                              _buildFilterWarning('Select at least one category.'),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      _buildFilterSectionCard(
                        title: 'Organizations',
                        subtitle: 'Show organization posts by subtype.',
                        enabled: draftOrganizationsEnabled,
                        onEnabledChanged: (value) {
                          setSheetState(() => draftOrganizationsEnabled = value);
                        },
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildScopeChips(
                              selected: draftOrganizationsScope,
                              onSelected: (value) {
                                setSheetState(() => draftOrganizationsScope = value);
                              },
                            ),
                            const SizedBox(height: 12),
                            _buildMultiSelectSection(
                              title: 'Organization types',
                              options: const [
                                ('government', 'Government'),
                                ('nonprofit', 'Non-profit'),
                                ('news_agency', 'News agency'),
                              ],
                              selected: draftOrganizationKinds,
                              setSheetState: setSheetState,
                            ),
                            if (draftOrganizationKinds.isEmpty) ...[
                              const SizedBox(height: 8),
                              _buildFilterWarning('Select at least one type.'),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: const Color(0xFFE6DDCE)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Public distance',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'This only limits public posts. Local posts keep using their own visibility rules.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _buildDistanceChip(
                                  label: 'Any distance',
                                  selected: draftPublicDistanceLimitKm == null,
                                  onTap: () => setSheetState(() => draftPublicDistanceLimitKm = null),
                                ),
                                for (final km in const [5, 10, 20, 50, 100])
                                  _buildDistanceChip(
                                    label: '$km km',
                                    selected: draftPublicDistanceLimitKm == km,
                                    onTap: () => setSheetState(() => draftPublicDistanceLimitKm = km),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: hasInvalidRequiredSelections()
                              ? null
                              : () {
                            Navigator.of(context).pop();
                            setState(() {
                              _generalPostsEnabled = draftGeneralEnabled;
                              _generalPostsScope = draftGeneralScope;
                              _marketplaceEnabled = draftMarketplaceEnabled;
                              _marketplaceScope = draftMarketplaceScope;
                              _selectedMarketplaceIntents
                                ..clear()
                                ..addAll(draftMarketplaceIntents);
                              _selectedMarketplaceCategories
                                ..clear()
                                ..addAll(draftMarketplaceCategories);
                              _gigsEnabled = draftGigsEnabled;
                              _gigsScope = draftGigsScope;
                              _selectedGigTypes
                                ..clear()
                                ..addAll(draftGigTypes);
                              _selectedGigCategories
                                ..clear()
                                ..addAll(draftGigCategories);
                              _lostFoundEnabled = draftLostFoundEnabled;
                              _lostFoundScope = draftLostFoundScope;
                              _foodAdsEnabled = draftFoodAdsEnabled;
                              _foodAdsScope = draftFoodAdsScope;
                              _selectedFoodCategories
                                ..clear()
                                ..addAll(draftFoodCategories);
                              _organizationsEnabled = draftOrganizationsEnabled;
                              _organizationsScope = draftOrganizationsScope;
                              _selectedOrganizationKinds
                                ..clear()
                                ..addAll(draftOrganizationKinds);
                              _publicDistanceLimitKm = draftPublicDistanceLimitKm;
                            });
                            _saveFilters();
                            _load(reset: true);
                          },
                          child: const Text('Apply filters'),
                        ),
                      ),
                    ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _sectionScopeLabel(String value) {
    switch (value) {
      case 'public':
        return 'Public';
      case 'following':
        return 'Following';
      case 'all':
      default:
        return 'Public + Following';
    }
  }

  String _feedWhatShowing() {
    final sections = <String>[];
    if (_generalPostsEnabled) {
      sections.add('general posts (${_sectionScopeLabel(_generalPostsScope).toLowerCase()})');
    }
    if (_marketplaceEnabled) {
      final intentText = _selectedMarketplaceIntents.isEmpty
          ? 'all marketplace posts'
          : _selectedMarketplaceIntents.map(_intentLabel).join(' & ').toLowerCase();
      final categoryText = _selectedMarketplaceCategories.isEmpty
          ? 'no categories selected'
          : _selectedMarketplaceCategories.map(marketCategoryLabel).join(', ');
      sections.add(
        '$intentText in $categoryText (${_sectionScopeLabel(_marketplaceScope).toLowerCase()})',
      );
    }
    if (_gigsEnabled) {
      final gigText = _selectedGigTypes.isEmpty
          ? 'all gigs'
          : _selectedGigTypes.map(_postTypeLabel).join(' & ').toLowerCase();
      final categoryText = _selectedGigCategories.isEmpty
          ? 'no categories selected'
          : _selectedGigCategories.map(serviceCategoryLabel).join(', ');
      sections.add(
        'gigs $gigText in $categoryText (${_sectionScopeLabel(_gigsScope).toLowerCase()})',
      );
    }
    if (_lostFoundEnabled) {
      sections.add('lost & found (${_sectionScopeLabel(_lostFoundScope).toLowerCase()})');
    }
    if (_foodAdsEnabled) {
      final categoryText = _selectedFoodCategories.isEmpty
          ? 'no categories selected'
          : _selectedFoodCategories.map(foodCategoryLabel).join(', ');
      sections.add(
        'food ads in $categoryText (${_sectionScopeLabel(_foodAdsScope).toLowerCase()})',
      );
    }
    if (_organizationsEnabled) {
      final orgText = _selectedOrganizationKinds.isEmpty
          ? 'all organization posts'
          : _selectedOrganizationKinds.map(_organizationKindLabel).join(', ').toLowerCase();
      sections.add('$orgText (${_sectionScopeLabel(_organizationsScope).toLowerCase()})');
    }

    final postText = sections.isEmpty ? 'no sections selected' : sections.join(' • ');
    if (_publicDistanceLimitKm != null) {
      sections.add('public posts within ${_publicDistanceLimitKm} km');
    }
    return 'You are seeing ${sections.isEmpty ? 'no sections selected' : sections.join(' • ')}';
  }

  String _postTypeLabel(String value) {
    switch (value) {
      case 'service_offer':
        return 'offering';
      case 'service_request':
        return 'requesting';
      case 'lost_found':
        return 'Lost & found';
      case 'food_ad':
        return 'Food ad';
      default:
        return value;
    }
  }

  String _organizationKindLabel(String value) {
    switch (value) {
      case 'government':
        return 'Government';
      case 'nonprofit':
        return 'Non-profit';
      case 'news_agency':
        return 'News agency';
      default:
        return value;
    }
  }

  Widget _buildDistanceChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      showCheckmark: false,
      selectedColor: const Color(0xFF0F766E).withValues(alpha: 0.14),
      side: BorderSide(
        color: selected ? const Color(0xFF0F766E) : const Color(0xFFE6DDCE),
      ),
      labelStyle: TextStyle(
        fontWeight: FontWeight.w700,
        color: selected ? const Color(0xFF0F766E) : null,
      ),
    );
  }

  Widget _buildFilterWarning(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4E5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF5C26B)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Color(0xFF9A6700),
        ),
      ),
    );
  }

  Widget _buildFilterSectionCard({
    required String title,
    required String subtitle,
    required bool enabled,
    required ValueChanged<bool> onEnabledChanged,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE6DDCE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
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
              Switch.adaptive(
                value: enabled,
                onChanged: onEnabledChanged,
              ),
            ],
          ),
          if (enabled) ...[
            const SizedBox(height: 12),
            child,
          ],
        ],
      ),
    );
  }

  Widget _buildScopeChips({
    required String selected,
    required ValueChanged<String> onSelected,
  }) {
    const options = [
      ('all', 'Public + Following'),
      ('public', 'Public'),
      ('following', 'Following'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 6),
          child: Text(
            'Visibility',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options.map((entry) {
            final isSelected = selected == entry.$1;
            return ChoiceChip(
              selected: isSelected,
              label: Text(entry.$2),
              onSelected: (_) => onSelected(entry.$1),
              showCheckmark: false,
              backgroundColor: const Color(0xFFF8F3E8),
              selectedColor: const Color(0xFFE7F4EF),
              side: BorderSide(
                color: isSelected ? const Color(0xFF0F766E) : const Color(0xFFE0D5C2),
              ),
              labelStyle: TextStyle(
                fontWeight: FontWeight.w700,
                color: isSelected ? const Color(0xFF0F766E) : const Color(0xFF3F3426),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildMultiSelectSection({
    required String title,
    required List<(String, String)> options,
    required Set<String> selected,
    required void Function(void Function()) setSheetState,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(
            title,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options.map((entry) {
            final value = entry.$1;
            final label = entry.$2;
            final isSelected = selected.contains(value);
            return FilterChip(
              selected: isSelected,
              label: Text(label),
              showCheckmark: false,
              backgroundColor: const Color(0xFFF8F3E8),
              selectedColor: const Color(0xFFE7F4EF),
              side: BorderSide(
                color: isSelected ? const Color(0xFF0F766E) : const Color(0xFFE0D5C2),
              ),
              labelStyle: TextStyle(
                fontWeight: FontWeight.w700,
                color: isSelected ? const Color(0xFF0F766E) : const Color(0xFF3F3426),
              ),
              onSelected: (_) {
                setSheetState(() {
                  if (isSelected) {
                    selected.remove(value);
                  } else {
                    selected.add(value);
                  }
                });
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildQuickLinkButton({
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

  Widget _buildFeedMetaText(String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        color: Theme.of(context).hintColor,
      ),
    );
  }

  Widget _buildSidebarQuickLink({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: 18),
          label: Align(
            alignment: Alignment.centerLeft,
            child: Text(label),
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopSidebar() {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 18, 16, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFFFCF7), Color(0xFFF1E9D8)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: const Color(0xFFE6DDCE)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Feed controls',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    onPressed: _openFilterSheet,
                    icon: const Icon(Icons.tune_rounded),
                    label: const Text('Open filters'),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () async {
                      final res = await context.push('/create-post');
                      if (!mounted) return;
                      if (res == true) _load(reset: true);
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Post to feed'),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                    child: TextButton.icon(
                      onPressed: () {
                        setState(() {
                          _generalPostsEnabled = true;
                          _generalPostsScope = 'all';
                          _marketplaceEnabled = true;
                          _marketplaceScope = 'all';
                          _selectedMarketplaceIntents
                            ..clear()
                            ..addAll({'buying', 'selling'});
                          _selectedMarketplaceCategories.clear();
                          _gigsEnabled = true;
                          _gigsScope = 'all';
                          _selectedGigTypes
                            ..clear()
                            ..addAll({'service_offer', 'service_request'});
                          _selectedGigCategories.clear();
                          _lostFoundEnabled = true;
                          _lostFoundScope = 'all';
                          _foodAdsEnabled = true;
                          _foodAdsScope = 'all';
                          _selectedFoodCategories.clear();
                          _organizationsEnabled = false;
                          _organizationsScope = 'all';
                          _selectedOrganizationKinds.clear();
                        });
                        _saveFilters();
                        _load(reset: true);
                      },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Reset feed'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: const Color(0xFFE6DDCE)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Browse sections',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 14),
                _buildSidebarQuickLink(
                  icon: Icons.storefront_outlined,
                  label: 'Marketplace',
                  onPressed: () => context.push('/marketplace'),
                ),
                _buildSidebarQuickLink(
                  icon: Icons.miscellaneous_services_outlined,
                  label: 'Gigs',
                  onPressed: () => context.push('/gigs'),
                ),
                _buildSidebarQuickLink(
                  icon: Icons.fastfood,
                  label: 'Foods',
                  onPressed: () => context.push('/foods'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _buildInfoCard(
            title: 'Local directory',
            child: Column(
              children: [
                _buildTaskRow(
                  icon: Icons.restaurant_menu,
                  title: 'Restaurants',
                  subtitle: 'Browse nearby places to eat.',
                  onTap: () => context.push('/restaurants'),
                ),
                _buildTaskRow(
                  icon: Icons.business,
                  title: 'Businesses',
                  subtitle: 'Explore nearby local businesses.',
                  onTap: () => context.push('/businesses'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard({
    required String title,
    required Widget child,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFE6DDCE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _buildTaskRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.45),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: theme.colorScheme.primary.withOpacity(0.12),
                child: Icon(icon, size: 18, color: theme.colorScheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRightSidebar() {
    final profileName = (_myProfileSummary?['full_name'] ?? 'Your profile')
        .toString();
    final incompleteProfile = _profileCompleteness < 100;
    final unreadChats = unreadBadgeController.unread.value;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 18, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfoCard(
            title: 'Top Trending',
            child: SizedBox(
              height: 420,
              child: _topPosts.isEmpty
                  ? const Center(child: Text('No top posts yet'))
                  : ListView.separated(
                      itemCount: _topPosts.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final post = _topPosts[index];
                        final title = ((post['market_title'] ?? '').toString().trim().isNotEmpty
                                ? post['market_title']
                                : post['content'] ?? 'Post')
                            .toString()
                            .trim();
                        final imageUrl = (post['image_url'] ?? '').toString();
                        final engagement = (post['engagement'] as int?) ?? 0;
                        return InkWell(
                          onTap: () => context.push('/post/${post['id']}'),
                          borderRadius: BorderRadius.circular(18),
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest
                                  .withOpacity(0.45),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Container(
                                    width: 52,
                                    height: 52,
                                    color: Colors.grey.shade200,
                                    padding: const EdgeInsets.all(4),
                                    child: imageUrl.isNotEmpty
                                        ? Image.network(
                                            imageUrl,
                                            fit: BoxFit.contain,
                                            alignment: Alignment.center,
                                          )
                                        : const Icon(Icons.image_outlined, size: 22),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        title.isEmpty ? 'Post' : title,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontWeight: FontWeight.w700),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '$engagement engagement',
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
                        );
                      },
                    ),
            ),
          ),
          const SizedBox(height: 18),
          _buildInfoCard(
            title: 'To do',
            child: Column(
              children: [
                if (_pendingOfferConversations > 0)
                  _buildTaskRow(
                    icon: Icons.local_offer_outlined,
                    title: 'Review offers',
                    subtitle: '$_pendingOfferConversations conversations need attention.',
                    onTap: () => context.push('/chats'),
                  ),
                if (_unreadOfferMessages > 0)
                  _buildTaskRow(
                    icon: Icons.forum_outlined,
                    title: 'Unread offer messages',
                    subtitle: '$_unreadOfferMessages unread messages in offer chats.',
                    onTap: () => context.push('/chats'),
                  ),
                if (_unreadNotifs > 0)
                  _buildTaskRow(
                    icon: Icons.notifications_active_outlined,
                    title: 'Notifications',
                    subtitle: '$_unreadNotifs unread notifications.',
                    onTap: () => context.push('/notifications'),
                  ),
                if (unreadChats > 0)
                  _buildTaskRow(
                    icon: Icons.chat_bubble_outline,
                    title: 'Unread chats',
                    subtitle: '$unreadChats unread conversations.',
                    onTap: () => context.push('/chats'),
                  ),
                if (_pendingOfferConversations == 0 &&
                    _unreadOfferMessages == 0 &&
                    _unreadNotifs == 0 &&
                    unreadChats == 0 &&
                    !incompleteProfile)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest
                          .withOpacity(0.45),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Text(
                      'Nothing pending right now.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (incompleteProfile) ...[
            const SizedBox(height: 18),
            _buildInfoCard(
              title: 'Profile completeness',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profileName,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      minHeight: 10,
                      value: (_profileCompleteness.clamp(0, 100)) / 100,
                      backgroundColor: const Color(0xFFE8E0D1),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$_profileCompleteness% complete',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Add the missing profile details to improve trust and discovery.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => context.push('/profile'),
                      icon: const Icon(Icons.person_outline, size: 18),
                      label: const Text('Open profile'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFeedList({
    required bool showTopFilters,
    required bool showSummaryBanner,
  }) {
    return RefreshIndicator(
      onRefresh: () async {
        await _load(reset: true);
        await _refreshUnreadNotifs();
      },
      child: ListView.builder(
        controller: _scroll,
        itemCount: _posts.length + 2,
        itemBuilder: (_, i) {
          if (showTopFilters) {
            if (i == 0) return _buildFilters();
            if (i == _posts.length + 1) return _buildFooter();
          } else if (showSummaryBanner) {
            if (i == 0) return _buildFeedSummaryBanner();
            if (i == _posts.length + 1) return _buildFooter();
          } else {
            if (i == 0) return const SizedBox(height: 6);
            if (i == _posts.length + 1) return _buildFooter();
          }

          final postIndex = i - 1;
          final p = _posts[postIndex];
          final badgeText = _getAuthorBadgeType(p);
          final isPrivateListing = _isPrivateListing(p);
          final displayPost = _displayPost(p);
          final detailRoute = _detailRouteForPost(displayPost);

          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InkWell(
                    onTap: isPrivateListing
                        ? null
                        : () => context.push('/p/${p.userId}'),
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
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  (p.sharedPostId ?? '').isNotEmpty
                                      ? '${_feedHeaderLabel(p)} shared a post'
                                      : _feedHeaderLabel(p),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    if (p.distanceKm != null)
                                      _buildFeedMetaText(
                                        '${p.distanceKm!.toStringAsFixed(1)} km',
                                      ),
                                    if (_locationLabel(p) != null)
                                      _buildFeedMetaText(_locationLabel(p)!),
                                    _buildVisibilityBadge(p.visibility),
                                    if (p.shareScope != 'none' && (p.sharedPostId ?? '').isEmpty)
                                      _buildAuthorBadge(_shareScopeLabel(p.shareScope)),
                                    if (badgeText != null) _buildAuthorBadge(badgeText),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          PopupMenuButton<String>(
                            icon: const Icon(Icons.more_vert),
                            onSelected: (value) async {
                              if (value == 'report') {
                                final reported = await showModalBottomSheet<bool>(
                                  context: context,
                                  isScrollControlled: true,
                                  builder: (_) => ReportPostSheet(postId: p.id),
                                );

                                if (reported == true && context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Thanks â€” weâ€™ll review it.'),
                                    ),
                                  );
                                }
                              }
                            },
                            itemBuilder: (context) => [
                              if (Supabase.instance.client.auth.currentUser?.id != p.userId)
                                const PopupMenuItem(
                                  value: 'report',
                                  child: Text('Report'),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (p.content.trim().isNotEmpty) ...[
                    TaggedContent(
                      content: p.content,
                      textStyle: const TextStyle(fontSize: 15),
                    ),
                  ],
                  if ((displayPost.marketTitle ?? '').trim().isNotEmpty &&
                      (p.sharedPostId ?? '').isEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      displayPost.marketTitle!.trim(),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                  if ((p.sharedPostId ?? '').isNotEmpty) ...[
                    _buildSharedPostSection(p),
                  ] else if ((displayPost.imageUrl ?? '').isNotEmpty ||
                      (displayPost.secondImageUrl ?? '').isNotEmpty ||
                      (displayPost.videoUrl ?? '').isNotEmpty) ...[
                    const SizedBox(height: 10),
                    PostMediaView(
                      imageUrl: displayPost.imageUrl,
                      secondImageUrl: displayPost.secondImageUrl,
                      videoUrl: displayPost.videoUrl,
                      maxHeight: 360,
                      singleImagePreview: _isMarketplacePost(displayPost) ||
                          _isGigPost(displayPost) ||
                          _isFoodPost(displayPost),
                      onImageTap: _openImagePreview,
                    ),
                  ],
                  if ((p.sharedPostId ?? '').isEmpty) _buildQaPreview(displayPost),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        _formatFeedTimestamp(p.createdAt),
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).hintColor,
                        ),
                      ),
                      if (displayPost.locationName != null &&
                          displayPost.locationName!.trim().isNotEmpty)
                        Text(
                          displayPost.locationName!.trim(),
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).hintColor,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (detailRoute != null)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => context.push(detailRoute),
                          icon: Icon(
                            p.postType == 'market'
                                ? Icons.open_in_new
                                : p.postType == 'food' || p.postType == 'food_ad'
                                ? Icons.restaurant
                                : Icons.work_outline,
                            size: 18,
                          ),
                          label: Text(
                            p.postType == 'market'
                                ? 'Open product'
                                : p.postType == 'food' || p.postType == 'food_ad'
                                ? 'Open food'
                                : 'Open gig',
                          ),
                        ),
                      ],
                    ),
                  _buildReactionsRow(p),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFooter() {
    if (!_hasMore) return const SizedBox(height: 24);
    if (_loadingMore) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    // Small spacer so last card isn't stuck to bottom
    return const SizedBox(height: 24);
  }

  Widget _buildAuthorBadge(String text) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 180),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.amber.withOpacity(0.14),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.amber.withOpacity(0.4)),
        ),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            height: 1.1,
          ),
        ),
      ),
    );
  }

  Widget _buildVisibilityBadge(String visibility) {
    final isLocal = visibility == 'followers';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isLocal
            ? const Color(0xFF0F766E).withOpacity(0.12)
            : const Color(0xFFCC7A00).withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: isLocal
              ? const Color(0xFF0F766E).withOpacity(0.28)
              : const Color(0xFFCC7A00).withOpacity(0.28),
        ),
      ),
      child: Text(
        isLocal ? 'LOCAL' : 'PUBLIC',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: isLocal ? const Color(0xFF0F766E) : const Color(0xFF8B5A12),
        ),
      ),
    );
  }

  String _formatFeedTimestamp(DateTime dt) {
    final local = dt.toLocal();
    final now = DateTime.now();
    final diff = now.difference(local);

    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';

    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} ${two(local.hour)}:${two(local.minute)}';
  }

  String? _locationLabel(Post post) {
    final loaded = (_authorLocationLabels[post.userId] ?? '').trim();
    if (loaded.isNotEmpty) return loaded;

    final city = (post.authorCity ?? '').trim();
    if (city.isNotEmpty) return city;

    final zipcode = (post.authorZipcode ?? '').trim();
    if (zipcode.isNotEmpty) return zipcode;

    return null;
  }

  Post _displayPost(Post post) => post.sharedPost ?? post;

  Widget _buildSharedPostSection(Post wrapperPost) {
    final shared = wrapperPost.sharedPost;
    if (shared != null) {
      return _buildSharedPostPreview(shared);
    }

    final sharedPostId = wrapperPost.sharedPostId;
    if (sharedPostId == null || sharedPostId.isEmpty) {
      return const SizedBox.shrink();
    }

    return FutureBuilder<Map<String, dynamic>?>(
      future: Supabase.instance.client
          .from('posts')
          .select(PostService.postSelect)
          .eq('id', sharedPostId)
          .maybeSingle(),
      builder: (context, snapshot) {
        final row = snapshot.data;
        if (row == null) {
          return Container(
            margin: const EdgeInsets.only(top: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.72),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE6DDCE)),
            ),
            child: const Text(
              'Original post unavailable',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          );
        }

        return _buildSharedPostPreview(Post.fromMap(row));
      },
    );
  }

  Widget _buildQaPreview(Post post) {
    final type = (post.postType ?? '').trim();
    final isMarketplacePost = type == 'market';
    final isGigPost = type == 'service_offer' || type == 'service_request';
    if (!isMarketplacePost && !isGigPost) {
      return const SizedBox.shrink();
    }

    final react = ReactionService(Supabase.instance.client);
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: react.fetchComments(post.id),
      builder: (context, snapshot) {
        final rows = snapshot.data ?? const <Map<String, dynamic>>[];
        if (rows.isEmpty) return const SizedBox.shrink();

        final roots = rows.where((row) => row['parent_comment_id'] == null).take(2).toList();
        if (roots.isEmpty) return const SizedBox.shrink();

        return Container(
          margin: const EdgeInsets.only(top: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.72),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE6DDCE)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Q&A',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              ...roots.map((question) {
                final questionId = question['id']?.toString() ?? '';
                final answers = rows
                    .where((row) => row['parent_comment_id']?.toString() == questionId)
                    .take(1)
                    .toList();
                final qProfile = question['profiles'];
                final qName = qProfile is Map
                    ? (qProfile['full_name']?.toString().trim().isNotEmpty == true
                        ? qProfile['full_name'].toString().trim()
                        : 'User')
                    : 'User';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        qName,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      TaggedContent(content: question['content']?.toString() ?? ''),
                      if (answers.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Padding(
                          padding: const EdgeInsets.only(left: 14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Owner/Author',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF7A5C2E),
                                ),
                              ),
                              const SizedBox(height: 4),
                              TaggedContent(content: answers.first['content']?.toString() ?? ''),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  String _shareScopeLabel(String scope) {
    switch (scope) {
      case 'followers':
        return 'Followers can share';
      case 'connections':
        return 'Connections can share';
      case 'public':
        return 'Public can share';
      default:
        return 'Sharing off';
    }
  }

  Widget _buildSharedPostPreview(Post sharedPost) {
    final badgeText = _getAuthorBadgeType(sharedPost);
    final detailRoute = _detailRouteForPost(sharedPost);

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.72),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE6DDCE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => context.push('/p/${sharedPost.userId}'),
            borderRadius: BorderRadius.circular(10),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundImage: sharedPost.authorAvatarUrl != null &&
                          sharedPost.authorAvatarUrl!.isNotEmpty
                      ? NetworkImage(sharedPost.authorAvatarUrl!)
                      : null,
                  child: sharedPost.authorAvatarUrl == null || sharedPost.authorAvatarUrl!.isEmpty
                      ? const Icon(Icons.person, size: 16)
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _feedHeaderLabel(sharedPost),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _buildVisibilityBadge(sharedPost.visibility),
                          if (badgeText != null) _buildAuthorBadge(badgeText),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (sharedPost.content.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            TaggedContent(
              content: sharedPost.content,
              textStyle: const TextStyle(fontSize: 14),
            ),
          ],
          if ((sharedPost.marketTitle ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              sharedPost.marketTitle!.trim(),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
          if ((sharedPost.imageUrl ?? '').isNotEmpty ||
              (sharedPost.secondImageUrl ?? '').isNotEmpty ||
              (sharedPost.videoUrl ?? '').isNotEmpty) ...[
            const SizedBox(height: 10),
            PostMediaView(
              imageUrl: sharedPost.imageUrl,
              secondImageUrl: sharedPost.secondImageUrl,
              videoUrl: sharedPost.videoUrl,
              maxHeight: 280,
              singleImagePreview: _isMarketplacePost(sharedPost) ||
                  _isGigPost(sharedPost) ||
                  _isFoodPost(sharedPost),
              onImageTap: _openImagePreview,
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Text(
                _formatFeedTimestamp(sharedPost.createdAt),
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).hintColor,
                ),
              ),
              if (sharedPost.locationName != null && sharedPost.locationName!.trim().isNotEmpty)
                Text(
                  sharedPost.locationName!.trim(),
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).hintColor,
                  ),
                ),
            ],
          ),
          if (detailRoute != null) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => context.push(detailRoute),
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('Open original'),
            ),
          ],
        ],
      ),
    );
  }

  void _openImagePreview(String imageUrl) {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            InteractiveViewer(
              minScale: 0.8,
              maxScale: 4,
              child: Center(
                child: Image.network(imageUrl, fit: BoxFit.contain),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResponsiveFeedBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('Feed error:\n$_error'),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 1100;
        if (!isWide) {
          return _buildFeedList(
            showTopFilters: false,
            showSummaryBanner: false,
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 300,
              child: _buildDesktopSidebar(),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 820),
                  child: _buildFeedList(
                    showTopFilters: false,
                    showSummaryBanner: true,
                  ),
                ),
              ),
            ),
            const VerticalDivider(width: 1),
            SizedBox(
              width: 320,
              child: _buildRightSidebar(),
            ),
          ],
        );
      },
    );
  }

  bool _useSplitMobileFeeds(BuildContext context) =>
      !kIsWeb && MediaQuery.of(context).size.width < 1100;

  Widget _buildRootFeedBody() {
    if (!_useSplitMobileFeeds(context)) {
      return _buildResponsiveFeedBody();
    }

    return Stack(
      children: [
        PageView(
          controller: _mobileFeedPager,
          onPageChanged: (index) {
            if (!mounted) return;
            setState(() => _mobileFeedPage = index);
          },
          children: [
            _buildResponsiveFeedBody(),
            const MobileVideoFeed(),
          ],
        ),
        Positioned(
          top: 10,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.28),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildMobileFeedDot(active: _mobileFeedPage == 0),
                    const SizedBox(width: 6),
                    _buildMobileFeedDot(active: _mobileFeedPage == 1),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMobileFeedDot({required bool active}) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: active ? 18 : 8,
      height: 8,
      decoration: BoxDecoration(
        color: active ? const Color(0xFF0F766E) : Colors.white.withOpacity(0.72),
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GlobalAppBar(
        title: 'Local Feed',
        notifBell: _notifBell(),
        showBackIfPossible: false,
        homeRoute: '/feed',
        onBeforeLogout: _onBeforeLogout,
      ),
      body: _buildRootFeedBody(),
      bottomNavigationBar: GlobalBottomNav(
        onOpenFilters: _openFilterSheet,
        onBeforeLogout: _onBeforeLogout,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: Padding(
        padding: EdgeInsets.only(
          right: MediaQuery.of(context).size.width >= 1100 ? 340 : 0,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (_showScrollTop)
              FloatingActionButton.small(
                heroTag: 'feed-top',
                onPressed: () {
                  _scroll.animateTo(
                    0,
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeOut,
                  );
                },
                child: const Icon(Icons.keyboard_arrow_up),
              ),
            if (_showScrollTop) const SizedBox(height: 10),
            FloatingActionButton.extended(
              heroTag: 'feed-post',
              onPressed: () async {
                final res = await context.push('/create-post');
                if (!mounted) return;
                if (res == true) _load(reset: true);
              },
              icon: const Icon(Icons.add),
              label: const Text('Post'),
            ),
          ],
        ),
      ),
    );

    /*
    return Scaffold(
      appBar: GlobalAppBar(
        title: 'Local Feed',
        notifBell: _notifBell(),
        showBackIfPossible: false,
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
                    await _load(reset: true);
                    await _refreshUnreadNotifs();
                  },
                  child: ListView.builder(
                    controller: _scroll,
                    itemCount: _posts.length + 2, // filters + footer
                    itemBuilder: (_, i) {
                      if (i == 0) return _buildFilters();
                      if (i == _posts.length + 1) return _buildFooter();

                      final p = _posts[i - 1];
                      final badgeText = _getAuthorBadgeType(p);
                      final isPrivateListing = _isPrivateListing(p);
                      final detailRoute = _detailRouteForPost(p);

                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              InkWell(
                                onTap: isPrivateListing
                                    ? null
                                    : () => context.push('/p/${p.userId}'),
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
                                          _feedHeaderLabel(p),
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
                                      if (_locationLabel(p) != null) ...[
                                        Text(
                                          _locationLabel(p)!,
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                        const SizedBox(width: 8),
                                      ],
                                      if (badgeText != null) ...[
                                        _buildAuthorBadge(badgeText),
                                        const SizedBox(width: 6),
                                      ],

                                      // ✅ NEW: 3-dot menu (Report)
                                      PopupMenuButton<String>(
                                        icon: const Icon(Icons.more_vert),
                                        onSelected: (value) async {
                                          if (value == 'report') {
                                            final reported = await showModalBottomSheet<bool>(
                                              context: context,
                                              isScrollControlled: true,
                                              builder: (_) => ReportPostSheet(postId: p.id),
                                            );

                                            if (reported == true && context.mounted) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(
                                                  content: Text('Thanks — we’ll review it.'),
                                                ),
                                              );
                                            }
                                          }
                                        },
                                        itemBuilder: (context) => [
                                          if (Supabase.instance.client.auth.currentUser?.id != p.userId)
                                            const PopupMenuItem(
                                              value: 'report',
                                              child: Text('Report'),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(p.content),

                              if (p.videoUrl != null && p.videoUrl!.isNotEmpty) ...[
                                YoutubePreview(videoUrl: p.videoUrl!),
                              ],

                              if (p.imageUrl != null) ...[
                                const SizedBox(height: 10),
                                InkWell(
                                  onTap: () => _openImagePreview(p.imageUrl!),
                                  borderRadius: BorderRadius.circular(12),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Image.network(p.imageUrl!, fit: BoxFit.cover),
                                  ),
                                ),
                              ],

                              const SizedBox(height: 6),
                              _buildReactionsRow(p),

                              const SizedBox(height: 8),
                              if (p.locationName != null)
                                Text('📍 ${p.locationName}', style: const TextStyle(fontSize: 12)),
                              if (p.postType == 'market' &&
                                  p.marketIntent != null &&
                                  p.marketIntent!.isNotEmpty)
                                Text(
                                  'Type: ${p.marketIntent == 'buying' ? 'Buying' : p.marketIntent == 'selling' ? 'Selling' : p.marketIntent}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              if (p.postType == 'market' &&
                                  p.marketCategory != null &&
                                  p.marketCategory!.isNotEmpty)
                                Text(
                                  'Category: ${marketCategoryLabel(p.marketCategory!)}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              if (detailRoute != null) ...[
                                const SizedBox(height: 8),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: OutlinedButton.icon(
                                    onPressed: () => context.push(detailRoute),
                                    icon: Icon(
                                      p.postType == 'market'
                                          ? Icons.storefront_outlined
                                          : (p.postType == 'food_ad' || p.postType == 'food')
                                              ? Icons.fastfood
                                              : Icons.miscellaneous_services_outlined,
                                    ),
                                    label: Text(
                                      p.postType == 'market'
                                          ? 'Open product'
                                          : (p.postType == 'food_ad' || p.postType == 'food')
                                              ? 'Open food'
                                              : 'Open gig',
                                    ),
                                  ),
                                ),
                              ],
                              Text(
                                _formatFeedTimestamp(p.createdAt),
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
          if (res == true) _load(reset: true);
        },
        icon: const Icon(Icons.add),
        label: const Text('Post'),
      ),
    );*/
  }
}
