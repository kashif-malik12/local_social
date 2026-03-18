import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/localization/app_localizations.dart';
import '../core/restaurant_categories.dart';
import '../widgets/global_app_bar.dart';
import '../widgets/global_bottom_nav.dart';

class RestaurantsScreen extends StatefulWidget {
  const RestaurantsScreen({super.key});

  @override
  State<RestaurantsScreen> createState() => _RestaurantsScreenState();
}

class _RestaurantsScreenState extends State<RestaurantsScreen> {
  static const int _kPageSize = 30;

  bool _loading = true;
  String? _error;
  String _search = '';
  String _selectedCategory = 'all';
  double _maxDistanceKm = 20;
  final _searchCtrl = TextEditingController();

  double? _meLat;
  double? _meLng;

  // Raw server rows, accumulated across pages
  List<Map<String, dynamic>> _rawRows = [];
  int _page = 0;
  bool _hasMore = true;
  bool _loadingMore = false;
  late final ScrollController _scrollCtrl;

  @override
  void dispose() {
    _scrollCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _scrollCtrl = ScrollController()..addListener(_onScroll);
    _load();
  }

  void _onScroll() {
    if (_loadingMore || !_hasMore) return;
    if (_scrollCtrl.position.pixels >= _scrollCtrl.position.maxScrollExtent - 400) {
      _loadMore();
    }
  }

  double _distanceKm(double lat1, double lng1, double lat2, double lng2) {
    const earth = 6371.0;
    final dLat = _toRad(lat2 - lat1);
    final dLng = _toRad(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRad(lat1)) *
            math.cos(_toRad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earth * c;
  }

  double _toRad(double d) => d * math.pi / 180;

  /// Apply client-side category/search/distance filters and sort by distance.
  List<Map<String, dynamic>> get _filteredRestaurants {
    var items = List<Map<String, dynamic>>.from(_rawRows);

    if (_selectedCategory != 'all') {
      items = items
          .where((r) => (r['restaurant_type'] ?? '').toString() == _selectedCategory)
          .toList();
    }

    if (_search.trim().isNotEmpty) {
      final q = _search.toLowerCase().trim();
      items = items.where((r) {
        return (r['business_name'] ?? '').toString().toLowerCase().contains(q) ||
            (r['full_name'] ?? '').toString().toLowerCase().contains(q) ||
            (r['bio'] ?? '').toString().toLowerCase().contains(q) ||
            (r['business_profile'] ?? '').toString().toLowerCase().contains(q) ||
            (r['city'] ?? '').toString().toLowerCase().contains(q) ||
            restaurantCategoryLabel((r['restaurant_type'] ?? '').toString())
                .toLowerCase()
                .contains(q);
      }).toList();
    }

    if (_meLat != null && _meLng != null) {
      items = items.where((r) {
        final lat = (r['latitude'] as num?)?.toDouble();
        final lng = (r['longitude'] as num?)?.toDouble();
        if (lat == null || lng == null) return false;
        return _distanceKm(_meLat!, _meLng!, lat, lng) <= _maxDistanceKm;
      }).toList();

      items.sort((a, b) {
        final aLat = (a['latitude'] as num?)?.toDouble();
        final aLng = (a['longitude'] as num?)?.toDouble();
        final bLat = (b['latitude'] as num?)?.toDouble();
        final bLng = (b['longitude'] as num?)?.toDouble();
        final ad = (aLat != null && aLng != null)
            ? _distanceKm(_meLat!, _meLng!, aLat, aLng)
            : 9999.0;
        final bd = (bLat != null && bLng != null)
            ? _distanceKm(_meLat!, _meLng!, bLat, bLng)
            : 9999.0;
        return ad.compareTo(bd);
      });
    }

    return items;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _rawRows = [];
      _page = 0;
      _hasMore = true;
    });

