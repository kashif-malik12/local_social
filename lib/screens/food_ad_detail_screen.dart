import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/food_categories.dart';
import '../models/post_model.dart';
import '../services/reaction_service.dart';
import '../widgets/global_app_bar.dart';
import '../widgets/global_bottom_nav.dart';
import '../widgets/post_media_view.dart';
import '../widgets/tagged_content.dart';

class FoodAdDetailScreen extends StatefulWidget {
  final String postId;

  const FoodAdDetailScreen({super.key, required this.postId});

  @override
  State<FoodAdDetailScreen> createState() => _FoodAdDetailScreenState();
}

class _FoodAdDetailScreenState extends State<FoodAdDetailScreen> {
  final _svc = ReactionService(Supabase.instance.client);
  final _commentCtrl = TextEditingController();
  final _commentFocus = FocusNode();

  bool _loading = true;
  String? _error;
  Post? _post;

  int _selectedTab = 0;
  bool _commentsLoading = true;
  String? _commentsError;
  List<Map<String, dynamic>> _comments = [];
  String? _replyToCommentId;
  String? _replyToUserId;
  String? _replyToName;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    _commentFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final row = await Supabase.instance.client
          .from('posts')
          .select('*, profiles(full_name, avatar_url, city, zipcode)')
          .eq('id', widget.postId)
          .inFilter('post_type', ['food_ad', 'food'])
          .maybeSingle();

      if (row == null) throw Exception('Food ad not found');
      if (!mounted) return;
      setState(() => _post = Post.fromMap(row));
      await _loadComments();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _loadComments() async {
    setState(() {
      _commentsLoading = true;
      _commentsError = null;
    });

    try {
      final rows = await _svc.fetchComments(widget.postId);
      if (!mounted) return;
      setState(() => _comments = rows);
    } catch (e) {
      if (!mounted) return;
      setState(() => _commentsError = e.toString());
    } finally {
      if (!mounted) return;
      setState(() => _commentsLoading = false);
    }
  }

  List<_CommentView> _visibleComments() {
    final byParent = <String?, List<Map<String, dynamic>>>{};
    for (final comment in _comments) {
      final parentId = comment['parent_comment_id']?.toString();
      byParent.putIfAbsent(parentId, () => []).add(comment);
    }

    final output = <_CommentView>[];

    void visit(String? parentId, int depth) {
      final children = byParent[parentId] ?? const [];
      for (final comment in children) {
        output.add(_CommentView(comment: comment, depth: depth));
        visit(comment['id']?.toString(), depth + 1);
      }
    }

    visit(null, 0);
    return output;
  }

