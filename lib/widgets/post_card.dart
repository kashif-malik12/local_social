import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/post_model.dart';
import 'report_post_sheet.dart';

class PostCard extends StatelessWidget {
  final Post post;
  final VoidCallback? onTap;

  const PostCard({
    super.key,
    required this.post,
    this.onTap,
  });

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
              _HeaderRow(post: post, isMe: isMe),

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

              // If you already have a YouTube preview widget, insert it here.
              // Example:
              // if (post.videoUrl != null && post.videoUrl!.isNotEmpty) ...[
              //   const SizedBox(height: 10),
              //   YoutubePreview(videoUrl: post.videoUrl!),
              // ],
            ],
          ),
        ),
      ),
    );
  }
}

class _HeaderRow extends StatelessWidget {
  final Post post;
  final bool isMe;

  const _HeaderRow({required this.post, required this.isMe});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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

        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                post.authorName ?? 'Unknown',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
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
            if (value == 'report') {
              final reported = await showModalBottomSheet<bool>(
                context: context,
                isScrollControlled: true,
                builder: (_) => ReportPostSheet(postId: post.id),
              );

              if (reported == true && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Thanks — we’ll review it.')),
                );
              }
            }

            if (value == 'delete') {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Delete not wired yet.')),
              );
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