import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/business_categories.dart';
import '../models/post_model.dart';
import '../services/post_service.dart';
import 'report_post_sheet.dart';

class PostCard extends StatelessWidget {
  final Post post;
  final VoidCallback? onTap;
  final ValueChanged<String>? onDeleted;

  const PostCard({
    super.key,
    required this.post,
    this.onTap,
    this.onDeleted,
  });

  Future<void> _deletePost(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete post?'),
        content: const Text('This will remove the post from your profile and feed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await PostService(Supabase.instance.client).deleteOwnPost(post.id);
      onDeleted?.call(post.id);

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Post deleted.')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    final bool isMe = uid != null && post.userId == uid;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _HeaderRow(
                post: post,
                isMe: isMe,
                onDelete: isMe ? _deletePost : null,
              ),
              if (post.locationName != null &&
                  post.locationName!.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.place, size: 14, color: Colors.grey.shade600),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        post.locationName!,
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              if (post.postType == 'market')
                _MarketListingBody(post: post)
              else
                _RegularPostBody(post: post),
            ],
          ),
        ),
      ),
    );
  }
}

class _RegularPostBody extends StatelessWidget {
  final Post post;

  const _RegularPostBody({required this.post});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (post.content.trim().isNotEmpty)
          Text(
            post.content.trim(),
            style: const TextStyle(fontSize: 14),
          ),
        if (post.imageUrl != null && post.imageUrl!.isNotEmpty) ...[
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              post.imageUrl!,
              fit: BoxFit.cover,
            ),
          ),
        ],
      ],
    );
  }
}

class _MarketListingBody extends StatelessWidget {
  final Post post;

  const _MarketListingBody({required this.post});

  String _priceText() {
    final min = post.marketPrice;
    final max = post.marketPriceMax;
    if (min == null) return 'Price on request';
    if (max != null && max > min) {
      return 'EUR ${min.toStringAsFixed(2)} – EUR ${max.toStringAsFixed(2)}';
    }
    return 'EUR ${min.toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    final intent = post.marketIntent ?? _MarketPostData.parseIntent(post.content);
    final title = (post.marketTitle ?? '').trim().isNotEmpty
        ? post.marketTitle!.trim()
        : _MarketPostData.parseTitle(post.content);
    final details = _MarketPostData.parseDetails(post.content);
    final badgeColor = intent == 'buying' ? Colors.teal : Colors.orange;
    final intentLabel = intent == 'buying' ? 'BUY' : 'SELL';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (post.imageUrl != null && post.imageUrl!.isNotEmpty)
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AspectRatio(
              aspectRatio: 4 / 3,
              child: Image.network(
                post.imageUrl!,
                fit: BoxFit.cover,
              ),
            ),
          ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: badgeColor.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                intentLabel,
                style: TextStyle(
                  color: badgeColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
            Text(
              _priceText(),
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
        if (details != null && details.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            details,
            style: const TextStyle(fontSize: 14),
          ),
        ],
      ],
    );
  }
}

class _MarketPostData {
  static String parseIntent(String rawContent) {
    final first = rawContent.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).firstOrNull ?? '';
    if (first.startsWith('[BUYING] ')) return 'buying';
    return 'selling';
  }

  static String parseTitle(String rawContent) {
    final lines = rawContent.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (lines.isEmpty) return 'Market listing';
    final first = lines.first;
    if (first.startsWith('[BUYING] ')) return first.replaceFirst('[BUYING] ', '').trim();
    if (first.startsWith('[SELLING] ')) return first.replaceFirst('[SELLING] ', '').trim();
    return first.isNotEmpty ? first : 'Market listing';
  }

  static String? parseDetails(String rawContent) {
    for (final line in rawContent.split('\n').map((e) => e.trim())) {
      if (line.startsWith('Details:')) {
        final d = line.replaceFirst('Details:', '').trim();
        if (d.isNotEmpty) return d;
      }
    }
    return null;
  }
}

class _HeaderRow extends StatelessWidget {
  final Post post;
  final bool isMe;
  final Future<void> Function(BuildContext context)? onDelete;

  const _HeaderRow({
    required this.post,
    required this.isMe,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isAnonymous = post.postType == 'market' ||
        post.postType == 'service_offer' ||
        post.postType == 'service_request';

    String headerName = (post.authorBusinessName != null && post.authorBusinessName!.isNotEmpty)
        ? post.authorBusinessName!
        : (post.authorName ?? 'Unknown');

    if (post.postType == 'market') {
      headerName = 'Marketplace listing';
    } else if (post.postType == 'service_offer' || post.postType == 'service_request') {
      headerName = 'Gigs post';
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!isAnonymous) ...[
          CircleAvatar(
            radius: 18,
            backgroundImage: (post.authorAvatarUrl != null &&
                    post.authorAvatarUrl!.isNotEmpty)
                ? NetworkImage(post.authorAvatarUrl!)
                : null,
            child: (post.authorAvatarUrl == null ||
                    post.authorAvatarUrl!.isEmpty)
                ? const Icon(Icons.person, size: 18)
                : null,
          ),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    headerName,
                    style:
                        const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                  if (!isAnonymous &&
                      post.authorBusinessType != null &&
                      (post.authorBusinessType == 'trader' ||
                          post.authorBusinessType == 'manufacturer')) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Text(
                        businessCategoryLabel(post.authorBusinessType!),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Colors.blue.shade800,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              if (!isAnonymous &&
                  post.authorJobTitle != null &&
                  post.authorJobTitle!.isNotEmpty)
                Text(
                  post.authorJobTitle!,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700,
                  ),
                ),
              const SizedBox(height: 2),
              Row(
                children: [
                  if (post.distanceKm != null)
                    Text(
                      '${post.distanceKm!.toStringAsFixed(1)} km',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                      ),
                    ),
                  if (post.distanceKm != null) const SizedBox(width: 8),
                  Text(
                    _formatTime(post.createdAt),
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 12,
                    ),
                  ),
                  if (post.visibility.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text(
                      post.visibility,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        PopupMenuButton<String>(
          onSelected: (value) async {
            final messenger = ScaffoldMessenger.of(context);
            if (value == 'report') {
              final reported = await showModalBottomSheet<bool>(
                context: context,
                isScrollControlled: true,
                builder: (_) => ReportPostSheet(postId: post.id),
              );

              if (reported == true) {
                messenger.showSnackBar(
                  const SnackBar(content: Text("Thanks - we'll review it.")),
                );
              }
            }

            if (value == 'delete') {
              if (!context.mounted) return;
              await onDelete?.call(context);
            }
          },
          itemBuilder: (context) => [
            if (!isMe)
              const PopupMenuItem(
                value: 'report',
                child: Text('Report'),
              ),
            if (isMe)
              const PopupMenuItem(
                value: 'delete',
                child: Text('Delete'),
              ),
          ],
        ),
      ],
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    return '${diff.inDays}d';
  }
}
