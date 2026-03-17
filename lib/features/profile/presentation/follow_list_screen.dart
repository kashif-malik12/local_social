import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../widgets/global_app_bar.dart';
import '../../../widgets/global_bottom_nav.dart';

enum FollowListMode { followers, following, connections }

class FollowListScreen extends StatefulWidget {
  final String profileId; // profiles.id == auth.uid in your app
  final FollowListMode mode;

  const FollowListScreen({
    super.key,
    required this.profileId,
    required this.mode,
  });

  @override
  State<FollowListScreen> createState() => _FollowListScreenState();
}

class _FollowListScreenState extends State<FollowListScreen> {
  final _db = Supabase.instance.client;

  bool _loading = true;
  String? _error;

  // Each item: {id, full_name, profile_type/account_type}
  List<Map<String, dynamic>> _profiles = [];

  String get _title {
    switch (widget.mode) {
      case FollowListMode.followers:
        return 'Followers';
      case FollowListMode.following:
        return 'Following';
      case FollowListMode.connections:
        return 'Connections';
    }
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
      _profiles = [];
    });

    try {
      // 1) Get ids from follows (NO JOIN to avoid wrong FK)
      final List<dynamic> followRows;

      if (widget.mode == FollowListMode.followers) {
        followRows = await _db
            .from('follows')
            .select('follower_id, created_at')
            .eq('followed_profile_id', widget.profileId)
            .eq('status', 'accepted')
            .order('created_at', ascending: false);
      } else if (widget.mode == FollowListMode.following) {
        followRows = await _db
            .from('follows')
            .select('followed_profile_id, created_at')
            .eq('follower_id', widget.profileId)
            .eq('status', 'accepted')
            .order('created_at', ascending: false);
      } else {
        final followers = await _db
            .from('follows')
            .select('follower_id, created_at')
            .eq('followed_profile_id', widget.profileId)
            .eq('status', 'accepted')
            .order('created_at', ascending: false);

        final following = await _db
            .from('follows')
            .select('followed_profile_id')
            .eq('follower_id', widget.profileId)
            .eq('status', 'accepted');

        final followingIds = (following as List)
            .map((row) => (row['followed_profile_id'] ?? '').toString())
            .where((id) => id.isNotEmpty)
            .toSet();

        followRows = (followers as List)
            .cast<Map<String, dynamic>>()
            .where((row) => followingIds.contains((row['follower_id'] ?? '').toString()))
            .toList();
      }

      final ids = <String>[];
      for (final r in followRows) {
        final m = r as Map<String, dynamic>;
        final id = (widget.mode == FollowListMode.followers ||
                widget.mode == FollowListMode.connections
            ? m['follower_id']
            : m['followed_profile_id'])
        ?.toString();
        if (id != null) ids.add(id);
      }

      if (ids.isEmpty) {
        setState(() {
          _profiles = [];
        });
        return;
      }

      // 2) Load profiles for those ids
      final profRows = await _db
          .from('profiles')
          .select('id, full_name, profile_type, account_type')
          .inFilter('id', ids);

      final profList = (profRows as List).cast<Map<String, dynamic>>();

      // 3) Keep same order as follows rows
      final byId = <String, Map<String, dynamic>>{};
      for (final p in profList) {
        final id = p['id']?.toString();
        if (id != null) byId[id] = p;
      }

      final ordered = <Map<String, dynamic>>[];
      for (final id in ids) {
        final p = byId[id];
        if (p != null) ordered.add(p);
      }

      setState(() {
        _profiles = ordered;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _badge(String? type) {
    final t = (type ?? '').toLowerCase();
    if (t == 'business') return 'BUSINESS';
    if (t == 'org') return 'ORG';
    return 'PERSON';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GlobalAppBar(
        title: _title,
        showBackIfPossible: true,
        homeRoute: '/feed',
      ),
      bottomNavigationBar: const GlobalBottomNav(),
      body: RefreshIndicator(
        onRefresh: _load,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFFFCF7), Color(0xFFF4EBDD)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: const Color(0xFFE6DDCE)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _title,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${_profiles.length} profile${_profiles.length == 1 ? '' : 's'}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_error != null)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('Error:\n$_error'),
                  )
                else if (_profiles.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: const Color(0xFFE6DDCE)),
                    ),
                    child: Center(child: Text('No ${_title.toLowerCase()} yet')),
                  )
                else
                  ..._profiles.map((p) {
                    final id = p['id']?.toString();
                    final name = (p['full_name'] ?? 'Unknown').toString();
                    final type = (p['profile_type'] ?? p['account_type'] ?? '').toString();

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Material(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(22),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(22),
                          onTap: id == null ? null : () => context.push('/p/$id'),
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(color: const Color(0xFFE6DDCE)),
                            ),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 22,
                                  child: Text(
                                    name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase(),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name,
                                        style: const TextStyle(fontWeight: FontWeight.w700),
                                      ),
                                      if (type.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          type,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(999),
                                    color: Theme.of(context)
                                        .colorScheme
                                        .surfaceContainerHighest
                                        .withValues(alpha: 0.55),
                                  ),
                                  child: Text(
                                    _badge(type),
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