    try {
      final db = Supabase.instance.client;
      final me = db.auth.currentUser;

      if (me != null) {
        final myProfile = await db
            .from('profiles')
            .select('latitude, longitude')
            .eq('id', me.id)
            .maybeSingle();
        _meLat = (myProfile?['latitude'] as num?)?.toDouble();
        _meLng = (myProfile?['longitude'] as num?)?.toDouble();
      }

      List<Map<String, dynamic>> rows;
      try {
        final data = await db
            .from('profiles')
            .select('id, full_name, bio, business_profile, avatar_url, city, latitude, longitude, is_restaurant, restaurant_type, account_type, business_name, job_title, is_disabled')
            .eq('is_restaurant', true)
            .eq('is_disabled', false)
            .order('business_name')
            .range(0, _kPageSize - 1);
        rows = (data as List).cast<Map<String, dynamic>>();
      } on PostgrestException {
        final data = await db
            .from('profiles')
            .select('id, full_name, bio, business_profile, avatar_url, city, latitude, longitude, account_type, business_name, job_title, is_disabled')
            .eq('account_type', 'business')
            .order('business_name')
            .range(0, _kPageSize - 1);
        rows = (data as List)
            .cast<Map<String, dynamic>>()
            .where((r) => r['is_disabled'] != true)
            .toList();
      }

      if (!mounted) return;
      setState(() {
        _rawRows = rows;
        _page = 1;
        _hasMore = rows.length == _kPageSize;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);

    try {
      final db = Supabase.instance.client;
      final from = _page * _kPageSize;
      final to = from + _kPageSize - 1;

      List<Map<String, dynamic>> rows;
      try {
        final data = await db
            .from('profiles')
            .select('id, full_name, bio, business_profile, avatar_url, city, latitude, longitude, is_restaurant, restaurant_type, account_type, business_name, job_title, is_disabled')
            .eq('is_restaurant', true)
            .eq('is_disabled', false)
            .order('business_name')
            .range(from, to);
        rows = (data as List).cast<Map<String, dynamic>>();
      } on PostgrestException {
        final data = await db
            .from('profiles')
            .select('id, full_name, bio, business_profile, avatar_url, city, latitude, longitude, account_type, business_name, job_title, is_disabled')
            .eq('account_type', 'business')
            .order('business_name')
            .range(from, to);
        rows = (data as List)
            .cast<Map<String, dynamic>>()
            .where((r) => r['is_disabled'] != true)
            .toList();
      }

      if (!mounted) return;
      setState(() {
        _rawRows = [..._rawRows, ...rows];
        _page++;
        _hasMore = rows.length == _kPageSize;
      });
    } catch (_) {
      // silently ignore load-more errors
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final restaurants = _filteredRestaurants;

    return Scaffold(
      appBar: GlobalAppBar(
        title: l10n.tr('restaurants'),
        showBackIfPossible: true,
        homeRoute: '/feed',
      ),
      bottomNavigationBar: const GlobalBottomNav(),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: l10n.tr('search_restaurants'),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _search.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _search = '');
                          _load();
                        },
                        icon: const Icon(Icons.clear),
                      ),
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (v) {
                setState(() => _search = v);
                _load();
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: DropdownButtonFormField<String>(
              initialValue: _selectedCategory,
              items: [
                DropdownMenuItem(value: 'all', child: Text(l10n.tr('all_types'))),
                ...restaurantMainCategories.map(
                  (c) => DropdownMenuItem(value: c, child: Text(restaurantCategoryLabel(c))),
                ),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() => _selectedCategory = v);
                _load();
              },
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: l10n.tr('restaurant_category'),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(
              children: [
                Text(l10n.tr('distance_label')),
                Expanded(
                  child: Slider(
                    value: _maxDistanceKm,
                    min: 1,
                    max: 50,
                    divisions: 49,
                    label: '${_maxDistanceKm.toStringAsFixed(0)} km',
                    onChanged: (v) => setState(() => _maxDistanceKm = v),
                    onChangeEnd: (_) => _load(),
                  ),
                ),
                Text('${_maxDistanceKm.toStringAsFixed(0)} km'),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(l10n.tr('error_with_detail', args: {'error': '$_error'})))
                    : restaurants.isEmpty
                        ? Center(child: Text(l10n.tr('no_restaurants_found')))
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.separated(
                              controller: _scrollCtrl,
                              itemCount: restaurants.length + (_loadingMore || _hasMore ? 1 : 0),
                              separatorBuilder: (context, index) => const Divider(height: 1),
                              itemBuilder: (context, i) {
                                // Footer item
                                if (i >= restaurants.length) {
                                  return Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Center(
                                      child: _loadingMore
                                          ? const CircularProgressIndicator()
                                          : const SizedBox.shrink(),
                                    ),
                                  );
                                }

                                final r = restaurants[i];
                                final lat = (r['latitude'] as num?)?.toDouble();
                                final lng = (r['longitude'] as num?)?.toDouble();
                                final dist = (_meLat != null && _meLng != null && lat != null && lng != null)
                                    ? _distanceKm(_meLat!, _meLng!, lat, lng)
                                    : null;

                                final id = (r['id'] ?? '').toString();
                                final bName = (r['business_name'] as String?) ?? (r['full_name'] as String?) ?? l10n.tr('restaurant');
                                final job = r['job_title'] as String?;
                                final businessProfile = (r['business_profile'] as String?) ?? '';

                                return Card(
                                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  child: ListTile(
                                    onTap: id.isEmpty ? null : () => context.push('/p/$id'),
                                    contentPadding: const EdgeInsets.all(12),
                                    leading: ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: Container(
                                        width: 64,
                                        height: 64,
                                        color: Colors.grey.shade200,
                                        padding: const EdgeInsets.all(6),
                                        child: (r['avatar_url'] ?? '').toString().isNotEmpty
                                            ? Image.network(
                                                (r['avatar_url'] ?? '').toString(),
                                                fit: BoxFit.contain,
                                              )
                                            : const Icon(Icons.storefront_outlined),
                                      ),
                                    ),
                                    title: Row(
                                      children: [
                                        Expanded(child: Text(bName)),
                                        const Icon(Icons.verified, color: Colors.green, size: 18),
                                      ],
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        if (job != null && job.isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(bottom: 2),
                                            child: Text(
                                              job,
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        Text(
                                          '${(r['restaurant_type'] ?? '').toString().isNotEmpty ? restaurantCategoryLabel((r['restaurant_type'] ?? '').toString()) : l10n.tr('restaurant')}'
                                          '${dist != null ? ' • ${dist.toStringAsFixed(1)} km' : ''}'
                                          '${(r['city'] ?? '').toString().isNotEmpty ? ' • ${(r['city'] ?? '').toString()}' : ''}',
                                        ),
                                        if (businessProfile.trim().isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 4),
                                            child: Text(
                                              businessProfile.trim(),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
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
        ],
      ),
    );
  }
}