  Future<void> _sendComment() async {
    final post = _post;
    final raw = _commentCtrl.text.trim();
    if (post == null || raw.isEmpty) return;

    try {
      await _svc.addComment(
        widget.postId,
        raw,
        parentCommentId: _replyToCommentId,
        postOwnerId: post.userId,
        parentCommentUserId: _replyToUserId,
      );
      _commentCtrl.clear();
      if (!mounted) return;
      setState(() {
        _replyToCommentId = null;
        _replyToUserId = null;
        _replyToName = null;
      });
      await _loadComments();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Comment error: $e')),
      );
    }
  }

  Widget _buildTabButton({
    required String label,
    required int index,
    required ThemeData theme,
  }) {
    final selected = _selectedTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedTab = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF0F766E) : const Color(0xFFF7F0E4),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? const Color(0xFF0F766E) : const Color(0xFFE1D5C0),
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: selected ? Colors.white : const Color(0xFF17322C),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCommentItem(Map<String, dynamic> comment, String? me, int depth) {
    final profile = comment['profiles'];
    final name = (profile is Map ? profile['full_name'] : null)?.toString().trim();
    final displayName = (name == null || name.isEmpty) ? 'Unknown' : name;
    final avatarUrl = profile is Map ? profile['avatar_url']?.toString() : null;
    final userId = comment['user_id']?.toString();
    final mine = me != null && userId == me;
    final likeCount = (comment['like_count'] as num?)?.toInt() ?? 0;
    final likedByMe = comment['liked_by_me'] == true;
    final commentId = (comment['id'] ?? '').toString();

    return Padding(
      padding: EdgeInsets.only(left: depth * 18.0),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: mine ? const Color(0xFFF4EBDD) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE6DDCE)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: userId == null || userId.isEmpty ? null : () => context.push('/p/$userId'),
              borderRadius: BorderRadius.circular(999),
              child: CircleAvatar(
                radius: 18,
                backgroundImage:
                    avatarUrl != null && avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
                child: avatarUrl == null || avatarUrl.isEmpty
                    ? Text(displayName[0].toUpperCase())
                    : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: userId == null || userId.isEmpty ? null : () => context.push('/p/$userId'),
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Text(
                              displayName,
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                        ),
                      ),
                      if (mine)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F766E).withOpacity(0.08),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text(
                            'You',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF0F766E),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  TaggedContent(content: comment['content']?.toString() ?? ''),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    children: [
                      TextButton.icon(
                        onPressed: commentId.isEmpty || userId == null || userId.isEmpty
                            ? null
                            : () async {
                                try {
                                  if (likedByMe) {
                                    await _svc.unlikeComment(commentId);
                                  } else {
                                    await _svc.likeComment(
                                      commentId: commentId,
                                      postId: widget.postId,
                                      commentOwnerId: userId,
                                    );
                                  }
                                  await _loadComments();
                                } catch (e) {
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Comment like error: $e')),
                                  );
                                }
                              },
                        icon: Icon(
                          likedByMe ? Icons.favorite : Icons.favorite_border,
                          size: 18,
                        ),
                        label: Text('$likeCount'),
                      ),
                      TextButton.icon(
                        onPressed: commentId.isEmpty || userId == null || userId.isEmpty
                            ? null
                            : () {
                                setState(() {
                                  _replyToCommentId = commentId;
                                  _replyToUserId = userId;
                                  _replyToName = displayName;
                                  _selectedTab = 1;
                                });
                                _commentFocus.requestFocus();
                              },
                        icon: const Icon(Icons.reply_outlined, size: 18),
                        label: const Text('Reply'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (mine)
              IconButton(
                tooltip: 'Delete comment',
                icon: const Icon(Icons.delete_outline, size: 20),
                onPressed: () async {
                  await _svc.deleteComment(commentId);
                  await _loadComments();
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDescriptionTab(Post p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Description',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
        const SizedBox(height: 8),
        TaggedContent(content: p.content),
      ],
    );
  }

  Widget _buildCommentsTab(ThemeData theme) {
    final me = Supabase.instance.client.auth.currentUser?.id;
    final visibleComments = _visibleComments();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE6DDCE)),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFF0F766E).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.forum_outlined, color: Color(0xFF0F766E)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Food comments',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_comments.length} ${_comments.length == 1 ? 'comment' : 'comments'}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (_commentsLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_commentsError != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text('Comments error:\n$_commentsError'),
          )
        else if (visibleComments.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE6DDCE)),
            ),
            child: const Text('No comments yet. Start the conversation.'),
          )
        else
          ...visibleComments.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _buildCommentItem(item.comment, me, item.depth),
            ),
          ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFE6DDCE)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x10000000),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_replyToCommentId != null)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4EBDD),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Replying to ${_replyToName ?? 'comment'}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          setState(() {
                            _replyToCommentId = null;
                            _replyToUserId = null;
                            _replyToName = null;
                          });
                        },
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _commentCtrl,
                      focusNode: _commentFocus,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendComment(),
                      decoration: InputDecoration(
                        hintText: _replyToCommentId == null
                            ? 'Write a comment...'
                            : 'Write a reply...',
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _sendComment,
                    icon: const Icon(Icons.send_rounded, size: 18),
                    label: Text(_replyToCommentId == null ? 'Send' : 'Reply'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = _post;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: const GlobalAppBar(
        title: 'Food details',
        showBackIfPossible: true,
        homeRoute: '/feed',
      ),
      bottomNavigationBar: const GlobalBottomNav(),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Error: $_error'))
              : p == null
                  ? const Center(child: Text('Food ad not found'))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          if ((p.imageUrl ?? '').isNotEmpty ||
                              (p.secondImageUrl ?? '').isNotEmpty ||
                              (p.videoUrl ?? '').isNotEmpty)
                            PostMediaView(
                              imageUrl: p.imageUrl,
                              secondImageUrl: p.secondImageUrl,
                              videoUrl: p.videoUrl,
                            )
                          else
                            SizedBox(
                              height: 280,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  color: Colors.grey.shade200,
                                  padding: const EdgeInsets.all(8),
                                  child: const Icon(Icons.fastfood, size: 64),
                                ),
                              ),
                            ),
                          const SizedBox(height: 16),
                          Text(
                            (p.marketTitle ?? '').trim().isNotEmpty ? p.marketTitle!.trim() : p.content,
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            p.marketPrice != null
                                ? 'EUR ${p.marketPrice!.toStringAsFixed(2)}'
                                : 'Price on request',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          InkWell(
                            onTap: p.userId.isEmpty ? null : () => context.push('/p/${p.userId}'),
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Text(
                                'Restaurant: ${p.authorName ?? 'Unknown'}',
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                          if (((p.authorCity ?? '').trim().isNotEmpty) ||
                              ((p.authorZipcode ?? '').trim().isNotEmpty))
                            Text(
                              'Location: ${((p.authorCity ?? '').trim().isNotEmpty ? p.authorCity!.trim() : p.authorZipcode!.trim())}',
                            ),
                          if ((p.marketCategory ?? '').isNotEmpty)
                            Text('Category: ${foodCategoryLabel(p.marketCategory!)}'),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              _buildTabButton(
                                label: 'Description',
                                index: 0,
                                theme: theme,
                              ),
                              const SizedBox(width: 10),
                              _buildTabButton(
                                label: 'Comments ${_comments.isEmpty ? '' : _comments.length}'.trim(),
                                index: 1,
                                theme: theme,
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 180),
                            child: _selectedTab == 0
                                ? _buildDescriptionTab(p)
                                : _buildCommentsTab(theme),
                          ),
                        ],
                      ),
                    ),
    );
  }
}

class _CommentView {
  final Map<String, dynamic> comment;
  final int depth;

  const _CommentView({
    required this.comment,
    required this.depth,
  });
}
