import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:math' as math;

import '../core/market_categories.dart';
import '../models/post_model.dart';
import '../widgets/global_app_bar.dart';

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
  String _search = '';
  final TextEditingController _searchCtrl = TextEditingController();
  List<Post> _posts = [];
  double? _meLat;
  double? _meLng;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

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
          .select('*, profiles(full_name, avatar_url, city, zipcode)')
          .eq('post_type', 'market')
          .order('created_at', ascending: false)
          .limit(120);

      final rows = (data as List).cast<Map<String, dynamic>>();

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

      if (!mounted) return;
      setState(() {
        _posts = items;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GlobalAppBar(
        title: 'Marketplace',
        showBackIfPossible: true,
        homeRoute: '/feed',
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/create-post'),
        icon: const Icon(Icons.add),
        label: const Text('Sell / Buy'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: TextField(
              controller: _searchCtrl,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search products, category, seller...',
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
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(
              children: [
                const Text('Category:'),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButton<String>(
                    value: _selectedCategory,
                    isExpanded: true,
                    items: [
                      const DropdownMenuItem(
                        value: 'all',
                        child: Text('All categories'),
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
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(
              children: [
                const Text('Type:'),
                const SizedBox(width: 40),
                Expanded(
                  child: DropdownButton<String>(
                    value: _selectedIntent,
                    isExpanded: true,
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('All types')),
                      DropdownMenuItem(value: 'selling', child: Text('Selling')),
                      DropdownMenuItem(value: 'buying', child: Text('Buying')),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _selectedIntent = v);
                      _load();
                    },
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text('Error: $_error'))
                    : _posts.isEmpty
                        ? const Center(child: Text('No marketplace posts found'))
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: GridView.builder(
                              padding: const EdgeInsets.all(12),
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                childAspectRatio: 0.72,
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
                                    : p.content.trim();
                                final intent = p.marketIntent;
                                final effectivePrice =
                                    p.marketPrice ?? _priceFromContent(p.content);
                                final distanceKm = _distanceKm(p);
                                final priceText = effectivePrice != null
                                    ? 'EUR ${effectivePrice.toStringAsFixed(2)}'
                                    : (intent == 'buying'
                                        ? 'Looking to buy'
                                        : 'Price on request');

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
                                        Expanded(
                                          child: ClipRRect(
                                            borderRadius: const BorderRadius.vertical(
                                              top: Radius.circular(12),
                                            ),
                                            child: Container(
                                              width: double.infinity,
                                              color: Colors.grey.shade200,
                                              child: p.imageUrl != null && p.imageUrl!.isNotEmpty
                                                  ? Image.network(
                                                      p.imageUrl!,
                                                      fit: BoxFit.cover,
                                                    )
                                                  : const Icon(
                                                      Icons.image_outlined,
                                                      size: 46,
                                                      color: Colors.black45,
                                                    ),
                                            ),
                                          ),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.all(10),
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
                                                  onPressed: canSendOffer
                                                      ? () => context.push(
                                                            '/offer-chat/post/${p.id}/user/${p.userId}',
                                                          )
                                                      : null,
                                                  icon: const Icon(
                                                    Icons.local_offer_outlined,
                                                    size: 16,
                                                  ),
                                                  label: const Text('Send offer'),
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
        ],
      ),
    );
  }
}
