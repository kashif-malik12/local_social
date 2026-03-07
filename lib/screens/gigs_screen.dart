import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/service_categories.dart';
import '../models/post_model.dart';
import '../widgets/global_app_bar.dart';

class GigsScreen extends StatefulWidget {
  const GigsScreen({super.key});

  @override
  State<GigsScreen> createState() => _GigsScreenState();
}

class _GigsScreenState extends State<GigsScreen> {
  bool _loading = true;
  String? _error;
  String _selectedCategory = 'all';
  String _selectedType = 'all';
  String _search = '';
  final TextEditingController _searchCtrl = TextEditingController();
  List<Post> _posts = [];

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  bool _isServicePost(Post p) =>
      p.postType == 'service_offer' || p.postType == 'service_request';

  String _typeLabel(String? postType) {
    if (postType == 'service_offer') return 'Offering';
    if (postType == 'service_request') return 'Requesting';
    return '';
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
      final data = await Supabase.instance.client
          .from('posts')
          .select('*, profiles(full_name, avatar_url)')
          .inFilter('post_type', ['service_offer', 'service_request'])
          .order('created_at', ascending: false)
          .limit(120);

      final rows = (data as List).cast<Map<String, dynamic>>();
      var items = rows.map((e) => Post.fromMap(e)).where(_isServicePost).toList();

      if (_selectedCategory != 'all') {
        items = items
            .where((p) => (p.marketCategory ?? '').trim() == _selectedCategory)
            .toList();
      }

      if (_selectedType != 'all') {
        items = items.where((p) => p.postType == _selectedType).toList();
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
      appBar: GlobalAppBar(
        title: 'Gigs',
        showBackIfPossible: true,
        homeRoute: '/feed',
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/create-post'),
        icon: const Icon(Icons.add),
        label: const Text('Post a Service'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: TextField(
              controller: _searchCtrl,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search services, category, provider...',
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
                const Text('Type:'),
                const SizedBox(width: 42),
                Expanded(
                  child: DropdownButton<String>(
                    value: _selectedType,
                    isExpanded: true,
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('All types')),
                      DropdownMenuItem(
                        value: 'service_offer',
                        child: Text('Offering'),
                      ),
                      DropdownMenuItem(
                        value: 'service_request',
                        child: Text('Requesting'),
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
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text('Error: $_error'))
                    : _posts.isEmpty
                        ? const Center(child: Text('No service posts found'))
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
                                final provider = (p.authorName ?? 'Unknown').trim();
                                final title = (p.marketTitle ?? '').trim().isNotEmpty
                                    ? p.marketTitle!.trim()
                                    : p.content.trim();
                                final priceText = p.marketPrice != null
                                    ? '€${p.marketPrice!.toStringAsFixed(2)}'
                                    : (p.postType == 'service_request'
                                        ? 'Budget open'
                                        : 'Rate on request');

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
                                        Expanded(
                                          child: ClipRRect(
                                            borderRadius: const BorderRadius.vertical(
                                              top: Radius.circular(12),
                                            ),
                                            child: Container(
                                              width: double.infinity,
                                              color: Colors.grey.shade200,
                                              child: p.imageUrl != null &&
                                                      p.imageUrl!.isNotEmpty
                                                  ? Image.network(
                                                      p.imageUrl!,
                                                      fit: BoxFit.cover,
                                                    )
                                                  : const Icon(
                                                      Icons.miscellaneous_services_outlined,
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
                                              Text(
                                                'By: $provider',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey.shade700,
                                                ),
                                              ),
                                              Text(
                                                _typeLabel(p.postType),
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.grey.shade600,
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