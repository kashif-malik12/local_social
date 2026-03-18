import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:math' as math;

import '../core/localization/app_localizations.dart';
import '../core/food_categories.dart';
import '../models/post_model.dart';
import '../services/mention_service.dart';
import '../services/post_service.dart';
import '../widgets/global_app_bar.dart';
import '../widgets/global_bottom_nav.dart';

class FoodsScreen extends StatefulWidget {
  const FoodsScreen({super.key});

  @override
  State<FoodsScreen> createState() => _FoodsScreenState();
}

class _FoodsScreenState extends State<FoodsScreen> {
  static const int _kPageSize = 24;

  bool _loading = true;
  String? _error;
  String _selectedCategory = 'all';
  String _sortBy = 'date_desc';
  String _search = '';
  final _searchCtrl = TextEditingController();

  // Raw server rows, accumulated across pages
  List<Map<String, dynamic>> _rawRows = [];
  int _page = 0;
  bool _hasMore = true;
  bool _loadingMore = false;
  late final ScrollController _scrollCtrl;

  double? _meLat;
  double? _meLng;

  int _gridCount(double width) {
    if (width >= 1200) return 4;
    if (width >= 800) return 3;
    return 2;
  }

  double _gridAspectRatio(double width) {
    final count = _gridCount(width);
    if (count == 2) return 0.64;
    if (count == 3) return 0.8;
    return 0.98;
  }

  String _plainListingText(String raw) {
    return MentionService.parseTaggedContent(raw).body;
  }

