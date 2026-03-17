import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../widgets/global_app_bar.dart'; // ✅ NEW
import '../widgets/global_bottom_nav.dart';
import '../core/localization/app_localizations.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

enum SearchTab { profiles, posts }
enum SearchScope { public, following }

class _SearchScreenState extends State<SearchScreen> {
  final _qCtrl = TextEditingController();
  Timer? _debounce;

  SearchTab _tab = SearchTab.profiles;
  SearchScope _scope = SearchScope.public;

  final List<String> _postTypes = const [
    'all',
    'post',
    'market',
    'service_offer',
    'service_request',
    'lost_found',
  ];
  final List<String> _authorTypes = const ['all', 'person', 'business', 'org'];

  String _selectedPostType = 'all';
  String _selectedAuthorType = 'all';

  String _strictnessLabel(double v) {
    final l10n = context.l10n;
    final x = v.clamp(0.15, 0.45).toDouble();
    if (x <= 0.20) return l10n.tr('broad');
    if (x <= 0.30) return l10n.tr('balanced');
    if (x <= 0.40) return l10n.tr('precise');
    return l10n.tr('exact');
  }

  bool _loading = false;
  String? _error;
  bool _filtersExpanded = true;

  // ✅ Nearby toggle + viewer location from profile
  bool _nearbyOnly = false;
  double? _meLat;
  double? _meLng;
  int _meRadiusKm = 5;
  bool _profileLoaded = false;

  // ✅ Fuzzy threshold (lower = more results, more noise)
  double _simThreshold = 0.25;

  List<Map<String, dynamic>> _profiles = [];
  List<Map<String, dynamic>> _posts = [];

