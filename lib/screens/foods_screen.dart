import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:math' as math;

import '../core/food_categories.dart';
import '../models/post_model.dart';
import '../widgets/global_app_bar.dart';
import '../widgets/global_bottom_nav.dart';

class FoodsScreen extends StatefulWidget {
  const FoodsScreen({super.key});

  @override
  State<FoodsScreen> createState() => _FoodsScreenState();
}

class _FoodsScreenState extends State<FoodsScreen> {
  bool _loading = true;
  String? _error;
  String _selectedCategory = 'all';
  String _search = '';
  final _searchCtrl = TextEditingController();
  List<Post> _posts = [];
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
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
          .inFilter('post_type', ['food_ad', 'food'])
          .order('created_at', ascending: false)
          .limit(150);

      final rows = (data as List).cast<Map<String, dynamic>>();
      var items = rows.map((e) => Post.fromMap(e)).toList();

      if (_selectedCategory != 'all') {
        items = items.where((p) => (p.marketCategory ?? '') == _selectedCategory).toList();
      }

      if (_search.trim().isNotEmpty) {
        final q = _search.trim().toLowerCase();
        items = items.where((p) {
          return (p.marketTitle ?? '').toLowerCase().contains(q) ||
              p.content.toLowerCase().contains(q) ||
              (p.authorName ?? '').toLowerCase().contains(q) ||
              foodCategoryLabel(p.marketCategory ?? '').toLowerCase().contains(q);
        }).toList();
      }

      if (!mounted) return;
      setState(() => _posts = items);
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
      appBar: const GlobalAppBar(
        title: 'Food Ads',
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
                hintText: 'Search foods, category, restaurant...',
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
                const DropdownMenuItem(value: 'all', child: Text('All food categories')),
                ...foodMainCategories.map(
                  (c) => DropdownMenuItem(value: c, child: Text(foodCategoryLabel(c))),
                ),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() => _selectedCategory = v);
                _load();
              },
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Food category',
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text('Error: $_error'))
                    : _posts.isEmpty
                        ? const Center(child: Text('No food ads found'))
                        : LayoutBuilder(
                            builder: (context, constraints) {
                              return GridView.builder(
                                padding: const EdgeInsets.all(12),
                                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: _gridCount(constraints.maxWidth),
                                  childAspectRatio: _gridAspectRatio(
                                    constraints.maxWidth,
                                  ),
                                  crossAxisSpacing: 10,
                                  mainAxisSpacing: 10,
                                ),
                                itemCount: _posts.length,
                                itemBuilder: (context, index) {
                              final p = _posts[index];
                              final distanceKm = _distanceKm(p);
                              final title = (p.marketTitle ?? '').trim().isNotEmpty
                                  ? p.marketTitle!.trim()
                                  : p.content.trim();
                              final price = p.marketPrice != null
                                  ? '€${p.marketPrice!.toStringAsFixed(2)}'
                                  : 'Price on request';

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
                                            if ((p.authorName ?? '').trim().isNotEmpty) ...[
                                              const SizedBox(height: 4),
                                              Text(
                                                p.authorName!.trim(),
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
        ],
      ),
    );
  }
}
