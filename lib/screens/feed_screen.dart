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
import '../core/create_post_launcher.dart';
import '../core/localization/app_localizations.dart';
import '../models/post_model.dart';
import '../core/business_categories.dart';
import '../core/market_categories.dart';
import '../core/restaurant_categories.dart';
import '../core/service_categories.dart';
import '../services/feed_filter_service.dart';
import '../services/post_service.dart';
import '../services/reaction_service.dart';
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

class _FeedScreenState extends State<FeedScreen> with WidgetsBindingObserver {
  final FeedFilterService _feedFilterService = FeedFilterService(Supabase.instance.client);

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
  int _activeMediaIndex = 0;

  // ✅ Filters
  bool _generalPostsEnabled = true;
  String _generalPostsScope = 'all';
  bool _marketplaceEnabled = true;
  final Set<String> _selectedMarketplaceIntents = {'buying', 'selling'};
  final Set<String> _selectedMarketplaceCategories = {};
  bool _gigsEnabled = true;
  final Set<String> _selectedGigTypes = {'service_offer', 'service_request'};
  final Set<String> _selectedGigCategories = {};
  bool _lostFoundEnabled = true;
  String _lostFoundScope = 'all';
  bool _foodAdsEnabled = true;
  final Set<String> _selectedFoodCategories = {};
  bool _organizationsEnabled = false;
  final Set<String> _selectedOrganizationKinds = {};

