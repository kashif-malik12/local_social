import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../services/follow_service.dart';

class FollowRequestsScreen extends StatefulWidget {
  const FollowRequestsScreen({super.key});

  @override
  State<FollowRequestsScreen> createState() => _FollowRequestsScreenState();
}

class _FollowRequestsScreenState extends State<FollowRequestsScreen> {
  final _db = Supabase.instance.client;
  late final FollowService _follow;

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _follow = FollowService(_db);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final rows = await _follow.incomingRequests(limit: 100);
      if (!mounted) return;
      setState(() => _items = rows);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _accept(String followerId) async {
    try {
      await _follow.acceptRequest(followerId);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Accept failed: $e')),
      );
    }
  }

  Future<void> _decline(String followerId) async {
    try {
      await _follow.declineRequest(followerId);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Decline failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Follow requests')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(16), child: Text(_error!)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _items.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: const [
                            SizedBox(height: 120),
                            Center(child: Text('No follow requests')),
                          ],
                        )
                      : ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: _items.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final row = _items[index];
                            final followerId = row['follower_id'] as String;

                            final p = row['profiles'] as Map<String, dynamic>?;
                            final name = (p?['full_name'] ?? 'Unknown').toString();
                            final avatarUrl = (p?['avatar_url'] as String?)?.trim();

                            return ListTile(
                              leading: CircleAvatar(
                                backgroundImage: (avatarUrl != null && avatarUrl.isNotEmpty)
                                    ? NetworkImage(avatarUrl)
                                    : null,
                                child: (avatarUrl == null || avatarUrl.isEmpty)
                                    ? const Icon(Icons.person)
                                    : null,
                              ),
                              title: Text(name),
                              subtitle: const Text('Requested to follow you'),
                              onTap: () => context.push('/p/$followerId'),
                              trailing: Wrap(
                                spacing: 8,
                                children: [
                                  OutlinedButton(
                                    onPressed: () => _decline(followerId),
                                    child: const Text('Decline'),
                                  ),
                                  ElevatedButton(
                                    onPressed: () => _accept(followerId),
                                    child: const Text('Accept'),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
    );
  }
}