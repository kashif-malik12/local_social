import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../models/post_model.dart';
import 'package:go_router/go_router.dart';


class ProfileDetailScreen extends StatefulWidget {
  final String profileId; // ✅ in your app this equals auth uid
  const ProfileDetailScreen({super.key, required this.profileId});

  @override
  State<ProfileDetailScreen> createState() => _ProfileDetailScreenState();
}

class _ProfileDetailScreenState extends State<ProfileDetailScreen> {
  final _db = Supabase.instance.client;

  bool _loading = true;
  String? _error;

  Map<String, dynamic>? _profile;
  bool _isMe = false;
  bool _isFollowing = false;

  int _followersCount = 0;
  int _followingCount = 0;

  // ✅ Posts on profile
  bool _postsLoading = true;
  String? _postsError;
  List<Post> _posts = [];

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    await Future.wait([
      _loadProfileAndFollow(),
      _loadPosts(),
    ]);
  }

  Future<void> _loadProfileAndFollow() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final myUserId = _db.auth.currentUser!.id;

      // ✅ Your schema: profiles.id == auth uid
      final p = await _db.from('profiles').select('*').eq('id', widget.profileId).single();

      _profile = p;
      _isMe = (widget.profileId == myUserId);

      // ✅ Follow state
      if (!_isMe) {
        final f = await _db
            .from('follows')
            .select('id')
            .eq('follower_id', myUserId)
            .eq('followed_profile_id', widget.profileId)
            .maybeSingle();

        _isFollowing = f != null;
      } else {
        _isFollowing = false;
      }

      // ✅ Followers count
      final followersRows = await _db
          .from('follows')
          .select('id')
          .eq('followed_profile_id', widget.profileId);
      _followersCount = (followersRows as List).length;

      // ✅ Following count
      final followingRows = await _db
          .from('follows')
          .select('id')
          .eq('follower_id', widget.profileId);
      _followingCount = (followingRows as List).length;
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadPosts() async {
    setState(() {
      _postsLoading = true;
      _postsError = null;
    });

    try {
      // ✅ Select posts for this profile/user
      // We include profiles(full_name) so Post.fromMap keeps working (it expects map['profiles']).
      final rows = await _db
          .from('posts')
          .select('*, profiles(full_name)')
          .eq('user_id', widget.profileId)
          .order('created_at', ascending: false);

      final list = (rows as List).map((e) => Post.fromMap(e as Map<String, dynamic>)).toList();

      if (mounted) {
        setState(() => _posts = list);
      }
    } catch (e) {
      if (mounted) setState(() => _postsError = e.toString());
    } finally {
      if (mounted) setState(() => _postsLoading = false);
    }
  }

  Future<void> _toggleFollow() async {
    if (_isMe) return;

    final myUserId = _db.auth.currentUser!.id;

    setState(() => _loading = true);

    try {
      if (_isFollowing) {
        await _db
            .from('follows')
            .delete()
            .eq('follower_id', myUserId)
            .eq('followed_profile_id', widget.profileId);

        _isFollowing = false;
        _followersCount = (_followersCount - 1).clamp(0, 1 << 30);
      } else {
        await _db.from('follows').insert({
          'follower_id': myUserId,
          'followed_profile_id': widget.profileId,
        });

        _isFollowing = true;
        _followersCount = _followersCount + 1;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Follow error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _profile == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Profile')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('Profile error:\n$_error'),
        ),
      );
    }

    final name = (_profile?['full_name'] ?? 'Profile').toString();
    final bio = (_profile?['bio'] ?? '').toString();
    final type = (_profile?['profile_type'] ?? _profile?['account_type'] ?? '').toString();

    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: RefreshIndicator(
        onRefresh: _loadAll,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(name, style: Theme.of(context).textTheme.headlineSmall),
            if (type.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('Type: $type', style: const TextStyle(fontSize: 12)),
            ],
            if (bio.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(bio),
            ],
            const SizedBox(height: 16),

           Row(
  children: [
    Expanded(
      child: InkWell(
        onTap: () => context.push('/p/${widget.profileId}/followers'),
        borderRadius: BorderRadius.circular(12),
        child: _StatTile(label: 'Followers', value: _followersCount),
      ),
    ),
    const SizedBox(width: 12),
    Expanded(
      child: InkWell(
        onTap: () => context.push('/p/${widget.profileId}/following'),
        borderRadius: BorderRadius.circular(12),
        child: _StatTile(label: 'Following', value: _followingCount),
      ),
    ),
  ],
),

            const SizedBox(height: 16),
            if (!_isMe)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loading ? null : _toggleFollow,
                  child: Text(_isFollowing ? 'Unfollow' : 'Follow'),
                ),
              )
            else
              const Text('This is your profile', textAlign: TextAlign.center),

            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: Text('Posts', style: Theme.of(context).textTheme.titleMedium),
                ),
                IconButton(
                  tooltip: 'Refresh posts',
                  onPressed: _postsLoading ? null : _loadPosts,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 8),

            if (_postsLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_postsError != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text('Posts error:\n$_postsError'),
              )
            else if (_posts.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('No posts yet.'),
              )
            else
              ..._posts.map(_PostCard.new),
          ],
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final int value;
  const _StatTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text('$value', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(label),
          ],
        ),
      ),
    );
  }
}

class _PostCard extends StatelessWidget {
  final Post p;
  const _PostCard(this.p);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
            Text(
              p.createdAt.toLocal().toString(),
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
