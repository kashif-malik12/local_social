import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  final x = v.clamp(0.15, 0.45).toDouble();
  if (x <= 0.20) return 'Broad';
  if (x <= 0.30) return 'Balanced';
  if (x <= 0.40) return 'Precise';
  return 'Exact';
}

  bool _loading = false;
  String? _error;

  // ✅ Nearby toggle + viewer location from profile
  bool _nearbyOnly = true;
  double? _meLat;
  double? _meLng;
  int _meRadiusKm = 5;
  bool _profileLoaded = false;

  // ✅ Fuzzy threshold (lower = more results, more noise)
  double _simThreshold = 0.25;

  List<Map<String, dynamic>> _profiles = [];
  List<Map<String, dynamic>> _posts = [];

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
      if (user == null) return;

      final me = await _db
          .from('profiles')
          .select('latitude, longitude, radius_km')
          .eq('id', user.id)
          .single();

      _meLat = (me['latitude'] as num?)?.toDouble();
      _meLng = (me['longitude'] as num?)?.toDouble();
      _meRadiusKm = (me['radius_km'] as int?) ?? 5;
    } catch (_) {
      // ignore, will fallback to non-nearby search
    } finally {
      if (!mounted) return;
      setState(() => _profileLoaded = true);
    }
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
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // ✅ Profiles: nearby + fuzzy if we have location and toggle on, else fallback to old rpc
      if (_tab == SearchTab.profiles) {
        final useNearby = _nearbyOnly && _meLat != null && _meLng != null;

        final res = useNearby
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

        final rows = (res as List<dynamic>).cast<Map<String, dynamic>>();

        if (!mounted) return;
        setState(() {
          _profiles = rows;
          _posts = [];
          _loading = false;
        });
      } else {
        // ✅ Posts: nearby + scoped + fuzzy if we have location and toggle on, else fallback to scoped search
        final user = _db.auth.currentUser;
        if (user == null) throw Exception('Not logged in');

        final scopeStr = _scope == SearchScope.following ? 'following' : 'public';
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

        if (!mounted) return;
        setState(() {
          _posts = rows;
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
    });
    _runSearch();
  }

  @override
  Widget build(BuildContext context) {
    final q = _qCtrl.text.trim();

    return Scaffold(
      appBar: AppBar(title: const Text('Search')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: TextField(
              controller: _qCtrl,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search profiles or posts…',
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SegmentedButton<SearchTab>(
              segments: const [
                ButtonSegment(
                  value: SearchTab.profiles,
                  label: Text('Profiles'),
                  icon: Icon(Icons.person_search),
                ),
                ButtonSegment(
                  value: SearchTab.posts,
                  label: Text('Posts'),
                  icon: Icon(Icons.article),
                ),
              ],
              selected: {_tab},
              onSelectionChanged: (s) => _switchTab(s.first),
            ),
          ),

          // ✅ Nearby toggle (works for both tabs)
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _nearbyOnly,
              title: const Text('Nearby only'),
              subtitle: Text(
                !_profileLoaded
                    ? 'Loading your location…'
                    : (_meLat == null || _meLng == null)
                        ? 'Location not set in your profile (fallback to global search)'
                        : 'Using radius $_meRadiusKm km',
              ),
              onChanged: (v) {
                setState(() => _nearbyOnly = v);
                _runSearch();
              },
            ),
          ),

          // ✅ Fuzzy slider (optional quick control)
          Padding(
  padding: const EdgeInsets.symmetric(horizontal: 12),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          const Text(
            'Match strictness',
            style: TextStyle(fontWeight: FontWeight.w600),
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
      const Padding(
        padding: EdgeInsets.only(top: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Broader', style: TextStyle(fontSize: 12)),
            Text('Exact', style: TextStyle(fontSize: 12)),
          ],
        ),
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
                      label: 'Scope',
                      child: DropdownButton<SearchScope>(
                        isExpanded: true,
                        value: _scope,
                        underline: const SizedBox.shrink(),
                        items: const [
                          DropdownMenuItem(
                            value: SearchScope.public,
                            child: Text('Public'),
                          ),
                          DropdownMenuItem(
                            value: SearchScope.following,
                            child: Text('Following'),
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
                      label: 'Post Type',
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: _selectedPostType,
                        underline: const SizedBox.shrink(),
                        items: _postTypes
                            .map((t) => DropdownMenuItem(
                                  value: t,
                                  child: Text(t),
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
                label: 'Author Type',
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: _selectedAuthorType,
                  underline: const SizedBox.shrink(),
                  items: _authorTypes
                      .map((t) => DropdownMenuItem(
                            value: t,
                            child: Text(t),
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
          Expanded(child: _buildBody(q)),
        ],
      ),
    );
  }

  Widget _buildBody(String q) {
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
              ElevatedButton(onPressed: _runSearch, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    if (q.isEmpty) return const Center(child: Text('Type something to search.'));

    if (_tab == SearchTab.profiles) {
      if (_profiles.isEmpty) {
        return const Center(child: Text('No profiles found.'));
      }

      return ListView.separated(
        itemCount: _profiles.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final p = _profiles[i];
          final id = (p['id'] ?? '').toString();
          final fullName = (p['full_name'] ?? '').toString();
          final accountType = (p['account_type'] ?? '').toString();
          final city = (p['city'] ?? '').toString();
          final zipcode = (p['zipcode'] ?? '').toString();
          final dist = (p['distance_km'] as num?)?.toDouble();

          return ListTile(
            leading: CircleAvatar(
              child: Text(fullName.trim().isEmpty ? '?' : fullName.trim()[0]),
            ),
            title: Text(fullName.isEmpty ? 'Unnamed' : fullName),
            subtitle: Text(
              [
                if (accountType.isNotEmpty) accountType,
                if (dist != null) '${dist.toStringAsFixed(1)} km',
                if (city.isNotEmpty || zipcode.isNotEmpty)
                  '${city.isEmpty ? '' : city}${city.isNotEmpty && zipcode.isNotEmpty ? ' • ' : ''}${zipcode.isEmpty ? '' : zipcode}',
              ].where((x) => x.isNotEmpty).join(' — '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => context.push('/p/$id'),
          );
        },
      );
    }

    if (_posts.isEmpty) return const Center(child: Text('No posts found.'));

    return ListView.separated(
      itemCount: _posts.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final p = _posts[i];
        final content = (p['content'] ?? '').toString();
        final location = (p['location_name'] ?? '').toString();
        final postType = (p['post_type'] ?? '').toString();
        final authorType = (p['author_profile_type'] ?? '').toString();
        final visibility = (p['visibility'] ?? '').toString();
        final dist = (p['distance_km'] as num?)?.toDouble();

        return ListTile(
          title: Text(
            content.isEmpty ? '(no text)' : content,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            [
              if (postType.isNotEmpty) postType,
              if (authorType.isNotEmpty) authorType,
              if (visibility.isNotEmpty) visibility,
              if (dist != null) '${dist.toStringAsFixed(1)} km',
              if (location.isNotEmpty) location,
            ].join(' • '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
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