  // ✅ Notifications badge + realtime
  int _unreadNotifs = 0;
  RealtimeChannel? _notifChannel;
  RealtimeChannel? _postsChannel;
  Timer? _notifDebounce;
  Timer? _newPostsPoller;
  bool _syncingPostMutation = false;
  final Set<String> _pendingNewPostIds = {};
  Map<String, dynamic>? _myProfileSummary;
  int _profileCompleteness = 0;
  int _pendingOfferConversations = 0;
  int _unreadOfferMessages = 0;
  List<Map<String, dynamic>> _topPosts = [];
  final PageController _mobileFeedPager = PageController();
  int _mobileFeedPage = 0;
  bool _mobileVideoFeedActivated = false;
  bool _feedSummaryExpanded = false;
  AppLifecycleState? _appLifecycleState;
  bool _pollingStateInitialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _appLifecycleState = WidgetsBinding.instance.lifecycleState;
    _scroll.addListener(_onScroll);
    _initFeed();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_runDeferredStartupWork());
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_pollingStateInitialized) return;
    _pollingStateInitialized = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _updateNewPostsPollingState();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _mobileFeedPager.dispose();

    _notifDebounce?.cancel();
    _newPostsPoller?.cancel();
    final ch = _notifChannel;
    _notifChannel = null;
    if (ch != null) {
      Supabase.instance.client.removeChannel(ch);
    }
    final postsCh = _postsChannel;
    _postsChannel = null;
    if (postsCh != null) {
      Supabase.instance.client.removeChannel(postsCh);
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appLifecycleState = state;
    _updateNewPostsPollingState();
  }

  // -----------------------------
  // Infinite scroll trigger
  // -----------------------------
  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    final shouldShowTop = pos.pixels > 320;
    final estimatedIndex = (pos.pixels / 640).floor().clamp(0, _posts.isEmpty ? 0 : _posts.length - 1);
    if (shouldShowTop != _showScrollTop && mounted) {
      setState(() {
        _showScrollTop = shouldShowTop;
        _activeMediaIndex = estimatedIndex;
      });
    } else if (estimatedIndex != _activeMediaIndex && mounted) {
      setState(() => _activeMediaIndex = estimatedIndex);
    }
    if (pos.pixels >= pos.maxScrollExtent - 350) {
      _loadMore();
    }
  }

  Future<void> _initFeed() async {
    await _restoreSavedFilters();
    await _load(reset: true);
  }

  Future<void> _runDeferredStartupWork() async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    if (!mounted) return;
    unawaited(_initNotificationsUnread());
    _subscribePostsRealtime();
    unawaited(_loadSidebarData());
  }

  Future<void> _restoreSavedFilters() async {
    final data = await _feedFilterService.load();
    if (data == null || !mounted) return;

    setState(() => _applySavedFilters(data));
  }

  Future<void> _saveFilters() async {
    await _feedFilterService.save(_currentFilterPayload());
  }

  void _applySavedFilters(Map<String, dynamic> data) {
    _generalPostsEnabled = data['general_enabled'] != false;
    _generalPostsScope = (data['general_scope'] as String?) ?? 'all';
    _marketplaceEnabled = data['market_enabled'] != false;
    _selectedMarketplaceIntents
      ..clear()
      ..addAll(((data['market_intents'] as List?) ?? const []).map((e) => e.toString()));
    _selectedMarketplaceCategories
      ..clear()
      ..addAll(((data['market_categories'] as List?) ?? const []).map((e) => e.toString()));
    if (_marketplaceEnabled && _selectedMarketplaceCategories.isEmpty) {
      _selectedMarketplaceCategories.addAll(marketMainCategories);
    }
    if (_selectedMarketplaceIntents.isEmpty) {
      _selectedMarketplaceIntents.addAll({'buying', 'selling'});
    }
    _gigsEnabled = data['gigs_enabled'] != false;
    _selectedGigTypes
      ..clear()
      ..addAll(((data['gig_types'] as List?) ?? const []).map((e) => e.toString()));
    _selectedGigCategories
      ..clear()
      ..addAll(((data['gig_categories'] as List?) ?? const []).map((e) => e.toString()));
    if (_gigsEnabled && _selectedGigCategories.isEmpty) {
      _selectedGigCategories.addAll(serviceMainCategories);
    }
    if (_selectedGigTypes.isEmpty) {
      _selectedGigTypes.addAll({'service_offer', 'service_request'});
    }
    _lostFoundEnabled = data['lost_found_enabled'] != false;
    _lostFoundScope = (data['lost_found_scope'] as String?) ?? 'all';
    _foodAdsEnabled = data['food_enabled'] != false;
    _selectedFoodCategories
      ..clear()
      ..addAll(((data['food_categories'] as List?) ?? const []).map((e) => e.toString()));
    if (_foodAdsEnabled && _selectedFoodCategories.isEmpty) {
      _selectedFoodCategories.addAll(foodMainCategories);
    }
    _organizationsEnabled = data['org_enabled'] == true;
    _selectedOrganizationKinds
      ..clear()
      ..addAll(((data['org_kinds'] as List?) ?? const []).map((e) => e.toString()));
    if (_organizationsEnabled && _selectedOrganizationKinds.isEmpty) {
      _selectedOrganizationKinds.addAll({'government', 'nonprofit', 'news_agency'});
    }
  }

  Map<String, dynamic> _currentFilterPayload() {
    return {
      'general_enabled': _generalPostsEnabled,
      'general_scope': _generalPostsScope,
      'market_enabled': _marketplaceEnabled,
      'market_intents': _selectedMarketplaceIntents.toList(),
      'market_categories': _selectedMarketplaceCategories.toList(),
      'gigs_enabled': _gigsEnabled,
      'gig_types': _selectedGigTypes.toList(),
      'gig_categories': _selectedGigCategories.toList(),
      'lost_found_enabled': _lostFoundEnabled,
      'lost_found_scope': _lostFoundScope,
      'food_enabled': _foodAdsEnabled,
      'food_categories': _selectedFoodCategories.toList(),
      'org_enabled': _organizationsEnabled,
      'org_kinds': _selectedOrganizationKinds.toList(),
    };
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

  void _subscribePostsRealtime() {
    if (_postsChannel != null) return;

    final channel = Supabase.instance.client.channel('feed-posts');
    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'posts',
          callback: (payload) {
            final insertedId = (payload.newRecord['id'] ?? '').toString();
            if (insertedId.isEmpty || !mounted) return;

            final existingIds = _posts.map((post) => post.id).toSet();
            if (existingIds.contains(insertedId) ||
                _pendingNewPostIds.contains(insertedId)) {
              return;
            }

            setState(() {
              _pendingNewPostIds.add(insertedId);
            });
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'posts',
          callback: (_) {
            _refreshFeedAfterPostMutation();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'posts',
          callback: (payload) {
            final deletedId = (payload.oldRecord['id'] ?? '').toString();
            if (deletedId.isEmpty || !mounted) return;

            setState(() {
              _pendingNewPostIds.remove(deletedId);
              _posts.removeWhere(
                (post) => post.id == deletedId || post.sharedPostId == deletedId,
              );
              _topPosts.removeWhere(
                (row) =>
                    (row['id'] ?? '').toString() == deletedId ||
                    (row['shared_post_id'] ?? '').toString() == deletedId,
              );
            });
          },
        )
        .subscribe();

    _postsChannel = channel;
  }

  Future<void> _reloadForNewPosts() async {
    await _load(reset: true);
    await _loadSidebarData();
    if (!mounted) return;
    setState(() {
      _pendingNewPostIds.clear();
    });
    if (_scroll.hasClients) {
      await _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _refreshFeedAfterPostMutation() async {
    if (_syncingPostMutation || !mounted) return;
    _syncingPostMutation = true;

    try {
      await _load(reset: true);
      await _loadSidebarData();
    } finally {
      _syncingPostMutation = false;
    }
  }

  Widget _notifBell() {
    return IconButton(
      tooltip: context.l10n.tr('notifications'),
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
    _stopNewPostsPolling();
    final ch = _notifChannel;
    _notifChannel = null;
    if (ch != null) {
      await Supabase.instance.client.removeChannel(ch);
    }
    final postsCh = _postsChannel;
    _postsChannel = null;
    if (postsCh != null) {
      await Supabase.instance.client.removeChannel(postsCh);
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

  bool _isOrganizationAuthored(Post post) => (post.authorType ?? '').trim() == 'org';

  bool _matchesMarketplaceFilters(Post post) {
    if (!_isMarketplacePost(post)) {
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
    if (!_isGigPost(post)) {
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
        !_isOrganizationAuthored(post) &&
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
        _isFoodPost(post)) {
      if (_selectedFoodCategories.isNotEmpty) {
        matchedSection = _selectedFoodCategories.contains((post.marketCategory ?? '').trim());
      }
    }

    if (_organizationsEnabled &&
        !matchedSection &&
        (post.authorType ?? '').trim() == 'org' &&
        _isGeneralPost(post)) {
      if (_selectedOrganizationKinds.isNotEmpty) {
        final orgKind = ((post.authorOrgKind ?? _authorOrgKinds[post.userId]) ?? '').trim();
        matchedSection = orgKind.isEmpty || _selectedOrganizationKinds.contains(orgKind);
      }
    }

    if (!matchedSection) return false;

    return true;
  }

  void _startNewPostsPolling() {
    _newPostsPoller?.cancel();
    _newPostsPoller = Timer.periodic(
      const Duration(seconds: 8),
      (_) => _pollForNewPosts(),
    );
  }

  void _stopNewPostsPolling() {
    _newPostsPoller?.cancel();
    _newPostsPoller = null;
  }

  bool _shouldPollForNewPosts() {
    final lifecycle = _appLifecycleState;
    final appActive =
        lifecycle == null ||
        lifecycle == AppLifecycleState.resumed ||
        lifecycle == AppLifecycleState.inactive;
    final onFeedTab = !_useSplitMobileFeeds(context) || _mobileFeedPage == 0;
    return mounted && appActive && onFeedTab;
  }

  void _updateNewPostsPollingState() {
    if (!_shouldPollForNewPosts()) {
      _stopNewPostsPolling();
      return;
    }

    if (_newPostsPoller == null || !_newPostsPoller!.isActive) {
      _startNewPostsPolling();
    }
  }

  Future<List<Post>> _fetchFeedPage({
    required int limit,
    DateTime? beforeCreatedAt,
    String? beforeId,
    bool refreshAuthorBadges = true,
  }) async {
    final service = PostService(Supabase.instance.client);

    final raw = await service.fetchPublicFeed(
      scope: 'all',
      postType: 'all',
      authorType: 'all',
      limit: limit,
      beforeCreatedAt: beforeCreatedAt,
      beforeId: beforeId,
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

      if (beforeCreatedAt != null) {
        final ts = beforeCreatedAt.toIso8601String();
        if (beforeId != null && beforeId.isNotEmpty) {
          ownQuery = ownQuery.or(
            'created_at.lt.$ts,and(created_at.eq.$ts,id.lt.$beforeId)',
          );
        } else {
          ownQuery = ownQuery.lt('created_at', ts);
        }
      }

      final ownData = await ownQuery
          .order('created_at', ascending: false)
          .order('id', ascending: false)
          .limit(limit);
      ownRows = await service.excludeUnavailableAuthorRows(
        (ownData as List).cast<Map<String, dynamic>>(),
      );

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

        if (beforeCreatedAt != null) {
          final ts = beforeCreatedAt.toIso8601String();
          if (beforeId != null && beforeId.isNotEmpty) {
            followedQuery = followedQuery.or(
              'created_at.lt.$ts,and(created_at.eq.$ts,id.lt.$beforeId)',
            );
          } else {
            followedQuery = followedQuery.lt('created_at', ts);
          }
        }

        final followedData = await followedQuery
            .order('created_at', ascending: false)
            .order('id', ascending: false)
            .limit(limit);
        followedRows = await service.excludeUnavailableAuthorRows(
          (followedData as List).cast<Map<String, dynamic>>(),
        );
      }
    }

    if (_organizationsEnabled) {
      dynamic orgQuery = Supabase.instance.client
          .from('posts')
          .select(PostService.postSelect)
          .eq('author_profile_type', 'org')
          .eq('visibility', 'public');

      if (orgQuery != null && beforeCreatedAt != null) {
        final ts = beforeCreatedAt.toIso8601String();
        if (beforeId != null && beforeId.isNotEmpty) {
          orgQuery = orgQuery.or(
            'created_at.lt.$ts,and(created_at.eq.$ts,id.lt.$beforeId)',
          );
        } else {
          orgQuery = orgQuery.lt('created_at', ts);
        }
      }

      if (orgQuery != null) {
        final orgData = await orgQuery
            .order('created_at', ascending: false)
            .order('id', ascending: false)
            .limit(limit);
        orgRows = await service.excludeUnavailableAuthorRows(
          (orgData as List).cast<Map<String, dynamic>>(),
        );
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
    if (refreshAuthorBadges) {
      await _loadAuthorBadges(fetchedPosts);
    }
    return fetchedPosts.where(_matchesSelectedFilters).toList();
  }

  Future<void> _pollForNewPosts() async {
    if (!mounted || _loading || _loadingMore) return;
    try {
      final latestPosts = await _fetchFeedPage(
        limit: _pageSize,
        refreshAuthorBadges: false,
      );
      if (!mounted) return;

      final existingIds = _posts.map((post) => post.id).toSet();
      final newIds = latestPosts
          .map((post) => post.id)
          .where((id) => !existingIds.contains(id))
          .toSet();
      if (newIds.isEmpty) return;

      setState(() {
        _pendingNewPostIds.addAll(newIds);
      });
    } catch (_) {
      // Polling is additive only. Ignore transient failures.
    }
  }

  Future<void> _load({required bool reset}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
        _posts = [];
        _pendingNewPostIds.clear();
        _hasMore = true;
        _loadingMore = false;
        _cursorCreatedAt = null;
        _cursorId = null;
      });
    } else {
      setState(() => _loadingMore = true);
    }

    try {
      final fetchedPosts = await _fetchFeedPage(
        limit: _pageSize,
        beforeCreatedAt: _cursorCreatedAt,
        beforeId: _cursorId,
      );
      final incoming = fetchedPosts;

      if (incoming.length < _pageSize) _hasMore = false;

      if (incoming.isNotEmpty) {
        final last = incoming.last;
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
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
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
      if (!_canSharePost(p)) return const SizedBox.shrink();
      return Row(
        children: [
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
                  SnackBar(content: Text(context.l10n.tr('post_shared'))),
                );
                await _load(reset: true);
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      context.l10n.tr('share_error', args: {'error': '$e'}),
                    ),
                  ),
                );
              }
            },
            icon: const Icon(Icons.share_outlined),
            label: Text(context.l10n.tr('share')),
          ),
        ],
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
                final messenger = ScaffoldMessenger.of(context);
                final l10n = context.l10n;
                try {
                  if (liked) {
                    await react.unlike(p.id);
                  } else {
                    await react.like(p.id);
                  }
                  if (!mounted) return;
                  setState(() {});
                } catch (e) {
                  if (!mounted) return;
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(
                        l10n.tr('like_error', args: {'error': '$e'}),
                      ),
                    ),
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
                  final messenger = ScaffoldMessenger.of(context);
                  final l10n = context.l10n;
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
                    messenger.showSnackBar(
                      SnackBar(content: Text(l10n.tr('post_shared'))),
                    );
                    await _load(reset: true);
                  } catch (e) {
                    if (!mounted) return;
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(
                          l10n.tr('share_error', args: {'error': '$e'}),
                        ),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.share_outlined),
                label: Text(context.l10n.tr('share')),
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

  String? _orgKindLabel(String value) {
    switch (value) {
      case 'government':
        return context.l10n.tr('government');
      case 'nonprofit':
        return context.l10n.tr('non_profit');
      case 'news_agency':
        return context.l10n.tr('news_agency');
      default:
        return value.trim().isEmpty ? null : value;
    }
  }

  String? _getAuthorBadgeType(Post post) {
    return _authorBadgeLabels[post.userId];
  }

  String? _getAuthorAccountBadge(Post post) {
    final type = ((post.authorType ?? '')).trim();
    switch (type) {
      case 'business':
        final subtype = (_getAuthorBadgeType(post) ?? '').trim().toLowerCase();
        final restaurantLabels = restaurantMainCategories
            .map(restaurantCategoryLabel)
            .map((value) => value.toLowerCase())
            .toSet();
        return restaurantLabels.contains(subtype) ? 'Restaurant' : 'Business';
      case 'org':
        return 'Organization';
      default:
        return null;
    }
  }

  String? _getAuthorSubtypeBadge(Post post) {
    final type = ((post.authorType ?? '')).trim();
    if (type == 'org') {
      final orgKind = ((post.authorOrgKind ?? _authorOrgKinds[post.userId]) ?? '').trim();
      return _orgKindLabel(orgKind);
    }
    if (type == 'business') {
      return _getAuthorBadgeType(post);
    }
    return null;
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
              'id, full_name, bio, avatar_url, zipcode, city, latitude, longitude, profile_type, radius_km',
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
      final ranked = (await Future.wait<Map<String, dynamic>?>(
        topPostRows.map((row) async {
          final id = (row['id'] ?? '').toString();
          if (id.isEmpty) return null;
          final counts = await Future.wait<int>([
            react.likesCount(id),
            react.commentsCount(id),
          ]);
          return {
            ...row,
            'engagement': counts[0] + counts[1],
          };
        }),
      ))
          .whereType<Map<String, dynamic>>()
          .toList();
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
      case 'service_request':
        return 'Gigs post';
      default:
        return post.authorName ?? 'Unknown';
    }
  }

  String? _getPostTypeBadge(Post p) {
    switch (p.postType) {
      case 'market':
        return 'Marketplace';
      case 'service_offer':
        return 'Service Offer';
      case 'service_request':
        return 'Service Request';
      case 'lost_found':
        return 'Lost & Found';
      case 'food_ad':
      case 'food':
        return 'Food Ad';
      default:
        return null;
    }
  }

  String? _getCategoryBadge(Post p) {
    final category = (p.marketCategory ?? '').trim();
    if (category.isEmpty) return null;

    switch (p.postType) {
      case 'market':
        return marketCategoryLabel(category);
      case 'service_offer':
      case 'service_request':
        return serviceCategoryLabel(category);
      case 'food_ad':
      case 'food':
        return foodCategoryLabel(category);
      default:
        return null;
    }
  }

  String? _getMarketplaceIntentBadge(Post p) {
    if (p.postType != 'market') return null;

    final intent = (p.marketIntent ?? '').trim();
    if (intent.isEmpty) return null;
    return _intentLabel(intent);
  }

  bool _shouldShowAuthorBadge(Post p) {
    switch (p.postType) {
      case 'market':
      case 'service_offer':
      case 'service_request':
      case 'food_ad':
      case 'food':
        return false;
      default:
        return true;
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
    final l10n = context.l10n;
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
              l10n.tr('discover_nearby'),
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
                  label: Text(l10n.tr('filters')),
                ),
                FilledButton.icon(
                  onPressed: () async {
                    final res = await openCreatePostFlow(context);
                    if (!mounted) return;
                    if (res == true) _load(reset: true);
                  },
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(l10n.tr('post_label')),
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
                  label: l10n.tr('marketplace'),
                  onPressed: () => context.push('/marketplace'),
                ),
                _buildQuickLinkButton(
                  icon: Icons.miscellaneous_services_outlined,
                  label: l10n.tr('gigs'),
                  onPressed: () => context.push('/gigs'),
                ),
                _buildQuickLinkButton(
                  icon: Icons.fastfood,
                  label: l10n.tr('foods'),
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
                  label: l10n.tr('businesses'),
                  onPressed: () => context.push('/businesses'),
                ),
                _buildQuickLinkButton(
                  icon: Icons.restaurant_menu,
                  label: l10n.tr('restaurants'),
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
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () {
          if (!mounted) return;
          setState(() => _feedSummaryExpanded = !_feedSummaryExpanded);
        },
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFF0F766E).withValues(alpha: 0.1),
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
                      _feedSummaryExpanded ? 'Tap to hide details' : 'Tap to view details',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    AnimatedCrossFade(
                      duration: const Duration(milliseconds: 180),
                      firstChild: const SizedBox.shrink(),
                      secondChild: Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          _feedWhatShowing(),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      crossFadeState: _feedSummaryExpanded
                          ? CrossFadeState.showSecond
                          : CrossFadeState.showFirst,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Icon(
                _feedSummaryExpanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                color: const Color(0xFF0F766E),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeedStatusBanner() {
    final count = _pendingNewPostIds.length;
    if (count == 0) return const SizedBox.shrink();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: _reloadForNewPosts,
        child: Ink(
          decoration: BoxDecoration(
            color: const Color(0xFF0F766E),
            borderRadius: BorderRadius.circular(999),
            boxShadow: const [
              BoxShadow(
                color: Color(0x22000000),
                blurRadius: 14,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.fiber_new_rounded, color: Colors.white, size: 16),
                const SizedBox(width: 8),
                Text(
                  count == 1 ? '1 new post' : '$count new posts',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStickyFeedStatus({required double top}) {
    if (_pendingNewPostIds.isEmpty) return const SizedBox.shrink();
    return Positioned(
      top: top,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: IgnorePointer(
          ignoring: false,
          child: Center(child: _buildFeedStatusBanner()),
        ),
      ),
    );
  }

  Future<void> _openFilterSheet() async {
    final l10n = context.l10n;
    var draftGeneralEnabled = _generalPostsEnabled;
    var draftGeneralScope = _generalPostsScope;
    var draftMarketplaceEnabled = _marketplaceEnabled;
    final draftMarketplaceIntents = {..._selectedMarketplaceIntents};
    final draftMarketplaceCategories = {..._selectedMarketplaceCategories};
    var draftGigsEnabled = _gigsEnabled;
    final draftGigTypes = {..._selectedGigTypes};
    final draftGigCategories = {..._selectedGigCategories};
    var draftLostFoundEnabled = _lostFoundEnabled;
    var draftLostFoundScope = _lostFoundScope;
    var draftFoodAdsEnabled = _foodAdsEnabled;
    final draftFoodCategories = {..._selectedFoodCategories};
    var draftOrganizationsEnabled = _organizationsEnabled;
    final draftOrganizationKinds = {..._selectedOrganizationKinds};
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
                                draftMarketplaceIntents
                                  ..clear()
                                  ..addAll({'buying', 'selling'});
                                draftMarketplaceCategories.clear();
                                draftGigsEnabled = true;
                                draftGigTypes
                                  ..clear()
                                  ..addAll({'service_offer', 'service_request'});
                                draftGigCategories.clear();
                                draftLostFoundEnabled = true;
                                draftLostFoundScope = 'all';
                                draftFoodAdsEnabled = true;
                                draftFoodCategories.clear();
                                draftOrganizationsEnabled = false;
                                draftOrganizationKinds.clear();
                              });
                            },
                            child: Text(l10n.tr('reset')),
                          ),
                          IconButton(
                            tooltip: l10n.tr('close'),
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _buildFilterSectionCard(
                        title: l10n.tr('general_posts'),
                        subtitle: l10n.tr('normal_feed_posts_only'),
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
                        title: l10n.tr('marketplace_posts'),
                        subtitle: l10n.tr('buying_selling_product_categories'),
                        enabled: draftMarketplaceEnabled,
                        onEnabledChanged: (value) {
                          setSheetState(() => draftMarketplaceEnabled = value);
                        },
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildMultiSelectSection(
                              title: l10n.tr('marketplace_type'),
                              options: [
                                ('buying', l10n.tr('buying')),
                                ('selling', l10n.tr('selling')),
                              ],
                              selected: draftMarketplaceIntents,
                              setSheetState: setSheetState,
                            ),
                            const SizedBox(height: 12),
                            _buildMultiSelectSection(
                              title: l10n.tr('marketplace_categories'),
                              options: marketMainCategories
                                  .map((c) => (c, marketCategoryLabel(c)))
                                  .toList(),
                              selected: draftMarketplaceCategories,
                              setSheetState: setSheetState,
                            ),
                            if (draftMarketplaceCategories.isEmpty) ...[
                              const SizedBox(height: 8),
                              _buildFilterWarning(l10n.tr('select_at_least_one_category')),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      _buildFilterSectionCard(
                        title: l10n.tr('gig_posts'),
                        subtitle: l10n.tr('service_offers_requests_and_categories'),
                        enabled: draftGigsEnabled,
                        onEnabledChanged: (value) {
                          setSheetState(() => draftGigsEnabled = value);
                        },
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildMultiSelectSection(
                              title: l10n.tr('gig_type'),
                              options: [
                                ('service_offer', l10n.tr('offering')),
                                ('service_request', l10n.tr('requesting')),
                              ],
                              selected: draftGigTypes,
                              setSheetState: setSheetState,
                            ),
                            const SizedBox(height: 12),
                            _buildMultiSelectSection(
                              title: l10n.tr('service_categories'),
                              options: serviceMainCategories
                                  .map((c) => (c, serviceCategoryLabel(c)))
                                  .toList(),
                              selected: draftGigCategories,
                              setSheetState: setSheetState,
                            ),
                            if (draftGigCategories.isEmpty) ...[
                              const SizedBox(height: 8),
                              _buildFilterWarning(l10n.tr('select_at_least_one_category')),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      _buildFilterSectionCard(
                        title: l10n.tr('lost_and_found'),
                        subtitle: l10n.tr('show_or_hide_lost_and_found_posts'),
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
                        title: l10n.tr('food_ads'),
                        subtitle: l10n.tr('food_posts_with_separate_categories'),
                        enabled: draftFoodAdsEnabled,
                        onEnabledChanged: (value) {
                          setSheetState(() => draftFoodAdsEnabled = value);
                        },
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildMultiSelectSection(
                              title: l10n.tr('food_category'),
                              options: foodMainCategories
                                  .map((c) => (c, foodCategoryLabel(c)))
                                  .toList(),
                              selected: draftFoodCategories,
                              setSheetState: setSheetState,
                            ),
                            if (draftFoodCategories.isEmpty) ...[
                              const SizedBox(height: 8),
                              _buildFilterWarning(l10n.tr('select_at_least_one_category')),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      _buildFilterSectionCard(
                        title: l10n.tr('organizations'),
                        subtitle: l10n.tr('show_organization_posts_by_subtype'),
                        enabled: draftOrganizationsEnabled,
                        onEnabledChanged: (value) {
                          setSheetState(() => draftOrganizationsEnabled = value);
                        },
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildMultiSelectSection(
                              title: l10n.tr('organization_types'),
                              options: [
                                ('government', l10n.tr('government')),
                                ('nonprofit', l10n.tr('non_profit')),
                                ('news_agency', l10n.tr('news_agency')),
                              ],
                              selected: draftOrganizationKinds,
                              setSheetState: setSheetState,
                            ),
                            if (draftOrganizationKinds.isEmpty) ...[
                              const SizedBox(height: 8),
                              _buildFilterWarning(l10n.tr('select_at_least_one_type')),
                            ],
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
                              _selectedMarketplaceIntents
                                ..clear()
                                ..addAll(draftMarketplaceIntents);
                              _selectedMarketplaceCategories
                                ..clear()
                                ..addAll(draftMarketplaceCategories);
                              _gigsEnabled = draftGigsEnabled;
                              _selectedGigTypes
                                ..clear()
                                ..addAll(draftGigTypes);
                              _selectedGigCategories
                                ..clear()
                                ..addAll(draftGigCategories);
                              _lostFoundEnabled = draftLostFoundEnabled;
                              _lostFoundScope = draftLostFoundScope;
                              _foodAdsEnabled = draftFoodAdsEnabled;
                              _selectedFoodCategories
                                ..clear()
                                ..addAll(draftFoodCategories);
                              _organizationsEnabled = draftOrganizationsEnabled;
                              _selectedOrganizationKinds
                                ..clear()
                                ..addAll(draftOrganizationKinds);
                            });
                            _saveFilters();
                            _load(reset: true);
                          },
                          child: Text(l10n.tr('apply_filters')),
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
        return context.l10n.tr('public');
      case 'following':
        return context.l10n.tr('following');
      case 'all':
      default:
        return context.l10n.tr('visibility_public_following');
    }
  }

  String _feedWhatShowing() {
    final l10n = context.l10n;
    final sections = <String>[];
    if (_generalPostsEnabled) {
      sections.add(
        '${l10n.tr('general_posts').toLowerCase()} (${_sectionScopeLabel(_generalPostsScope).toLowerCase()})',
      );
    }
    if (_marketplaceEnabled) {
      final intentText = _selectedMarketplaceIntents.isEmpty
          ? l10n.tr('all_marketplace_posts')
          : _selectedMarketplaceIntents.map(_intentLabel).join(' & ').toLowerCase();
      final categoryText = _selectedMarketplaceCategories.isEmpty
          ? l10n.tr('no_categories_selected')
          : _selectedMarketplaceCategories.map(marketCategoryLabel).join(', ');
      sections.add('$intentText in $categoryText');
    }
    if (_gigsEnabled) {
      final gigText = _selectedGigTypes.isEmpty
          ? l10n.tr('all_gigs')
          : _selectedGigTypes.map(_postTypeLabel).join(' & ').toLowerCase();
      final categoryText = _selectedGigCategories.isEmpty
          ? l10n.tr('no_categories_selected')
          : _selectedGigCategories.map(serviceCategoryLabel).join(', ');
      sections.add(
        l10n.tr(
          'gigs_in_categories',
          args: {'types': gigText, 'categories': categoryText},
        ),
      );
    }
    if (_lostFoundEnabled) {
      sections.add(
        '${l10n.tr('lost_and_found').toLowerCase()} (${_sectionScopeLabel(_lostFoundScope).toLowerCase()})',
      );
    }
    if (_foodAdsEnabled) {
      final categoryText = _selectedFoodCategories.isEmpty
          ? l10n.tr('no_categories_selected')
          : _selectedFoodCategories.map(foodCategoryLabel).join(', ');
      sections.add(
        l10n.tr(
          'food_ads_in_categories',
          args: {'categories': categoryText},
        ),
      );
    }
    if (_organizationsEnabled) {
      final orgText = _selectedOrganizationKinds.isEmpty
          ? l10n.tr('all_organization_posts')
          : _selectedOrganizationKinds.map(_organizationKindLabel).join(', ').toLowerCase();
      sections.add(orgText);
    }

    final radiusKm = (_myProfileSummary?['radius_km'] as num?)?.toInt();
    final sectionText =
        sections.isEmpty ? l10n.tr('no_sections_selected') : sections.join(' • ');
    if (radiusKm != null) {
      return l10n.tr(
        'you_are_seeing_with_radius',
        args: {'sections': sectionText, 'radius': '$radiusKm'},
      );
    }
    return l10n.tr('you_are_seeing', args: {'sections': sectionText});
  }

  String _postTypeLabel(String value) {
    switch (value) {
      case 'service_offer':
        return context.l10n.tr('offering');
      case 'service_request':
        return context.l10n.tr('requesting');
      case 'lost_found':
        return context.l10n.tr('lost_and_found');
      case 'food_ad':
        return context.l10n.tr('food_ads');
      default:
        return value;
    }
  }

  String _organizationKindLabel(String value) {
    switch (value) {
      case 'government':
        return context.l10n.tr('government');
      case 'nonprofit':
        return context.l10n.tr('non_profit');
      case 'news_agency':
        return context.l10n.tr('news_agency');
      default:
        return value;
    }
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
    final options = [
      ('all', context.l10n.tr('visibility_public_following')),
      ('public', context.l10n.tr('public')),
      ('following', context.l10n.tr('following')),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(left: 4, bottom: 6),
          child: Text(
            context.l10n.tr('visibility'),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
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
    final l10n = context.l10n;
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
                  l10n.tr('feed_controls'),
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
                    label: Text(l10n.tr('open_filters')),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () async {
                      final res = await openCreatePostFlow(context);
                      if (!mounted) return;
                      if (res == true) _load(reset: true);
                    },
                    icon: const Icon(Icons.add),
                    label: Text(l10n.tr('post_to_feed')),
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
                          _selectedMarketplaceIntents
                            ..clear()
                            ..addAll({'buying', 'selling'});
                          _selectedMarketplaceCategories.clear();
                          _gigsEnabled = true;
                          _selectedGigTypes
                            ..clear()
                            ..addAll({'service_offer', 'service_request'});
                          _selectedGigCategories.clear();
                          _lostFoundEnabled = true;
                          _lostFoundScope = 'all';
                          _foodAdsEnabled = true;
                          _selectedFoodCategories.clear();
                          _organizationsEnabled = false;
                          _selectedOrganizationKinds.clear();
                        });
                        _saveFilters();
                        _load(reset: true);
                      },
                    icon: const Icon(Icons.refresh),
                     label: Text(l10n.tr('reset_feed')),
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
                  l10n.tr('browse_sections'),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 14),
                _buildSidebarQuickLink(
                  icon: Icons.storefront_outlined,
                  label: l10n.tr('marketplace'),
                  onPressed: () => context.push('/marketplace'),
                ),
                _buildSidebarQuickLink(
                  icon: Icons.miscellaneous_services_outlined,
                  label: l10n.tr('gigs'),
                  onPressed: () => context.push('/gigs'),
                ),
                _buildSidebarQuickLink(
                  icon: Icons.fastfood,
                  label: l10n.tr('foods'),
                  onPressed: () => context.push('/foods'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _buildInfoCard(
            title: l10n.tr('local_directory'),
            child: Column(
              children: [
                _buildTaskRow(
                  icon: Icons.restaurant_menu,
                  title: l10n.tr('restaurants'),
                  subtitle: l10n.tr('browse_nearby_places_to_eat'),
                  onTap: () => context.push('/restaurants'),
                ),
                _buildTaskRow(
                  icon: Icons.business,
                  title: l10n.tr('businesses'),
                  subtitle: l10n.tr('explore_nearby_local_businesses'),
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
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.12),
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
    final l10n = context.l10n;
    final profileName = (_myProfileSummary?['full_name'] ?? context.l10n.tr('my_profile'))
        .toString();
    final incompleteProfile = _profileCompleteness < 100;
    final unreadChats = unreadBadgeController.unread.value;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 18, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfoCard(
            title: l10n.tr('top_trending'),
            child: SizedBox(
              height: 420,
              child: _topPosts.isEmpty
                  ? Center(child: Text(l10n.tr('no_top_posts_yet')))
                  : ListView.separated(
                      itemCount: _topPosts.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final post = _topPosts[index];
                        final title = ((post['market_title'] ?? '').toString().trim().isNotEmpty
                                ? post['market_title']
                                : post['content'] ?? l10n.tr('post_label'))
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
                                  .withValues(alpha: 0.45),
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
                                        title.isEmpty ? l10n.tr('post_label') : title,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontWeight: FontWeight.w700),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        l10n.tr(
                                          'engagement_count',
                                          args: {'count': '$engagement'},
                                        ),
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
            title: l10n.tr('todo'),
            child: Column(
              children: [
                if (_pendingOfferConversations > 0)
                  _buildTaskRow(
                    icon: Icons.local_offer_outlined,
                    title: l10n.tr('review_offers'),
                    subtitle: l10n.tr(
                      'conversations_need_attention',
                      args: {'count': '$_pendingOfferConversations'},
                    ),
                    onTap: () => context.push('/chats'),
                  ),
                if (_unreadOfferMessages > 0)
                  _buildTaskRow(
                    icon: Icons.forum_outlined,
                    title: l10n.tr('unread_offer_messages'),
                    subtitle: l10n.tr(
                      'unread_messages_in_offer_chats',
                      args: {'count': '$_unreadOfferMessages'},
                    ),
                    onTap: () => context.push('/chats'),
                  ),
                if (_unreadNotifs > 0)
                  _buildTaskRow(
                    icon: Icons.notifications_active_outlined,
                    title: l10n.tr('notifications'),
                    subtitle: l10n.tr(
                      'unread_notifications',
                      args: {'count': '$_unreadNotifs'},
                    ),
                    onTap: () => context.push('/notifications'),
                  ),
                if (unreadChats > 0)
                  _buildTaskRow(
                    icon: Icons.chat_bubble_outline,
                    title: l10n.tr('unread_chats'),
                    subtitle: l10n.tr(
                      'unread_conversations',
                      args: {'count': '$unreadChats'},
                    ),
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
                          .withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Text(
                      l10n.tr('nothing_pending_right_now'),
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
              title: l10n.tr('profile_completeness'),
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
                    l10n.tr(
                      'profile_complete_percent',
                      args: {'count': '$_profileCompleteness'},
                    ),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                      l10n.tr('improve_trust_and_discovery'),
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
                      label: Text(l10n.tr('open_profile')),
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
        await _reloadForNewPosts();
        await _refreshUnreadNotifs();
      },
      child: ListView.builder(
        controller: _scroll,
        cacheExtent: 900,
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
          final authorAccountBadge = _getAuthorAccountBadge(p);
          final authorSubtypeBadge = _getAuthorSubtypeBadge(p);
          final categoryBadge = _getCategoryBadge(p);
          final marketplaceIntentBadge = _getMarketplaceIntentBadge(p);
          final isPrivateListing = _isPrivateListing(p);
          final displayPost = _displayPost(p);
          final detailRoute = _detailRouteForPost(displayPost);
          final shouldEagerLoadMedia = (postIndex - _activeMediaIndex).abs() <= 1;

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
                          if (!isPrivateListing) ...[
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
                          ],
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
                                if (!isPrivateListing &&
                                    p.authorJobTitle != null &&
                                    p.authorJobTitle!.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(
                                      p.authorJobTitle!,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade700,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
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
                                    if (_getPostTypeBadge(p) != null)
                                      _buildPostTypeBadge(_getPostTypeBadge(p)!),
                                    if (marketplaceIntentBadge != null)
                                      _buildAuthorBadge(marketplaceIntentBadge),
                                    if (categoryBadge != null)
                                      _buildAuthorBadge(categoryBadge),
                                    if (!isPrivateListing &&
                                        p.authorBusinessType != null &&
                                        (p.authorBusinessType == 'trader' ||
                                            p.authorBusinessType == 'manufacturer'))
                                      _buildAuthorBadge(
                                        businessCategoryLabel(p.authorBusinessType!),
                                      ),
                                    if (!isPrivateListing &&
                                        p.shareScope != 'none' &&
                                        (p.sharedPostId ?? '').isEmpty)
                                      _buildAuthorBadge(_shareScopeLabel(p.shareScope)),
                                    if (authorAccountBadge != null &&
                                        _shouldShowAuthorBadge(p))
                                      _buildAuthorBadge(authorAccountBadge),
                                    if (authorSubtypeBadge != null &&
                                        _shouldShowAuthorBadge(p))
                                      _buildAuthorBadge(authorSubtypeBadge),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          PopupMenuButton<String>(
                            icon: const Icon(Icons.more_vert),
                            onSelected: (value) async {
                              if (value == 'report') {
                                final messenger = ScaffoldMessenger.of(context);
                                final reported = await showModalBottomSheet<bool>(
                                  context: context,
                                  isScrollControlled: true,
                                  builder: (_) => ReportPostSheet(postId: p.id),
                                );

                                if (reported == true) {
                                  messenger.showSnackBar(
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
                    _buildDeferredPostMedia(
                      post: displayPost,
                      loadFullMedia: shouldEagerLoadMedia,
                    ),
                  ],
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
          color: Colors.amber.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
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

  Widget _buildPostTypeBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF0F766E).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: Color(0xFF0F766E),
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
            ? const Color(0xFF0F766E).withValues(alpha: 0.12)
            : const Color(0xFFCC7A00).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: isLocal
              ? const Color(0xFF0F766E).withValues(alpha: 0.28)
              : const Color(0xFFCC7A00).withValues(alpha: 0.28),
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

  Widget _buildDeferredPostMedia({
    required Post post,
    required bool loadFullMedia,
  }) {
    if (loadFullMedia) {
      return PostMediaView(
        imageUrl: post.imageUrl,
        secondImageUrl: post.secondImageUrl,
        videoUrl: post.videoUrl,
        maxHeight: 360,
        singleImagePreview: _isMarketplacePost(post) ||
            _isGigPost(post) ||
            _isFoodPost(post),
        startMuted: true,
        showMuteToggle: true,
        autoplay: false,
        onImageTap: _openImagePreview,
      );
    }

    final previewImage = ((post.imageUrl ?? '').trim().isNotEmpty
            ? post.imageUrl
            : post.secondImageUrl)
        ?.trim();
    final hasVideo = (post.videoUrl ?? '').trim().isNotEmpty;

    return InkWell(
      onTap: () => context.push('/post/${post.id}'),
      borderRadius: BorderRadius.circular(12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              constraints: const BoxConstraints(maxHeight: 280),
              width: double.infinity,
              color: Colors.black.withValues(alpha: 0.06),
              child: previewImage != null && previewImage.isNotEmpty
                  ? Image.network(
                      previewImage,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(color: Colors.black12),
                    )
                  : Container(
                      height: 220,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF12211D), Color(0xFF425B56)],
                        ),
                      ),
                    ),
            ),
            Container(color: Colors.black.withValues(alpha: hasVideo ? 0.26 : 0.14)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.56),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    hasVideo ? Icons.play_arrow_rounded : Icons.photo_outlined,
                    color: Colors.white,
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    hasVideo ? 'Load video' : 'Load media',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
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
              color: Colors.white.withValues(alpha: 0.72),
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
            color: Colors.white.withValues(alpha: 0.72),
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
    final authorAccountBadge = _getAuthorAccountBadge(sharedPost);
    final authorSubtypeBadge = _getAuthorSubtypeBadge(sharedPost);
    final categoryBadge = _getCategoryBadge(sharedPost);
    final marketplaceIntentBadge = _getMarketplaceIntentBadge(sharedPost);
    final detailRoute = _detailRouteForPost(sharedPost);

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
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
                          if (marketplaceIntentBadge != null)
                            _buildAuthorBadge(marketplaceIntentBadge),
                          if (categoryBadge != null)
                            _buildAuthorBadge(categoryBadge),
                          if (authorAccountBadge != null &&
                              _shouldShowAuthorBadge(sharedPost))
                            _buildAuthorBadge(authorAccountBadge),
                          if (authorSubtypeBadge != null &&
                              _shouldShowAuthorBadge(sharedPost))
                            _buildAuthorBadge(authorSubtypeBadge),
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
              startMuted: true,
              showMuteToggle: true,
              autoplay: false,
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
              label: Text(context.l10n.tr('open_original')),
            ),
          ],
        ],
      ),
    );
  }

  void _openImagePreview(String imageUrl) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
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
                onPressed: () => Navigator.of(dialogContext).pop(),
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
          child: Text(context.l10n.tr('feed_error', args: {'error': '$_error'})),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 1100;
        if (!isWide) {
          return _buildFeedList(
            showTopFilters: false,
            showSummaryBanner: true,
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
      return Stack(
        children: [
          _buildResponsiveFeedBody(),
          _buildStickyFeedStatus(top: 10),
        ],
      );
    }

    return Stack(
      children: [
        PageView.builder(
          controller: _mobileFeedPager,
          itemCount: 2,
          onPageChanged: (index) {
            if (!mounted) return;
            setState(() {
              _mobileFeedPage = index;
              if (index == 1) {
                _mobileVideoFeedActivated = true;
              }
            });
            _updateNewPostsPollingState();
          },
          itemBuilder: (context, index) {
            if (index == 0) {
              return _buildResponsiveFeedBody();
            }

            if (_mobileVideoFeedActivated || _mobileFeedPage == 1) {
              return const MobileVideoFeed();
            }

            return Container(
              color: const Color(0xFF08111C),
              alignment: Alignment.center,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.play_circle_outline,
                      size: 56,
                      color: Colors.white70,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Swipe to open the video feed.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'The video page now loads only when you actually open it.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.72),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
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
                  color: Colors.black.withValues(alpha: 0.28),
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
        if (_mobileFeedPage == 0) _buildStickyFeedStatus(top: 44),
      ],
    );
  }

  Widget _buildMobileFeedDot({required bool active}) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: active ? 18 : 8,
      height: 8,
      decoration: BoxDecoration(
        color: active ? const Color(0xFF0F766E) : Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GlobalAppBar(
        title: 'Allonssy!',
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
                final res = await openCreatePostFlow(context);
                if (!mounted) return;
                if (res == true) _load(reset: true);
              },
              icon: const Icon(Icons.add),
              label: Text(context.l10n.tr('post_label')),
            ),
          ],
        ),
      ),
    );
  }
}
