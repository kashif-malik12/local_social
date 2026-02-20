import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum FollowListMode { followers, following }

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

  String get _title => widget.mode == FollowListMode.followers ? 'Followers' : 'Following';

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
            .order('created_at', ascending: false);
      } else {
        followRows = await _db
            .from('follows')
            .select('followed_profile_id, created_at')
            .eq('follower_id', widget.profileId)
            .order('created_at', ascending: false);
      }

      final ids = <String>[];
      for (final r in followRows) {
        final m = r as Map<String, dynamic>;
        final id = (widget.mode == FollowListMode.followers
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
      appBar: AppBar(title: Text(_title)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('Error:\n$_error'),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: _profiles.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final p = _profiles[i];
                      final id = p['id']?.toString();
                      final name = (p['full_name'] ?? 'Unknown').toString();
                      final type = (p['profile_type'] ?? p['account_type'] ?? '').toString();

                      return ListTile(
                        onTap: id == null ? null : () => context.push('/p/$id'),
                        title: Text(name),
                        subtitle: type.isEmpty ? null : Text(type),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Theme.of(context).dividerColor),
                          ),
                          child: Text(_badge(type), style: const TextStyle(fontSize: 12)),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
