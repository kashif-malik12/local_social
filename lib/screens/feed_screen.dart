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

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final service = PostService(Supabase.instance.client);
      final raw = await service.fetchPublicFeed();

      setState(() {
        _posts = raw.map((e) => Post.fromMap(e)).toList();
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _posts = [];
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
     appBar: AppBar(
  title: const Text('Local Feed ✅'),
  actions: [
    IconButton(
      icon: const Icon(Icons.person),
      onPressed: () {
        context.go('/profile');
      },
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
                    itemCount: _posts.length,
                    itemBuilder: (_, i) {
                      final p = _posts[i];
                      final isBiz = p.authorType == 'business';

                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      p.authorName ?? 'Unknown',
                                      style: const TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  if (isBiz)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(),
                                      ),
                                      child: const Text('BUSINESS', style: TextStyle(fontSize: 12)),
                                    ),
                                ],
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
                                Text(
                                  '📍 ${p.locationName}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              Text(
                                p.createdAt.toLocal().toString(),
                                style: const TextStyle(fontSize: 12),
                              ),
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
