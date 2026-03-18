import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:math' as math;

import '../core/localization/app_localizations.dart';
import '../core/market_categories.dart';
import '../models/post_model.dart';
import '../services/mention_service.dart';
import '../services/post_service.dart';
import '../widgets/global_app_bar.dart';
import '../widgets/global_bottom_nav.dart';

class MarketplaceScreen extends StatefulWidget {
  const MarketplaceScreen({super.key});

  @override
  State<MarketplaceScreen> createState() => _MarketplaceScreenState();
}

class _MarketplaceScreenState extends State<MarketplaceScreen> {
  bool _loading = true;
  String? _error;
  String _selectedCategory = 'all';
  String _selectedIntent = 'all';
  String _sortBy = 'date_desc';
  String _search = '';
  final TextEditingController _searchCtrl = TextEditingController();
  List<Post> _posts = [];
  double? _meLat;
  double? _meLng;
  bool _showFilters = false;

  int get _activeFilterCount {
    int count = 0;
    if (_selectedCategory != 'all') count++;
    if (_selectedIntent != 'all') count++;
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
    if (count == 3) return 0.70;
    return 0.88;
  }

  String _plainListingText(String raw) {
    return MentionService.parseTaggedContent(raw).body;
  }

  Widget _buildResponsiveDropdownRow({
    required String label,
    required Widget child,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 360;
        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label),
              const SizedBox(height: 8),
              child,
            ],
          );
        }

        return Row(
          children: [
            SizedBox(
              width: 72,
              child: Text(label),
            ),
            const SizedBox(width: 12),
            Expanded(child: child),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String _intentLabel(String? intent) {
    switch (intent) {
      case 'buying':
        return context.l10n.tr('buying');
      case 'selling':
        return context.l10n.tr('selling');
      default:
        return (intent ?? '').trim();
    }
  }

  bool _matchesIntentByContent(Post post, String targetIntent) {
    final text = post.content.toLowerCase();
    if (targetIntent == 'selling') {
      return text.contains('sell') ||
          text.contains('for sale') ||
          text.contains('wts');
    }

    if (targetIntent == 'buying') {
      return text.contains('buy') ||
          text.contains('looking for') ||
          text.contains('wtb');
    }

    return true;
  }

  double? _priceFromContent(String raw) {
    final patterns = [
      RegExp(r'price\s*:\s*(\d+(?:[.,]\d{1,2})?)', caseSensitive: false),
      RegExp(r'price\s*:\s*(?:eur|euro|€|\$)\s*(\d+(?:[.,]\d{1,2})?)',
          caseSensitive: false),
      RegExp(r'(?:eur|euro|€)\s*(\d+(?:[.,]\d{1,2})?)', caseSensitive: false),
      RegExp(r'(\d+(?:[.,]\d{1,2})?)\s*eur', caseSensitive: false),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(raw);
      if (match != null) {
        final value = (match.group(1) ?? '').replaceAll(',', '.');
        final parsed = double.tryParse(value);
        if (parsed != null) return parsed;
      }
    }

    return null;
  }

  double _toRad(double d) => d * math.pi / 180;

  double? _distanceKm(Post p) {
    if (_meLat == null || _meLng == null) return null;
    final lat2 = p.latitude;
    final lng2 = p.longitude;
    const earth = 6371.0;
    final dLat = _toRad(lat2 - _meLat!);
    final dLng = _toRad(lng2 - _meLng!);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRad(_meLat!)) *
            math.cos(_toRad(lat2)) *
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

  void _sortItems(List<Post> items) {
    switch (_sortBy) {
      case 'date_asc':
        items.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        break;
      case 'price_asc':
        items.sort((a, b) {
          final aPrice = a.marketPrice ?? _priceFromContent(a.content) ?? double.infinity;
          final bPrice = b.marketPrice ?? _priceFromContent(b.content) ?? double.infinity;
          return aPrice.compareTo(bPrice);
        });
        break;
      case 'price_desc':
        items.sort((a, b) {
          final aPrice = a.marketPrice ?? _priceFromContent(a.content) ?? -1;
          final bPrice = b.marketPrice ?? _priceFromContent(b.content) ?? -1;
          return bPrice.compareTo(aPrice);
        });
        break;
      case 'date_desc':
      default:
        items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
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
          .eq('post_type', 'market')
          .order('created_at', ascending: false)
          .limit(120);

      final rows = await PostService(Supabase.instance.client)
          .excludeUnavailableAuthorRows((data as List).cast<Map<String, dynamic>>());

      var items = rows.map((e) => Post.fromMap(e)).toList();

      if (_selectedCategory != 'all') {
        items = items
            .where((p) => (p.marketCategory ?? '').trim() == _selectedCategory)
            .toList();
      }

      if (_selectedIntent != 'all') {
        items = items.where((p) {
          final intent = (p.marketIntent ?? '').trim();
          if (intent.isNotEmpty) {
            return intent == _selectedIntent;
          }
          return _matchesIntentByContent(p, _selectedIntent);
        }).toList();
      }

      final q = _search.trim().toLowerCase();
      if (q.isNotEmpty) {
        items = items.where((p) {
          final title = (p.marketTitle ?? '').toLowerCase();
          final content = p.content.toLowerCase();
          final seller = (p.authorName ?? '').toLowerCase();
          final category = marketCategoryLabel(p.marketCategory ?? '').toLowerCase();
          return title.contains(q) ||
              content.contains(q) ||
              seller.contains(q) ||
              category.contains(q);
        }).toList();
      }

      _sortItems(items);

      if (!mounted) return;
      setState(() {
        _posts = items;
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

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: GlobalAppBar(
        title: l10n.tr('marketplace'),
        showBackIfPossible: true,
        homeRoute: '/feed',
      ),
      bottomNavigationBar: const GlobalBottomNav(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/create-post'),
        icon: const Icon(Icons.add),
        label: Text(l10n.tr('sell_buy')),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: TextField(
              controller: _searchCtrl,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: l10n.tr('search_products_category_seller'),
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
                        _selectedIntent = 'all';
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
                        child: _buildResponsiveDropdownRow(
                          label: l10n.tr('category_label'),
                          child: DropdownButton<String>(
                            value: _selectedCategory,
                            isExpanded: true,
                            items: [
                              DropdownMenuItem(
                                value: 'all',
                                child: Text(l10n.tr('all_categories')),
                              ),
                              ...marketMainCategories.map(
                                (c) => DropdownMenuItem(
                                  value: c,
                                  child: Text(marketCategoryLabel(c)),
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
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                        child: _buildResponsiveDropdownRow(
                          label: l10n.tr('type_label'),
                          child: DropdownButton<String>(
                            value: _selectedIntent,
                            isExpanded: true,
                            items: [
                              DropdownMenuItem(value: 'all', child: Text(l10n.tr('all_types'))),
                              DropdownMenuItem(value: 'selling', child: Text(l10n.tr('selling'))),
                              DropdownMenuItem(value: 'buying', child: Text(l10n.tr('buying'))),
                            ],
                            onChanged: (v) {
                              if (v == null) return;
                              setState(() => _selectedIntent = v);
                              _load();
                            },
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                        child: _buildResponsiveDropdownRow(
                          label: l10n.tr('sort_label'),
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
                    : _posts.isEmpty
                        ? Center(child: Text(l10n.tr('no_marketplace_posts_found')))
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                return GridView.builder(
                                  padding: const EdgeInsets.all(12),
                                  gridDelegate:
                                      SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: _gridCount(constraints.maxWidth),
                                    childAspectRatio: _gridAspectRatio(constraints.maxWidth),
                                    crossAxisSpacing: 10,
                                    mainAxisSpacing: 10,
                                  ),
                                  itemCount: _posts.length,
                                  itemBuilder: (context, index) {
                                final p = _posts[index];
                                final myId = Supabase.instance.client.auth.currentUser?.id;
                                final canSendOffer = myId != null && p.userId != myId;
                                final title = (p.marketTitle ?? '').trim().isNotEmpty
                                    ? p.marketTitle!.trim()
                                    : _plainListingText(p.content);
                                final intent = p.marketIntent;
                                final effectivePrice =
                                    p.marketPrice ?? _priceFromContent(p.content);
                                final distanceKm = _distanceKm(p);
                                final String priceText;
                                if (effectivePrice != null) {
                                  if (p.marketPriceMax != null && p.marketPriceMax! > effectivePrice) {
                                    priceText = 'EUR ${effectivePrice.toStringAsFixed(2)} – EUR ${p.marketPriceMax!.toStringAsFixed(2)}';
                                  } else {
                                    priceText = 'EUR ${effectivePrice.toStringAsFixed(2)}';
                                  }
                                } else {
                                  priceText = intent == 'buying' ? l10n.tr('looking_to_buy') : l10n.tr('price_on_request');
                                }

                                return InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () => context.push('/marketplace/product/${p.id}'),
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
                                              child: p.imageUrl != null && p.imageUrl!.isNotEmpty
                                                  ? Image.network(
                                                      p.imageUrl!,
                                                      fit: BoxFit.contain,
                                                      alignment: Alignment.center,
                                                    )
                                                  : const Icon(
                                                      Icons.image_outlined,
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
                                                marketCategoryLabel(p.marketCategory ?? ''),
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
                                              if (intent != null && intent.isNotEmpty)
                                                Text(
                                                  _intentLabel(intent),
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
