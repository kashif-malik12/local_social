import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/post_model.dart';
import '../services/post_service.dart';
import 'network_video_player.dart';
import 'youtube_preview.dart';

class MobileVideoFeed extends StatefulWidget {
  const MobileVideoFeed({super.key});

  @override
  State<MobileVideoFeed> createState() => _MobileVideoFeedState();
}

class _MobileVideoFeedState extends State<MobileVideoFeed> {
  static const int _nearbyRadiusKm = 10;

  final _pageController = PageController();

  bool _loading = true;
  String? _error;
  String _scope = 'following';
  List<Post> _posts = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  bool _isYoutubeUrl(String? value) {
    if (value == null || value.trim().isEmpty) return false;
    final uri = Uri.tryParse(value.trim());
    if (uri == null) return false;
    final host = uri.host.toLowerCase();
    return host.contains('youtube.com') || host.contains('youtu.be');
  }

  String _serviceScope() {
    switch (_scope) {
      case 'public':
        return 'public';
      case 'nearby':
        return 'all';
      case 'following':
      default:
        return 'following';
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final rows = await PostService(Supabase.instance.client).fetchPublicFeed(
        limit: 80,
        scope: _serviceScope(),
        radiusKmOverride: _scope == 'nearby' ? _nearbyRadiusKm : null,
      );
      final hydrated = await PostService(Supabase.instance.client).attachSharedPosts(rows);
      final posts = hydrated
          .map((row) => Post.fromMap(row))
          .where((post) => (post.videoUrl ?? '').trim().isNotEmpty && (post.sharedPostId ?? '').isEmpty)
          .toList();

      if (!mounted) return;
      setState(() => _posts = posts);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _scopeChip({
    required String value,
    required String label,
  }) {
    final selected = _scope == value;
    return ChoiceChip(
      selected: selected,
      onSelected: (_) {
        if (_scope == value) return;
        setState(() => _scope = value);
        _load();
      },
      label: Text(label),
      selectedColor: const Color(0xFF0F766E),
      labelStyle: TextStyle(
        color: selected ? Colors.white : const Color(0xFF17322C),
        fontWeight: FontWeight.w700,
      ),
      side: BorderSide(
        color: selected ? const Color(0xFF0F766E) : const Color(0xFFD8C8AF),
      ),
      backgroundColor: const Color(0xFFF7F0E4),
    );
  }

  Widget _buildVideoPlayer(String videoUrl) {
    if (_isYoutubeUrl(videoUrl)) {
      return YoutubePreview(videoUrl: videoUrl);
    }
    return NetworkVideoPlayer(videoUrl: videoUrl, maxHeight: 520);
  }

  Widget _buildPostCard(Post post) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0C111D), Color(0xFF162136)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundImage: (post.authorAvatarUrl ?? '').isNotEmpty
                          ? NetworkImage(post.authorAvatarUrl!)
                          : null,
                      child: (post.authorAvatarUrl ?? '').isEmpty
                          ? const Icon(Icons.person, size: 18)
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          InkWell(
                            onTap: () => context.push('/p/${post.userId}'),
                            child: Text(
                              post.authorName ?? 'Unknown',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            post.locationName?.trim().isNotEmpty == true
                                ? post.locationName!.trim()
                                : (_scope == 'nearby'
                                    ? 'Nearby videos within $_nearbyRadiusKm km'
                                    : 'Video feed'),
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.72),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (post.distanceKm != null && _scope == 'nearby')
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '${post.distanceKm!.toStringAsFixed(1)} km',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: Container(
                      width: double.infinity,
                      color: Colors.black,
                      child: _buildVideoPlayer(post.videoUrl!.trim()),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: Colors.white.withOpacity(0.08)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (post.content.trim().isNotEmpty)
                        Text(
                          post.content.trim(),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 15),
                        ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: BorderSide(color: Colors.white.withOpacity(0.35)),
                        ),
                        onPressed: () => context.push('/post/${post.id}'),
                        icon: const Icon(Icons.open_in_new, size: 18),
                        label: const Text('Open post'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF08111C),
      child: Column(
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Video Feed',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                  ),
                  IconButton(
                    onPressed: _loading ? null : _load,
                    color: Colors.white,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _scopeChip(value: 'following', label: 'Following'),
                _scopeChip(value: 'nearby', label: 'Nearby 10 km'),
                _scopeChip(value: 'public', label: 'Public'),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            'Video feed error:\n$_error',
                            style: const TextStyle(color: Colors.white),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : _posts.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                'No videos found for this filter yet.',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.78),
                                  fontSize: 16,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          )
                        : PageView.builder(
                            controller: _pageController,
                            scrollDirection: Axis.vertical,
                            itemCount: _posts.length,
                            itemBuilder: (_, index) => _buildPostCard(_posts[index]),
                          ),
          ),
        ],
      ),
    );
  }
}