  @override
  void initState() {
    super.initState();
    _scrollCtrl = ScrollController()..addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_loadingMore || !_hasMore) return;
    if (_scrollCtrl.position.pixels >= _scrollCtrl.position.maxScrollExtent - 400) {
      _loadMore();
    }
  }

  double _toRad(double d) => d * math.pi / 180;

  double? _distanceKm(Post p) {
    if (_meLat == null || _meLng == null) return null;
    const earth = 6371.0;
    final dLat = _toRad(p.latitude - _meLat!);
    final dLng = _toRad(p.longitude - _meLng!);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRad(_meLat!)) *
            math.cos(_toRad(p.latitude)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earth * c;
  }

  void _sortItems(List<Post> items) {
    switch (_sortBy) {
      case 'date_asc':
        items.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        break;
      case 'price_asc':
        items.sort((a, b) {
          final aPrice = a.marketPrice ?? double.infinity;
          final bPrice = b.marketPrice ?? double.infinity;
          return aPrice.compareTo(bPrice);
        });
        break;
      case 'price_desc':
        items.sort((a, b) {
          final aPrice = a.marketPrice ?? -1;
          final bPrice = b.marketPrice ?? -1;
          return bPrice.compareTo(aPrice);
        });
        break;
      case 'date_desc':
      default:
        items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
    }
  }

  /// Compute the filtered + sorted list from raw server rows.
  List<Post> get _filteredFoods {
    var items = _rawRows.map((e) => Post.fromMap(e)).toList();

    if (_selectedCategory != 'all') {
      items = items.where((p) => (p.marketCategory ?? '') == _selectedCategory).toList();
    }

    if (_search.trim().isNotEmpty) {
      final q = _search.trim().toLowerCase();
      items = items.where((p) {
        return (p.marketTitle ?? '').toLowerCase().contains(q) ||
            p.content.toLowerCase().contains(q) ||
            (p.authorBusinessName ?? '').toLowerCase().contains(q) ||
            (p.authorName ?? '').toLowerCase().contains(q) ||
            foodCategoryLabel(p.marketCategory ?? '').toLowerCase().contains(q);
      }).toList();
    }

    _sortItems(items);
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
      final me = Supabase.instance.client.auth.currentUser?.id;
      if (me != null) {
        final profile = await Supabase.instance.client
            .from('profiles')
            .select('latitude, longitude')
            .eq('id', me)
            .maybeSingle();
        _meLat = (profile?['latitude'] as num?)?.toDouble();
        _meLng = (profile?['longitude'] as num?)?.toDouble();
      }

      final data = await Supabase.instance.client
          .from('posts')
          .select('*, profiles(full_name, business_name, avatar_url, city, zipcode)')
          .inFilter('post_type', ['food_ad', 'food'])
          .order('created_at', ascending: false)
          .range(0, _kPageSize - 1);

      final rows = await PostService(Supabase.instance.client)
          .excludeUnavailableAuthorRows((data as List).cast<Map<String, dynamic>>());

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
      final from = _page * _kPageSize;
      final to = from + _kPageSize - 1;

      final data = await Supabase.instance.client
          .from('posts')
          .select('*, profiles(full_name, business_name, avatar_url, city, zipcode)')
          .inFilter('post_type', ['food_ad', 'food'])
          .order('created_at', ascending: false)
          .range(from, to);

      final rows = await PostService(Supabase.instance.client)
          .excludeUnavailableAuthorRows((data as List).cast<Map<String, dynamic>>());

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
    return Scaffold(
      appBar: GlobalAppBar(
        title: l10n.tr('food_ads'),
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
                hintText: l10n.tr('search_foods_category_restaurant'),
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
                DropdownMenuItem(value: 'all', child: Text(l10n.tr('all_food_categories'))),
                ...foodMainCategories.map(
                  (c) => DropdownMenuItem(value: c, child: Text(foodCategoryLabel(c))),
                ),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() => _selectedCategory = v);
                _load();
              },
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: l10n.tr('food_category'),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: DropdownButtonFormField<String>(
              initialValue: _sortBy,
              items: [
                DropdownMenuItem(value: 'date_desc', child: Text(l10n.tr('newest_first'))),
                DropdownMenuItem(value: 'date_asc', child: Text(l10n.tr('oldest_first'))),
                DropdownMenuItem(value: 'price_asc', child: Text(l10n.tr('price_low_to_high'))),
                DropdownMenuItem(value: 'price_desc', child: Text(l10n.tr('price_high_to_low'))),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() => _sortBy = v);
                _load();
              },
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: l10n.tr('sort_by'),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(l10n.tr('error_with_detail', args: {'error': '$_error'})))
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final posts = _filteredFoods;
                            final showFooter = _loadingMore || _hasMore;
                            final itemCount = posts.isEmpty
                                ? 1
                                : posts.length + (showFooter ? 1 : 0);

                            if (posts.isEmpty) {
                              return GridView.builder(
                                controller: _scrollCtrl,
                                padding: const EdgeInsets.all(12),
                                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: _gridCount(constraints.maxWidth),
                                  childAspectRatio: _gridAspectRatio(constraints.maxWidth),
                                  crossAxisSpacing: 10,
                                  mainAxisSpacing: 10,
                                ),
                                itemCount: 1,
                                itemBuilder: (context, index) => Center(
                                  child: Text(l10n.tr('no_food_ads_found')),
                                ),
                              );
                            }

                            return GridView.builder(
                              controller: _scrollCtrl,
                              padding: const EdgeInsets.all(12),
                              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: _gridCount(constraints.maxWidth),
                                childAspectRatio: _gridAspectRatio(
                                  constraints.maxWidth,
                                ),
                                crossAxisSpacing: 10,
                                mainAxisSpacing: 10,
                              ),
                              itemCount: itemCount,
                              itemBuilder: (context, index) {
                                // Footer item
                                if (index >= posts.length) {
                                  return Center(
                                    child: _loadingMore
                                        ? const Padding(
                                            padding: EdgeInsets.all(16),
                                            child: CircularProgressIndicator(),
                                          )
                                        : const SizedBox.shrink(),
                                  );
                                }

                                final p = posts[index];
                                final distanceKm = _distanceKm(p);
                                final title = (p.marketTitle ?? '').trim().isNotEmpty
                                    ? p.marketTitle!.trim()
                                    : _plainListingText(p.content);
                                final price = p.marketPrice != null
                                    ? '€${p.marketPrice!.toStringAsFixed(2)}'
                                    : l10n.tr('price_on_request');

                                return InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () => context.push('/foods/${p.id}'),
                                  child: Ink(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: Colors.black12),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        SizedBox(
                                          height: 112,
                                          child: ClipRRect(
                                            borderRadius: const BorderRadius.vertical(
                                              top: Radius.circular(12),
                                            ),
                                            child: Container(
                                              width: double.infinity,
                                              color: Colors.grey.shade200,
                                              padding: const EdgeInsets.all(6),
                                              child: p.imageUrl != null && p.imageUrl!.isNotEmpty
                                                  ? Image.network(
                                                      p.imageUrl!,
                                                      fit: BoxFit.contain,
                                                      alignment: Alignment.center,
                                                    )
                                                  : const Icon(Icons.fastfood, size: 40),
                                            ),
                                          ),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                title,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(fontWeight: FontWeight.w600),
                                              ),
                                              if (((p.authorBusinessName ?? p.authorName) ?? '').trim().isNotEmpty) ...[
                                                const SizedBox(height: 4),
                                                Text(
                                                  ((p.authorBusinessName ?? p.authorName) ?? '').trim(),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.grey.shade700,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                              const SizedBox(height: 4),
                                              Text(
                                                price,
                                                style: const TextStyle(fontWeight: FontWeight.bold),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                foodCategoryLabel(p.marketCategory ?? ''),
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey.shade700,
                                                ),
                                              ),
                                              if ((p.authorCity ?? '').trim().isNotEmpty ||
                                                  (p.authorZipcode ?? '').trim().isNotEmpty ||
                                                  distanceKm != null) ...[
                                                const SizedBox(height: 4),
                                                Text(
                                                  [
                                                    if ((p.authorCity ?? '').trim().isNotEmpty)
                                                      p.authorCity!.trim(),
                                                    if ((p.authorCity ?? '').trim().isEmpty &&
                                                        (p.authorZipcode ?? '').trim().isNotEmpty)
                                                      p.authorZipcode!.trim(),
                                                    if (distanceKm != null)
                                                      '${distanceKm.toStringAsFixed(1)} km',
                                                  ].join(' • '),
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: Colors.grey.shade600,
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
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
