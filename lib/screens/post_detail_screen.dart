import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/post_model.dart';
import '../services/reaction_service.dart';
import '../widgets/youtube_preview.dart';
import '../widgets/report_post_sheet.dart'; // ✅ NEW

class PostDetailScreen extends StatefulWidget {
  final String postId;
  const PostDetailScreen({super.key, required this.postId});

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  bool _loading = true;
  String? _error;
  Post? _post;

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
      final row = await Supabase.instance.client
          .from('posts')
          .select('*, profiles(full_name, avatar_url)')
          .eq('id', widget.postId)
          .maybeSingle();

      if (row == null) {
        throw Exception('Post not found');
      }

      _post = Post.fromMap(row);
    } catch (e) {
      _error = e.toString();
      _post = null;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reportPost(Post post) async {
    final reported = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ReportPostSheet(postId: post.id),
    );

    if (reported == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Thanks — we’ll review it.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final react = ReactionService(Supabase.instance.client);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Post'),
        actions: [
          IconButton(
            icon: const Icon(Icons.comment_outlined),
            onPressed: () {
              if (_post == null) return;
              context.push('/post/${_post!.id}/comments');
            },
          ),

          // ✅ NEW: 3-dot menu in AppBar
          if (_post != null)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (value) async {
                final p = _post;
                if (p == null) return;

                if (value == 'report') {
                  await _reportPost(p);
                }
              },
              itemBuilder: (context) {
                final uid = Supabase.instance.client.auth.currentUser?.id;
                final isMe = uid != null && _post!.userId == uid;

                return [
                  if (!isMe)
                    const PopupMenuItem(
                      value: 'report',
                      child: Text('Report'),
                    ),
                ];
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
                    child: Text('Error:\n$_error'),
                  ),
                )
              : _post == null
                  ? const Center(child: Text('Post not found'))
                  : SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Header row (tap author -> profile)
                            InkWell(
                              onTap: () => context.push('/p/${_post!.userId}'),
                              borderRadius: BorderRadius.circular(8),
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 4),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 18,
                                      backgroundImage: (_post!.authorAvatarUrl !=
                                                  null &&
                                              _post!.authorAvatarUrl!.isNotEmpty)
                                          ? NetworkImage(_post!.authorAvatarUrl!)
                                          : null,
                                      child: (_post!.authorAvatarUrl == null ||
                                              _post!.authorAvatarUrl!.isEmpty)
                                          ? const Icon(Icons.person, size: 18)
                                          : null,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        _post!.authorName ?? 'Unknown',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            const SizedBox(height: 12),
                            Text(_post!.content),

                            // ✅ YouTube preview
                            if (_post!.videoUrl != null &&
                                _post!.videoUrl!.isNotEmpty) ...[
                              YoutubePreview(videoUrl: _post!.videoUrl!),
                            ],

                            // ✅ Image
                            if (_post!.imageUrl != null &&
                                _post!.imageUrl!.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.network(
                                  _post!.imageUrl!,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ],

                            const SizedBox(height: 12),

                            // Likes + Comments counts
                            FutureBuilder<List<dynamic>>(
                              future: Future.wait([
                                react.likesCount(_post!.id),
                                react.commentsCount(_post!.id),
                              ]),
                              builder: (_, snap) {
                                final likes =
                                    snap.hasData ? snap.data![0] as int : 0;
                                final comments =
                                    snap.hasData ? snap.data![1] as int : 0;

                                return Row(
                                  children: [
                                    Text('❤️ $likes'),
                                    const SizedBox(width: 16),
                                    TextButton.icon(
                                      onPressed: () => context.push(
                                          '/post/${_post!.id}/comments'),
                                      icon: const Icon(Icons.comment_outlined),
                                      label: Text('$comments'),
                                    ),
                                  ],
                                );
                              },
                            ),

                            const SizedBox(height: 8),

                            if (_post!.locationName != null &&
                                _post!.locationName!.trim().isNotEmpty)
                              Text(
                                '📍 ${_post!.locationName}',
                                style: const TextStyle(fontSize: 12),
                              ),

                            Text(
                              _post!.createdAt.toLocal().toString(),
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ),
    );
  }
}