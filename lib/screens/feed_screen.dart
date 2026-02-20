import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/post_model.dart';
import '../services/post_service.dart';

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  bool _loading = true;
  String? _error;
  List<Post> _posts = [];

  // ✅ Filters
  String _selectedScope = 'all'; // 'all' or 'following'
  String _selectedPostType = 'all';
  String _selectedAuthorType = 'all';
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final service = PostService(Supabase.instance.client);

      final raw = await service.fetchPublicFeed(
        scope: _selectedScope,
        postType: _selectedPostType,
        authorType: _selectedAuthorType,
      );

      setState(() {
        _posts = raw.map((e) => Post.fromMap(e)).toList();
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _posts = [];
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String? _getAuthorBadgeType(Post post) {
    if (post.authorType == 'business') return 'BUSINESS';
    if (post.authorType == 'org') return 'ORG';
    return null;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Widget _buildFilters() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // ✅ Scope: All vs Following
          DropdownButton<String>(
            value: _selectedScope,
            items: const [
              DropdownMenuItem(value: 'all', child: Text('Public (All)')),
              DropdownMenuItem(value: 'following', child: Text('Following')),
            ],
            onChanged: (v) {
              if (v == null) return;
              setState(() => _selectedScope = v);
              _load();
            },
          ),

          // Post Type
          DropdownButton<String>(
            value: _selectedPostType,
            items: const [
              DropdownMenuItem(value: 'all', child: Text('All posts')),
              DropdownMenuItem(value: 'post', child: Text('General')),
              DropdownMenuItem(value: 'market', child: Text('Market')),
              DropdownMenuItem(value: 'service_offer', child: Text('Service offer')),
              DropdownMenuItem(value: 'service_request', child: Text('Service request')),
              DropdownMenuItem(value: 'lost_found', child: Text('Lost & found')),
            ],
            onChanged: (v) {
              if (v == null) return;
              setState(() => _selectedPostType = v);
              _load();
            },
          ),

          // Author Type
          DropdownButton<String>(
            value: _selectedAuthorType,
            items: const [
              DropdownMenuItem(value: 'all', child: Text('All authors')),
              DropdownMenuItem(value: 'person', child: Text('People')),
              DropdownMenuItem(value: 'business', child: Text('Businesses')),
              DropdownMenuItem(value: 'org', child: Text('Organizations')),
            ],
            onChanged: (v) {
              if (v == null) return;
              setState(() => _selectedAuthorType = v);
              _load();
            },
          ),

          // Reset
          TextButton.icon(
            onPressed: () {
              setState(() {
                _selectedScope = 'all';
                _selectedPostType = 'all';
                _selectedAuthorType = 'all';
              });
              _load();
            },
            icon: const Icon(Icons.refresh),
            label: const Text('Reset'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Local Feed ✅'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person),
            onPressed: () => context.go('/profile'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('Feed error:\n$_error'),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    itemCount: _posts.length + 1,
                    itemBuilder: (_, i) {
                      if (i == 0) return _buildFilters();

                      final p = _posts[i - 1];
                      final badgeText = _getAuthorBadgeType(p);

                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // ✅ Click author row → open profile
                              InkWell(
                                onTap: () => context.push('/p/${p.userId}'),
                                borderRadius: BorderRadius.circular(8),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          p.authorName ?? 'Unknown',
                                          style: const TextStyle(fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      if (badgeText != null)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(20),
                                            border: Border.all(),
                                          ),
                                          child: Text(badgeText, style: const TextStyle(fontSize: 12)),
                                        ),
                                    ],
                                  ),
                                ),
                              ),

                              const SizedBox(height: 6),
                              Text(p.content),
                              if (p.imageUrl != null) ...[
                                const SizedBox(height: 10),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.network(p.imageUrl!, fit: BoxFit.cover),
                                ),
                              ],
                              const SizedBox(height: 8),
                              if (p.locationName != null)
                                Text('📍 ${p.locationName}', style: const TextStyle(fontSize: 12)),
                              Text(p.createdAt.toLocal().toString(), style: const TextStyle(fontSize: 12)),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final res = await context.push('/create-post');
          if (res == true) _load();
        },
        icon: const Icon(Icons.add),
        label: const Text('Post'),
      ),
    );
  }
}
