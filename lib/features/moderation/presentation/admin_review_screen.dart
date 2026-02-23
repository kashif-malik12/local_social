import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminReviewScreen extends StatefulWidget {
  const AdminReviewScreen({super.key});

  @override
  State<AdminReviewScreen> createState() => _AdminReviewScreenState();
}

class _AdminReviewScreenState extends State<AdminReviewScreen>
    with SingleTickerProviderStateMixin {
  final _db = Supabase.instance.client;

  late final TabController _tab;

  bool _checkingAdmin = true;
  bool _isAdmin = false;

  String _statusFilter = 'pending'; // pending | reviewed | dismissed

  bool _loadingPosts = true;
  bool _loadingUsers = true;
  String? _errorPosts;
  String? _errorUsers;

  List<Map<String, dynamic>> _postReports = [];
  List<Map<String, dynamic>> _userReports = [];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _init();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    await _checkAdmin();
    if (_isAdmin) {
      await Future.wait([_loadPostReports(), _loadUserReports()]);
    }
  }

  Future<void> _checkAdmin() async {
    setState(() {
      _checkingAdmin = true;
      _isAdmin = false;
    });

    try {
      final uid = _db.auth.currentUser?.id;
      if (uid == null) {
        setState(() {
          _checkingAdmin = false;
          _isAdmin = false;
        });
        return;
      }

      final row = await _db
          .from('profiles')
          .select('is_admin')
          .eq('id', uid)
          .maybeSingle();

      setState(() {
        _isAdmin = (row?['is_admin'] == true);
        _checkingAdmin = false;
      });
    } catch (e) {
      setState(() {
        _checkingAdmin = false;
        _isAdmin = false;
      });
    }
  }

  Future<void> _loadPostReports() async {
    setState(() {
      _loadingPosts = true;
      _errorPosts = null;
    });

    try {
      // You can expand joins later (post author, reporter name, etc.)
      final rows = await _db
          .from('post_reports')
          .select('id, created_at, reporter_id, post_id, reason, details, status')
          .eq('status', _statusFilter)
          .order('created_at', ascending: false);

      setState(() {
        _postReports = List<Map<String, dynamic>>.from(rows);
        _loadingPosts = false;
      });
    } catch (e) {
      setState(() {
        _errorPosts = e.toString();
        _loadingPosts = false;
      });
    }
  }

  Future<void> _loadUserReports() async {
    setState(() {
      _loadingUsers = true;
      _errorUsers = null;
    });

    try {
      final rows = await _db
          .from('user_reports')
          .select(
              'id, created_at, reporter_id, reported_user_id, reason, details, status')
          .eq('status', _statusFilter)
          .order('created_at', ascending: false);

      setState(() {
        _userReports = List<Map<String, dynamic>>.from(rows);
        _loadingUsers = false;
      });
    } catch (e) {
      setState(() {
        _errorUsers = e.toString();
        _loadingUsers = false;
      });
    }
  }

  Future<void> _refreshCurrentTab() async {
    if (_tab.index == 0) {
      await _loadPostReports();
    } else {
      await _loadUserReports();
    }
  }

  void _setFilter(String value) {
    setState(() => _statusFilter = value);
    _refreshCurrentTab();
  }

  Future<void> _setReportStatus({
    required String table,
    required String reportId,
    required String status,
  }) async {
    try {
      await _db.rpc('admin_set_report_status', params: {
        'p_table': table,
        'p_report_id': reportId,
        'p_status': status,
      });
      await _refreshCurrentTab();
      if (mounted) _snack('Report marked $status');
    } catch (e) {
      if (mounted) _snack('Failed: $e');
    }
  }

  Future<void> _softDeletePost(String postId) async {
    final ok = await _confirm(
      title: 'Delete post?',
      message:
          'This will soft-delete the post (hide it in feeds). You can also mark the report reviewed.',
      confirmText: 'Delete',
      danger: true,
    );
    if (!ok) return;

    try {
      await _db.rpc('admin_soft_delete_post', params: {'p_post_id': postId});
      if (mounted) _snack('Post deleted');
    } catch (e) {
      if (mounted) _snack('Failed: $e');
    }
  }

  Future<void> _setUserBan(String userId, bool banned) async {
    final ok = await _confirm(
      title: banned ? 'Ban user?' : 'Unban user?',
      message: banned
          ? 'This will prevent the user from using the app (based on your app logic).'
          : 'This will restore access.',
      confirmText: banned ? 'Ban' : 'Unban',
      danger: banned,
    );
    if (!ok) return;

    try {
      await _db.rpc('admin_set_user_ban',
          params: {'p_user_id': userId, 'p_banned': banned});
      if (mounted) _snack(banned ? 'User banned' : 'User unbanned');
    } catch (e) {
      if (mounted) _snack('Failed: $e');
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmText,
    bool danger = false,
  }) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: danger
                ? ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                    foregroundColor: Theme.of(context).colorScheme.onError,
                  )
                : null,
            child: Text(confirmText),
          ),
        ],
      ),
    );
    return res == true;
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingAdmin) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!_isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Admin Review')),
        body: const Center(
          child: Text('Access denied.'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Review'),
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: 'Post Reports'),
            Tab(text: 'User Reports'),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _refreshCurrentTab,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          _StatusChips(
            value: _statusFilter,
            onChanged: _setFilter,
          ),
          const Divider(height: 1),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                _buildPostReports(),
                _buildUserReports(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPostReports() {
    if (_loadingPosts) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorPosts != null) {
      return Center(child: Text(_errorPosts!));
    }
    if (_postReports.isEmpty) {
      return const Center(child: Text('No reports.'));
    }

    return RefreshIndicator(
      onRefresh: _loadPostReports,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _postReports.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final r = _postReports[i];
          final id = r['id'].toString();
          final postId = r['post_id'].toString();
          final reason = (r['reason'] ?? '').toString();
          final details = (r['details'] ?? '').toString();
          final reporterId = r['reporter_id']?.toString() ?? '';
          final createdAt = (r['created_at'] ?? '').toString();

          return _ReportCard(
            title: reason.isEmpty ? 'Post report' : reason,
            subtitle:
                'Post: $postId\nReporter: $reporterId\nCreated: $createdAt',
            details: details.isEmpty ? null : details,
            actions: [
              TextButton.icon(
                onPressed: () => _setReportStatus(
                  table: 'post_reports',
                  reportId: id,
                  status: 'dismissed',
                ),
                icon: const Icon(Icons.close),
                label: const Text('Dismiss'),
              ),
              TextButton.icon(
                onPressed: () => _setReportStatus(
                  table: 'post_reports',
                  reportId: id,
                  status: 'reviewed',
                ),
                icon: const Icon(Icons.check),
                label: const Text('Reviewed'),
              ),
              ElevatedButton.icon(
                onPressed: () async {
                  await _softDeletePost(postId);
                  // Optional: auto mark reviewed after delete
                  await _setReportStatus(
                    table: 'post_reports',
                    reportId: id,
                    status: 'reviewed',
                  );
                },
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete post'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildUserReports() {
    if (_loadingUsers) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorUsers != null) {
      return Center(child: Text(_errorUsers!));
    }
    if (_userReports.isEmpty) {
      return const Center(child: Text('No reports.'));
    }

    return RefreshIndicator(
      onRefresh: _loadUserReports,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _userReports.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final r = _userReports[i];
          final id = r['id'].toString();
          final reportedUserId = r['reported_user_id'].toString();
          final reason = (r['reason'] ?? '').toString();
          final details = (r['details'] ?? '').toString();
          final reporterId = r['reporter_id']?.toString() ?? '';
          final createdAt = (r['created_at'] ?? '').toString();

          return _ReportCard(
            title: reason.isEmpty ? 'User report' : reason,
            subtitle:
                'User: $reportedUserId\nReporter: $reporterId\nCreated: $createdAt',
            details: details.isEmpty ? null : details,
            actions: [
              TextButton.icon(
                onPressed: () => _setReportStatus(
                  table: 'user_reports',
                  reportId: id,
                  status: 'dismissed',
                ),
                icon: const Icon(Icons.close),
                label: const Text('Dismiss'),
              ),
              TextButton.icon(
                onPressed: () => _setReportStatus(
                  table: 'user_reports',
                  reportId: id,
                  status: 'reviewed',
                ),
                icon: const Icon(Icons.check),
                label: const Text('Reviewed'),
              ),
              ElevatedButton.icon(
                onPressed: () async {
                  await _setUserBan(reportedUserId, true);
                  await _setReportStatus(
                    table: 'user_reports',
                    reportId: id,
                    status: 'reviewed',
                  );
                },
                icon: const Icon(Icons.block),
                label: const Text('Ban user'),
              ),
              OutlinedButton.icon(
                onPressed: () => _setUserBan(reportedUserId, false),
                icon: const Icon(Icons.undo),
                label: const Text('Unban'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StatusChips extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _StatusChips({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final items = const [
      ('pending', 'Pending'),
      ('reviewed', 'Reviewed'),
      ('dismissed', 'Dismissed'),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      child: Row(
        children: items.map((e) {
          final selected = value == e.$1;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(e.$2),
              selected: selected,
              onSelected: (_) => onChanged(e.$1),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? details;
  final List<Widget> actions;

  const _ReportCard({
    required this.title,
    required this.subtitle,
    required this.actions,
    this.details,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: Theme.of(context).textTheme.titleMedium,
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 6),
            Text(subtitle,
                style: Theme.of(context).textTheme.bodySmall,
                maxLines: 5,
                overflow: TextOverflow.ellipsis),
            if (details != null) ...[
              const SizedBox(height: 10),
              Text(
                details!,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: actions,
            ),
          ],
        ),
      ),
    );
  }
}