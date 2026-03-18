import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:math' as math;

import '../core/localization/app_localizations.dart';
import '../core/service_categories.dart';
import '../models/post_model.dart';
import '../services/mention_service.dart';
import '../services/post_service.dart';
import '../widgets/global_app_bar.dart';
import '../widgets/global_bottom_nav.dart';

class GigsScreen extends StatefulWidget {
  const GigsScreen({super.key});

  @override
  State<GigsScreen> createState() => _GigsScreenState();
}

class _GigsScreenState extends State<GigsScreen> {
  static const int _kPageSize = 20;

  bool _loading = true;
  String? _error;
  String _selectedCategory = 'all';
  String _selectedType = 'all';
  String _pricingFilter = 'all';
  String _sortBy = 'date_desc';
  String _search = '';
  final TextEditingController _searchCtrl = TextEditingController();

  // Raw server rows, accumulated across pages
  List<Map<String, dynamic>> _rawRows = [];
  int _page = 0;
  bool _hasMore = true;
  bool _loadingMore = false;
  late final ScrollController _scrollCtrl;

  double? _meLat;
  double? _meLng;
  bool _showFilters = false;

  int get _activeFilterCount {
    int count = 0;
    if (_selectedCategory != 'all') count++;
    if (_selectedType != 'all') count++;
    if (_pricingFilter != 'all') count++;
    if (_sortBy != 'date_desc') count++;
    return count;
  }

  int _gridCount(double width) {
    if (width >= 1200) return 4;
    if (width >= 800) return 3;
    return 2;
  }