  Future<Set<String>> _disabledProfileIds(Iterable<String> ids) async {
    final uniqueIds = ids.where((id) => id.isNotEmpty).toSet().toList();
    if (uniqueIds.isEmpty) return <String>{};

    final rows = await _db
        .from('profiles')
        .select('id, is_disabled')
        .inFilter('id', uniqueIds);

    return (rows as List)
        .cast<Map<String, dynamic>>()
        .where((row) => row['is_disabled'] == true)
        .map((row) => (row['id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  String _visibilityLabel(String raw) {
    switch (raw.trim()) {
      case 'followers':
      case 'following':
        return context.l10n.tr('following');
      case 'public':
        return context.l10n.tr('public');
      default:
        return raw;
    }
  }

  String _postTypeLabel(String raw) {
    switch (raw.trim()) {
      case 'all':
        return context.l10n.tr('all');
      case 'post':
        return context.l10n.tr('posts');
      case 'market':
        return context.l10n.tr('marketplace');
      case 'service_offer':
        return context.l10n.tr('service_offer');
      case 'service_request':
        return context.l10n.tr('service_request');
      case 'lost_found':
        return context.l10n.tr('lost_found');
      default:
        return raw;
    }
  }

  String _authorTypeLabel(String raw) {
    switch (raw.trim()) {
      case 'all':
        return context.l10n.tr('all');
      case 'person':
        return context.l10n.tr('person');
      case 'business':
        return context.l10n.tr('business');
      case 'org':
        return context.l10n.tr('organization');
      default:
        return raw;
    }
  }

  String _escapeIlikeValue(String value) {
    return value
        .replaceAll(r'\', r'\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_')
        .replaceAll(',', ' ')
        .trim();
  }

  double _toRad(double degrees) => degrees * math.pi / 180.0;

  double _distanceKm(double lat1, double lng1, double lat2, double lng2) {
    final dLat = _toRad(lat2 - lat1);
    final dLng = _toRad(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRad(lat1)) *
            math.cos(_toRad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return 6371.0 * c;
  }

  Future<List<Map<String, dynamic>>> _fallbackProfileSearch(
    String query, {
    required bool useNearby,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    final pattern = _escapeIlikeValue(trimmed);
    final rows = await _db
        .from('profiles')
        .select(
          'id, full_name, business_name, job_title, account_type, city, zipcode, latitude, longitude, avatar_url, is_disabled',
        )
        .eq('is_disabled', false)
        .or(
          [
            'full_name.ilike.%$pattern%',
            'business_name.ilike.%$pattern%',
            'job_title.ilike.%$pattern%',
            'city.ilike.%$pattern%',
            'zipcode.ilike.%$pattern%',
          ].join(','),
        )
        .limit(50);

    final myId = _db.auth.currentUser?.id;
    final normalizedQuery = trimmed.toLowerCase();
    final results = <Map<String, dynamic>>[];

    for (final row in (rows as List).cast<Map<String, dynamic>>()) {
      final id = (row['id'] ?? '').toString();
      if (id.isEmpty || id == myId) continue;

      final lat = (row['latitude'] as num?)?.toDouble();
      final lng = (row['longitude'] as num?)?.toDouble();
      double? distanceKm;

      if (_meLat != null && _meLng != null && lat != null && lng != null) {
        distanceKm = _distanceKm(_meLat!, _meLng!, lat, lng);
      }

      if (useNearby) {
        if (distanceKm == null || distanceKm > _meRadiusKm) {
          continue;
        }
      }

      final enriched = Map<String, dynamic>.from(row);
      if (distanceKm != null) {
        enriched['distance_km'] = distanceKm;
      }
      results.add(enriched);
    }

    int score(Map<String, dynamic> row) {
      final candidates = [
        (row['business_name'] ?? '').toString().toLowerCase(),
        (row['full_name'] ?? '').toString().toLowerCase(),
        (row['job_title'] ?? '').toString().toLowerCase(),
        (row['city'] ?? '').toString().toLowerCase(),
      ];

      for (final value in candidates) {
        if (value == normalizedQuery) return 0;
      }
      for (final value in candidates) {
        if (value.startsWith(normalizedQuery)) return 1;
      }
      for (final value in candidates) {
        if (value.contains(normalizedQuery)) return 2;
      }
      return 3;
    }

    results.sort((a, b) {
      final scoreCompare = score(a).compareTo(score(b));
      if (scoreCompare != 0) return scoreCompare;

      final aDist = (a['distance_km'] as num?)?.toDouble() ?? double.infinity;
      final bDist = (b['distance_km'] as num?)?.toDouble() ?? double.infinity;
      final distCompare = aDist.compareTo(bDist);
      if (distCompare != 0) return distCompare;

      final aName = ((a['business_name'] ?? a['full_name'] ?? '') as String).toLowerCase();
      final bName = ((b['business_name'] ?? b['full_name'] ?? '') as String).toLowerCase();
      return aName.compareTo(bName);
    });

    return results.take(30).toList();
  }

  SupabaseClient get _db => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _qCtrl.addListener(_onQueryChanged);
    _loadMyLocation();
  }

  Future<void> _loadMyLocation() async {
    try {
      final user = _db.auth.currentUser;
      if (user == null) {
        if (!mounted) return;
        setState(() => _profileLoaded = true);
        return;
      }

      final me = await _db
          .from('profiles')
          .select('latitude, longitude, radius_km')
          .eq('id', user.id)
          .single();

      _meLat = (me['latitude'] as num?)?.toDouble();
      _meLng = (me['longitude'] as num?)?.toDouble();
      _meRadiusKm = (me['radius_km'] as int?) ?? 5;
    } catch (_) {
      // ignore, fallback to non-nearby search
    }

    if (!mounted) return;
    setState(() => _profileLoaded = true);
  }

  void _onQueryChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _runSearch);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _qCtrl.dispose();
    super.dispose();
  }

  Future<void> _runSearch() async {
    final q = _qCtrl.text.trim();

    if (q.isEmpty) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = null;
        _profiles = [];
        _posts = [];
        _filtersExpanded = true;
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
      _filtersExpanded = false;
    });

    try {
      // ✅ Profiles
      if (_tab == SearchTab.profiles) {
        final useNearby = _nearbyOnly && _meLat != null && _meLng != null;

        final rpcRes = useNearby
            ? await _db.rpc('search_profiles_nearby', params: {
                'q': q,
                'viewer_lat': _meLat,
                'viewer_lng': _meLng,
                'radius_km': _meRadiusKm,
                'limit_n': 30,
                'sim_threshold': _simThreshold,
              })
            : await _db.rpc('search_profiles', params: {
                'q': q,
                'limit_n': 30,
              });

        final rows = (rpcRes as List<dynamic>).cast<Map<String, dynamic>>();
        final fallbackRows = await _fallbackProfileSearch(
          q,
          useNearby: useNearby,
        );
        final mergedById = <String, Map<String, dynamic>>{};
        for (final row in rows) {
          final id = (row['id'] ?? '').toString();
          if (id.isEmpty) continue;
          mergedById[id] = Map<String, dynamic>.from(row);
        }
        for (final row in fallbackRows) {
          final id = (row['id'] ?? '').toString();
          if (id.isEmpty) continue;
          mergedById.putIfAbsent(id, () => Map<String, dynamic>.from(row));
        }

        final disabledIds =
            await _disabledProfileIds(mergedById.keys);
        final myId = _db.auth.currentUser?.id;
        final visibleRows = mergedById.values.where((row) {
          final id = (row['id'] ?? '').toString();
          if (id.isEmpty) return false;
          if (id == myId) return false;
          return !disabledIds.contains(id);
        }).toList();

        if (!mounted) return;
        setState(() {
          _profiles = visibleRows;
          _posts = [];
          _loading = false;
        });
      } else {
        // ✅ Posts
        final user = _db.auth.currentUser;
        if (user == null) throw Exception('Not logged in');

        final scopeStr =
            _scope == SearchScope.following ? 'following' : 'public';
        final useNearby = _nearbyOnly && _meLat != null && _meLng != null;

        final res = useNearby
            ? await _db.rpc('search_posts_nearby_scoped', params: {
                'q': q,
                'viewer_id': user.id,
                'viewer_lat': _meLat,
                'viewer_lng': _meLng,
                'radius_km': _meRadiusKm,
                'scope': scopeStr,
                'limit_n': 30,
                'post_type_filter':
                    _selectedPostType == 'all' ? null : _selectedPostType,
                'author_type_filter':
                    _selectedAuthorType == 'all' ? null : _selectedAuthorType,
                'sim_threshold': _simThreshold,
              })
            : await _db.rpc('search_posts_scoped', params: {
                'q': q,
                'viewer_id': user.id,
                'scope': scopeStr,
                'limit_n': 30,
                'post_type_filter':
                    _selectedPostType == 'all' ? null : _selectedPostType,
                'author_type_filter':
                    _selectedAuthorType == 'all' ? null : _selectedAuthorType,
              });

        final rows = (res as List<dynamic>).cast<Map<String, dynamic>>();
        final disabledIds = await _disabledProfileIds(
          rows.map((row) => (row['user_id'] ?? row['profile_id'] ?? '').toString()),
        );
        final visibleRows = rows.where((row) {
          final authorId = (row['user_id'] ?? row['profile_id'] ?? '').toString();
          return !disabledIds.contains(authorId);
        }).toList();

        if (!mounted) return;
        setState(() {
          _posts = visibleRows;
          _profiles = [];
          _loading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _switchTab(SearchTab tab) {
    setState(() {
      _tab = tab;
      _error = null;
      _profiles = [];
      _posts = [];
      if (_qCtrl.text.trim().isEmpty) {
        _filtersExpanded = true;
      }
    });
    _runSearch();
  }


  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final q = _qCtrl.text.trim();

    return Scaffold(
      // ✅ Global sticky app bar (title clickable -> /feed)
      appBar: const GlobalAppBar(
        title: 'Allonssy!',
        showBackIfPossible: true,
        homeRoute: '/feed',
      ),
      bottomNavigationBar: const GlobalBottomNav(),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: TextField(
              controller: _qCtrl,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: l10n.tr('search_profiles_or_posts'),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: q.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _qCtrl.clear();
                          _runSearch();
                        },
                      ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onSubmitted: (_) => _runSearch(),
            ),
          ),
          if (q.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => setState(() => _filtersExpanded = !_filtersExpanded),
                child: Ink(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE6DDCE)),
                  ),
                  child: Row(
                    children: [
                      Icon(_filtersExpanded ? Icons.expand_less : Icons.tune),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _filtersExpanded
                              ? l10n.tr('hide_search_filters')
                              : l10n.tr('show_search_filters'),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (_filtersExpanded) ...[

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SegmentedButton<SearchTab>(
              segments: [
                ButtonSegment(
                  value: SearchTab.profiles,
                  label: Text(l10n.tr('profiles')),
                  icon: Icon(Icons.person_search),
                ),
                ButtonSegment(
                  value: SearchTab.posts,
                  label: Text(l10n.tr('posts')),
                  icon: Icon(Icons.article),
                ),
              ],
              selected: {_tab},
              onSelectionChanged: (s) => _switchTab(s.first),
            ),
          ),

          // ✅ Nearby toggle
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _nearbyOnly,
              title: Text(l10n.tr('nearby_only')),
              subtitle: Text(
                !_profileLoaded
                    ? l10n.tr('loading_your_location')
                    : !_nearbyOnly
                        ? l10n.tr('global_search')
                        : (_meLat == null || _meLng == null)
                        ? l10n.tr('location_not_set_fallback')
                        : l10n.tr(
                            'using_profile_radius',
                            args: {'radius': '$_meRadiusKm'},
                          ),
              ),
              onChanged: (v) {
                setState(() => _nearbyOnly = v);
                _runSearch();
              },
            ),
          ),

          // ✅ Fuzzy slider
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      l10n.tr('match_strictness'),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _strictnessLabel(_simThreshold),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
                Slider(
                  value: _simThreshold.clamp(0.15, 0.45).toDouble(),
                  min: 0.15,
                  max: 0.45,
                  divisions: 6,
                  label: _strictnessLabel(_simThreshold),
                  onChanged: (v) {
                    final clamped = v.clamp(0.15, 0.45).toDouble();
                    setState(() => _simThreshold = clamped);
                  },
                  onChangeEnd: (_) => _runSearch(),
                ),
                Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(l10n.tr('broader'), style: const TextStyle(fontSize: 12)),
                      Text(l10n.tr('exact'), style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
                Text(
                  l10n.tr('this_changes_match_quality'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),

          if (_tab == SearchTab.posts) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Expanded(
                    child: _DropdownBox(
                      label: l10n.tr('scope'),
                      child: DropdownButton<SearchScope>(
                        isExpanded: true,
                        value: _scope,
                        underline: const SizedBox.shrink(),
                        items: [
                          DropdownMenuItem(
                            value: SearchScope.public,
                            child: Text(l10n.tr('public')),
                          ),
                          DropdownMenuItem(
                            value: SearchScope.following,
                            child: Text(l10n.tr('following')),
                          ),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() => _scope = v);
                          _runSearch();
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _DropdownBox(
                      label: l10n.tr('post_type'),
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: _selectedPostType,
                        underline: const SizedBox.shrink(),
                        items: _postTypes
                            .map((t) => DropdownMenuItem(
                                  value: t,
                                  child: Text(_postTypeLabel(t)),
                                ))
                            .toList(),
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() => _selectedPostType = v);
                          _runSearch();
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: _DropdownBox(
                label: l10n.tr('author_type'),
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: _selectedAuthorType,
                  underline: const SizedBox.shrink(),
                  items: _authorTypes
                      .map((t) => DropdownMenuItem(
                            value: t,
                            child: Text(_authorTypeLabel(t)),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _selectedAuthorType = v);
                    _runSearch();
                  },
                ),
              ),
            ),
          ],

          const SizedBox(height: 8),
          ],
          Expanded(child: _buildBody(q)),
        ],
      ),
    );
  }

  Widget _buildBody(String q) {
    final l10n = context.l10n;
    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red),
              ),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: _runSearch, child: Text(l10n.tr('retry'))),
            ],
          ),
        ),
      );
    }

    if (q.isEmpty) return Center(child: Text(l10n.tr('type_something_to_search')));

    if (_tab == SearchTab.profiles) {
      if (_profiles.isEmpty) return Center(child: Text(l10n.tr('no_profiles_found')));

      return ListView.separated(
        itemCount: _profiles.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final p = _profiles[i];
          final id = (p['id'] ?? '').toString();
          final fullName = (p['full_name'] ?? '').toString();
          final bName = (p['business_name'] as String?) ?? '';
          final job = (p['job_title'] as String?) ?? '';
          
          final displayName =
              bName.isNotEmpty ? bName : (fullName.isEmpty ? l10n.tr('unnamed') : fullName);
          final accountType = (p['account_type'] ?? '').toString();
          final city = (p['city'] ?? '').toString();
          final zipcode = (p['zipcode'] ?? '').toString();
          final dist = (p['distance_km'] as num?)?.toDouble();

          return ListTile(
            leading: CircleAvatar(
              child: Text(displayName.trim().isEmpty ? '?' : displayName.trim()[0].toUpperCase()),
            ),
            title: Text(displayName),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (job.isNotEmpty)
                  Text(
                    job,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF0F766E),
                    ),
                  ),
                Text(
                  [
                    if (accountType.isNotEmpty) accountType,
                    if (dist != null) '${dist.toStringAsFixed(1)} km',
                    if (city.isNotEmpty || zipcode.isNotEmpty)
                      '${city.isEmpty ? '' : city}${city.isNotEmpty && zipcode.isNotEmpty ? ' • ' : ''}${zipcode.isEmpty ? '' : zipcode}',
                  ].where((x) => x.isNotEmpty).join(' — '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
            onTap: () => context.push('/p/$id'),
          );
        },
      );
    }

    if (_posts.isEmpty) return Center(child: Text(l10n.tr('no_posts_found')));

    return ListView.separated(
      itemCount: _posts.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final p = _posts[i];
        final content = (p['content'] ?? '').toString();
        final location = (p['location_name'] ?? '').toString();
        final postType = (p['post_type'] ?? '').toString();
        final authorType = (p['author_profile_type'] ?? '').toString();
        final visibility = (p['visibility'] ?? '').toString();
        final dist = (p['distance_km'] as num?)?.toDouble();
        final id = (p['id'] ?? '').toString();

        return ListTile(
          title: Text(
            content.isEmpty ? l10n.tr('no_text') : content,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            [
              if (postType.isNotEmpty) _postTypeLabel(postType),
              if (authorType.isNotEmpty) _authorTypeLabel(authorType),
              if (visibility.isNotEmpty) _visibilityLabel(visibility),
              if (dist != null) '${dist.toStringAsFixed(1)} km',
              if (location.isNotEmpty) location,
            ].join(' • '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: id.isEmpty ? null : () => context.push('/post/$id'),
        );
      },
    );
  }
}

class _DropdownBox extends StatelessWidget {
  const _DropdownBox({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
      child: child,
    );
  }
}