  double _gridAspectRatio(double width) {
    final count = _gridCount(width);
    if (count == 2) return 0.58;
    if (count == 3) return 0.74;
    return 0.92;
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

  bool _isServicePost(Post p) =>
      p.postType == 'service_offer' || p.postType == 'service_request';

  String _typeLabel(String? postType) {
    if (postType == 'service_offer') return context.l10n.tr('offering');
    if (postType == 'service_request') return context.l10n.tr('requesting');
    return '';
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

  String _formatCreatedDate(DateTime dt) {
    final d = dt.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year}';
  }

  String _plainListingText(String raw) {
    return MentionService.parseTaggedContent(raw).body;
  }

  void _sortItems(List<Post> items) {
    switch (_sortBy) {
      case 'date_asc':
        items.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        break;
      case 'price_asc':
        items.sort((a, b) {
          final aPrice = a.marketPrice;
          final bPrice = b.marketPrice;
          if (aPrice == null && bPrice == null) return 0;
          if (aPrice == null) return 1;
          if (bPrice == null) return -1;
          return aPrice.compareTo(bPrice);
        });
        break;
      case 'price_desc':
        items.sort((a, b) {
          final aPrice = a.marketPrice;
          final bPrice = b.marketPrice;
          if (aPrice == null && bPrice == null) return 0;
          if (aPrice == null) return 1;
          if (bPrice == null) return -1;
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
  List<Post> get _filteredGigs {
    var items = _rawRows.map((e) => Post.fromMap(e)).where(_isServicePost).toList();

    if (_selectedCategory != 'all') {
      items = items
          .where((p) => (p.marketCategory ?? '').trim() == _selectedCategory)
          .toList();
    }

    if (_selectedType != 'all') {
      items = items.where((p) => p.postType == _selectedType).toList();
    }

    if (_pricingFilter != 'all') {
      items = items.where((p) {
        final hasPrice = p.marketPrice != null;
        if (_pricingFilter == 'priced') return hasPrice;
        if (_pricingFilter == 'unpriced') return !hasPrice;
        return true;
      }).toList();
    }

    final q = _search.trim().toLowerCase();
    if (q.isNotEmpty) {
      items = items.where((p) {
        final title = (p.marketTitle ?? '').toLowerCase();
        final content = p.content.toLowerCase();
        final provider = (p.authorName ?? '').toLowerCase();
        final category = serviceCategoryLabel(p.marketCategory ?? '').toLowerCase();
        return title.contains(q) ||
            content.contains(q) ||
            provider.contains(q) ||
            category.contains(q);
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
          .select(PostService.postSelect)
          .inFilter('post_type', ['service_offer', 'service_request'])
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
          .select(PostService.postSelect)
          .inFilter('post_type', ['service_offer', 'service_request'])
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
        title: l10n.tr('gigs'),
        showBackIfPossible: true,
        homeRoute: '/feed',
      ),
      bottomNavigationBar: const GlobalBottomNav(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/create-post'),
        icon: const Icon(Icons.add),
        label: Text(l10n.tr('post_a_service')),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: TextField(
              controller: _searchCtrl,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: l10n.tr('search_services_category_provider'),
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
              onSubmitted: (value) {
                setState(() => _search = value);
                _load();
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: Row(
              children: [
                ActionChip(
                  avatar: Icon(
                    _showFilters ? Icons.expand_less : Icons.tune,
                    size: 18,
                  ),
                  label: Text(l10n.tr('filters')),
                  onPressed: () => setState(() => _showFilters = !_showFilters),
                  backgroundColor: _activeFilterCount > 0
                      ? Theme.of(context).colorScheme.primaryContainer
                      : null,
                ),
                if (_activeFilterCount > 0) ...[
                  const SizedBox(width: 8),
                  Text(
                    '($_activeFilterCount)',
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 4),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _selectedCategory = 'all';
                        _selectedType = 'all';
                        _pricingFilter = 'all';
                        _sortBy = 'date_desc';
                      });
                      _load();
                    },
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(l10n.tr('clear')),
                  ),
                ],
              ],
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            child: _showFilters
                ? Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                        child: Row(
                          children: [
                            Text(l10n.tr('category_label')),
                            const SizedBox(width: 12),
                            Expanded(
                              child: DropdownButton<String>(
                                value: _selectedCategory,
                                isExpanded: true,
                                items: [
                                  DropdownMenuItem(
                                    value: 'all',
                                    child: Text(l10n.tr('all_categories')),
                                  ),
                                  ...serviceMainCategories.map(
                                    (c) => DropdownMenuItem(
                                      value: c,
                                      child: Text(serviceCategoryLabel(c)),
                                    ),
                                  ),
                                ],
                                onChanged: (v) {
                                  if (v == null) return;
                                  setState(() => _selectedCategory = v);
                                  _load();
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                        child: Row(
                          children: [
                            Text(l10n.tr('type_label')),
                            const SizedBox(width: 42),
                            Expanded(
                              child: DropdownButton<String>(
                                value: _selectedType,
                                isExpanded: true,
                                items: [
                                  DropdownMenuItem(value: 'all', child: Text(l10n.tr('all_types'))),
                                  DropdownMenuItem(
                                    value: 'service_offer',
                                    child: Text(l10n.tr('offering')),
                                  ),
                                  DropdownMenuItem(
                                    value: 'service_request',
                                    child: Text(l10n.tr('requesting')),
                                  ),
                                ],
                                onChanged: (v) {
                                  if (v == null) return;
                                  setState(() => _selectedType = v);
                                  _load();
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                        child: Row(
                          children: [
                            Text(l10n.tr('sort_label')),
                            const SizedBox(width: 40),
                            Expanded(
                              child: DropdownButton<String>(
                                value: _sortBy,
                                isExpanded: true,
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
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                        child: Row(
                          children: [
                            Text('${l10n.tr('price')}:'),
                            const SizedBox(width: 34),
                            Expanded(
                              child: DropdownButton<String>(
                                value: _pricingFilter,
                                isExpanded: true,
                                items: [
                                  DropdownMenuItem(value: 'all', child: Text(l10n.tr('all'))),
                                  DropdownMenuItem(value: 'priced', child: Text(l10n.tr('with_price'))),
                                  DropdownMenuItem(value: 'unpriced', child: Text(l10n.tr('without_price'))),
                                ],
                                onChanged: (v) {
                                  if (v == null) return;
                                  setState(() => _pricingFilter = v);
                                  _load();
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
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
                            final posts = _filteredGigs;
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
                                  child: Text(l10n.tr('no_service_posts_found')),
                                ),
                              );
                            }

                            return GridView.builder(
                              controller: _scrollCtrl,
                              padding: const EdgeInsets.all(12),
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
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
                                final myId = Supabase.instance.client.auth.currentUser?.id;
                                final canSendOffer = myId != null && p.userId != myId;
                                final distanceKm = _distanceKm(p);
                                final title = (p.marketTitle ?? '').trim().isNotEmpty
                                    ? p.marketTitle!.trim()
                                    : _plainListingText(p.content);
                                final String priceText;
                                if (p.marketPrice != null) {
                                  if (p.marketPriceMax != null && p.marketPriceMax! > p.marketPrice!) {
                                    priceText = '€${p.marketPrice!.toStringAsFixed(2)} – €${p.marketPriceMax!.toStringAsFixed(2)}';
                                  } else {
                                    priceText = '€${p.marketPrice!.toStringAsFixed(2)}';
                                  }
                                } else {
                                  priceText = p.postType == 'service_request' ? l10n.tr('budget_open') : l10n.tr('rate_on_request');
                                }

                                return InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () => context.push('/gigs/service/${p.id}'),
                                  child: Ink(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: Colors.black12),
                                      color: Theme.of(context).cardColor,
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
                                              child: p.imageUrl != null &&
                                                      p.imageUrl!.isNotEmpty
                                                  ? Image.network(
                                                      p.imageUrl!,
                                                      fit: BoxFit.contain,
                                                      alignment: Alignment.center,
                                                    )
                                                  : const Icon(
                                                      Icons.miscellaneous_services_outlined,
                                                      size: 40,
                                                      color: Colors.black45,
                                                    ),
                                            ),
                                          ),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                title,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                priceText,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                serviceCategoryLabel(p.marketCategory ?? ''),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey.shade700,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                _formatCreatedDate(p.createdAt),
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.grey.shade600,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                _typeLabel(p.postType),
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.grey.shade600,
                                                ),
                                              ),
                                              if ((p.authorCity ?? '').trim().isNotEmpty ||
                                                  (p.authorZipcode ?? '').trim().isNotEmpty ||
                                                  distanceKm != null)
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
                                              const SizedBox(height: 8),
                                              SizedBox(
                                                width: double.infinity,
                                                child: OutlinedButton.icon(
                                                  style: OutlinedButton.styleFrom(
                                                    visualDensity: VisualDensity.compact,
                                                    padding: const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                      vertical: 10,
                                                    ),
                                                  ),
                                                  onPressed: canSendOffer
                                                      ? () => context.push(
                                                            '/offer-chat/post/${p.id}/user/${p.userId}',
                                                          )
                                                      : null,
                                                  icon: const Icon(
                                                    Icons.local_offer_outlined,
                                                    size: 16,
                                                  ),
                                                  label: Text(l10n.tr('send_offer')),
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
