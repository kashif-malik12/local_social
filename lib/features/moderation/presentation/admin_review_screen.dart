import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminLiveScreen extends StatefulWidget {
  const AdminLiveScreen({super.key});

  @override
  State<AdminLiveScreen> createState() => _AdminLiveScreenState();
}

class _AdminLiveScreenState extends State<AdminLiveScreen>
    with SingleTickerProviderStateMixin {
  final _db = Supabase.instance.client;
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();

  late final TabController _tab;

  bool _checkingAdmin = true;
  bool _isAdmin = false;
  bool _adminLoginLoading = false;
  String? _adminLoginError;

  String _statusFilter = 'pending'; // pending | reviewed | dismissed

  bool _loadingPosts = true;
  bool _loadingUsers = true;
  bool _loadingStats = true;
  String? _errorPosts;
  String? _errorUsers;
  String? _errorStats;

  List<Map<String, dynamic>> _postReports = [];
  List<Map<String, dynamic>> _userReports = [];
  Map<String, int> _stats = const {};
  List<Map<String, dynamic>> _recentPosts = [];
  List<Map<String, dynamic>> _recentUsers = [];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this);
    _init();
  }

  @override
  void dispose() {
    _tab.dispose();
    _email.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    await _checkAdmin();
    if (_isAdmin) {
      await Future.wait([_loadStats(), _loadPostReports(), _loadUserReports()]);
    }
  }

  Future<void> _adminLogin() async {
    setState(() {
      _adminLoginLoading = true;
      _adminLoginError = null;
    });

    try {
      await _db.auth.signInWithPassword(
        email: _email.text.trim(),
        password: _password.text,
      );
      await _init();
    } catch (e) {
      if (!mounted) return;
      setState(() => _adminLoginError = e.toString());
    } finally {
      if (mounted) setState(() => _adminLoginLoading = false);
    }
  }

  Future<void> _logoutAdmin() async {
    await _db.auth.signOut();
    if (!mounted) return;
    setState(() {
      _isAdmin = false;
      _checkingAdmin = false;
      _adminLoginError = null;
    });
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
      await _loadStats();
    } else if (_tab.index == 1) {
      await _loadStats();
    } else if (_tab.index == 2) {
      await _loadPostReports();
    } else {
      await _loadUserReports();
    }
  }

  Future<void> _loadStats() async {
    setState(() {
      _loadingStats = true;
      _errorStats = null;
    });

    try {
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day).toIso8601String();

      final results = await Future.wait<dynamic>([
        _db.from('profiles').select('id, profile_type, account_type, is_restaurant, org_kind'),
        _db.from('posts').select('id, post_type, author_profile_type, market_intent, visibility'),
        _db.from('posts').select('id').gte('created_at', todayStart),
        _db.from('post_reports').select('id').eq('status', 'pending'),
        _db.from('user_reports').select('id').eq('status', 'pending'),
        _db
            .from('posts')
            .select('id, content, market_title, post_type, created_at, user_id, image_url')
            .order('created_at', ascending: false)
            .limit(12),
        _db
            .from('profiles')
            .select('id, full_name, profile_type, account_type, org_kind')
            .order('created_at', ascending: false)
            .limit(12),
      ]);

      final profiles = (results[0] as List).cast<Map<String, dynamic>>();
      final posts = (results[1] as List).cast<Map<String, dynamic>>();
      String profileTypeOf(Map<String, dynamic> row) {
        return ((row['profile_type'] ?? row['account_type']) ?? '').toString().trim();
      }

      String postTypeOf(Map<String, dynamic> row) {
        return (row['post_type'] ?? '').toString().trim();
      }

      final peopleCount = profiles
          .where((row) => profileTypeOf(row) == 'person')
          .length;
      final businessCount = profiles
          .where((row) => profileTypeOf(row) == 'business')
          .length;
      final restaurantCount = profiles
          .where((row) => row['is_restaurant'] == true)
          .length;
      final orgCount = profiles
          .where((row) => profileTypeOf(row) == 'org')
          .length;
      final govCount = profiles
          .where((row) => (row['org_kind'] ?? '').toString() == 'government')
          .length;
      final nonprofitCount = profiles
          .where((row) => (row['org_kind'] ?? '').toString() == 'nonprofit')
          .length;
      final newsAgencyCount = profiles
          .where((row) => (row['org_kind'] ?? '').toString() == 'news_agency')
          .length;

      final marketplaceCount = posts
          .where((row) => postTypeOf(row) == 'market')
          .length;
      final gigCount = posts
          .where((row) {
            final type = postTypeOf(row);
            return type == 'service_offer' || type == 'service_request';
          })
          .length;
      final foodCount = posts
          .where((row) {
            final type = postTypeOf(row);
            return type == 'food_ad' || type == 'food';
          })
          .length;
      final lostFoundCount = posts
          .where((row) => postTypeOf(row) == 'lost_found')
          .length;
      final generalCount = posts
          .where((row) {
            final type = postTypeOf(row);
            return type.isEmpty || type == 'post';
          })
          .length;
      final publicPostCount = posts
          .where((row) => (row['visibility'] ?? '').toString() == 'public')
          .length;
      final localPostCount = posts
          .where((row) => (row['visibility'] ?? '').toString() == 'followers')
          .length;

      if (!mounted) return;
      setState(() {
        _stats = {
          'profiles': profiles.length,
          'people': peopleCount,
          'businesses': businessCount,
          'restaurants': restaurantCount,
          'organizations': orgCount,
          'org_government': govCount,
          'org_nonprofit': nonprofitCount,
          'org_news_agency': newsAgencyCount,
          'posts': posts.length,
          'today_posts': (results[2] as List).length,
          'general_posts': generalCount,
          'marketplace_posts': marketplaceCount,
          'gig_posts': gigCount,
          'food_posts': foodCount,
          'lost_found_posts': lostFoundCount,
          'public_posts': publicPostCount,
          'local_posts': localPostCount,
          'pending_post_reports': (results[3] as List).length,
          'pending_user_reports': (results[4] as List).length,
        };
        _recentPosts = (results[5] as List).cast<Map<String, dynamic>>();
        _recentUsers = (results[6] as List).cast<Map<String, dynamic>>();
        _loadingStats = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorStats = e.toString();
        _loadingStats = false;
      });
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

    if (_db.auth.currentUser == null) {
      return _buildAdminLoginScreen();
    }

    if (!_isAdmin) {
      return _buildAccessDeniedScreen();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Portal'),
        bottom: TabBar(
          controller: _tab,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelPadding: const EdgeInsets.symmetric(horizontal: 16),
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'Moderation'),
            Tab(text: 'Post Reports'),
            Tab(text: 'User Reports'),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () => context.go('/feed'),
            icon: const Icon(Icons.home_outlined),
            tooltip: 'Home',
          ),
          IconButton(
            onPressed: _refreshCurrentTab,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
          IconButton(
            onPressed: _logoutAdmin,
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
          ),
        ],
      ),
      body: Column(
        children: [
          _StatusChips(
            value: _statusFilter,
            onChanged: _setFilter,
            visible: _tab.index >= 2,
          ),
          const Divider(height: 1),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                _buildOverview(),
                _buildModerationTab(),
                _buildPostReports(),
                _buildUserReports(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverview() {
    if (_loadingStats) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorStats != null) {
      return Center(child: Text(_errorStats!));
    }

    return RefreshIndicator(
      onRefresh: _loadStats,
      child: ListView(
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
                  'Admin overview',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Use this dashboard to review reports, watch platform activity, and jump quickly into moderation work.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _StatCard(
                title: 'Profiles',
                value: '${_stats['profiles'] ?? 0}',
                subtitle: 'Registered accounts',
              ),
              _StatCard(
                title: 'Posts',
                value: '${_stats['posts'] ?? 0}',
                subtitle: 'Total published posts',
              ),
              _StatCard(
                title: 'Today',
                value: '${_stats['today_posts'] ?? 0}',
                subtitle: 'Posts created today',
              ),
              _StatCard(
                title: 'Pending Post Reports',
                value: '${_stats['pending_post_reports'] ?? 0}',
                subtitle: 'Need moderation review',
                danger: (_stats['pending_post_reports'] ?? 0) > 0,
              ),
              _StatCard(
                title: 'Pending User Reports',
                value: '${_stats['pending_user_reports'] ?? 0}',
                subtitle: 'Need moderation review',
                danger: (_stats['pending_user_reports'] ?? 0) > 0,
              ),
            ],
          ),
          const SizedBox(height: 18),
          _OverviewSection(
            title: 'Users on the portal',
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _MiniStatCard(title: 'People', value: '${_stats['people'] ?? 0}'),
                _MiniStatCard(title: 'Businesses', value: '${_stats['businesses'] ?? 0}'),
                _MiniStatCard(title: 'Restaurants', value: '${_stats['restaurants'] ?? 0}'),
                _MiniStatCard(title: 'Organizations', value: '${_stats['organizations'] ?? 0}'),
                _MiniStatCard(title: 'Government', value: '${_stats['org_government'] ?? 0}'),
                _MiniStatCard(title: 'Non-profit', value: '${_stats['org_nonprofit'] ?? 0}'),
                _MiniStatCard(title: 'News agency', value: '${_stats['org_news_agency'] ?? 0}'),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _OverviewSection(
            title: 'Content breakdown',
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _MiniStatCard(title: 'General posts', value: '${_stats['general_posts'] ?? 0}'),
                _MiniStatCard(title: 'Marketplace', value: '${_stats['marketplace_posts'] ?? 0}'),
                _MiniStatCard(title: 'Gigs', value: '${_stats['gig_posts'] ?? 0}'),
                _MiniStatCard(title: 'Food ads', value: '${_stats['food_posts'] ?? 0}'),
                _MiniStatCard(title: 'Lost & found', value: '${_stats['lost_found_posts'] ?? 0}'),
                _MiniStatCard(title: 'Public posts', value: '${_stats['public_posts'] ?? 0}'),
                _MiniStatCard(title: 'Local posts', value: '${_stats['local_posts'] ?? 0}'),
              ],
            ),
          ),
          Row(
            children: [
              Expanded(
                child: _AdminActionCard(
                  title: 'Review post reports',
                  subtitle: 'Check reported posts, dismiss noise, or remove harmful posts.',
                  icon: Icons.flag_outlined,
                  onTap: () => _tab.animateTo(2),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _AdminActionCard(
                  title: 'Review user reports',
                  subtitle: 'Handle abusive accounts and apply bans or unbans.',
                  icon: Icons.person_off_outlined,
                  onTap: () => _tab.animateTo(3),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFE6DDCE)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Admin notes',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 12),
                _buildNoteLine('Pending queues update when you refresh the dashboard or reports tabs.'),
                _buildNoteLine('Deleting a post hides it from feeds.'),
                _buildNoteLine('Banning a user depends on your backend app logic using the ban flag/RPC.'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdminLoginScreen() {
    final theme = Theme.of(context);
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0B1220), Color(0xFF101B31)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1080),
              child: Container(
                margin: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F7F5),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x33000000),
                      blurRadius: 28,
                      offset: Offset(0, 18),
                    ),
                  ],
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 860;

                    final leftPanel = Container(
                      padding: const EdgeInsets.all(34),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF121A2B), Color(0xFF0F2A3C)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(30),
                          bottomLeft: Radius.circular(30),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 68,
                            height: 68,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Icon(
                              Icons.admin_panel_settings_outlined,
                              color: Colors.white,
                              size: 34,
                            ),
                          ),
                          const SizedBox(height: 24),
                          const Text(
                            'Admin Portal',
                            style: TextStyle(
                              fontSize: 42,
                              height: 1,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: -1.1,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'Moderation, platform stats, reports, user controls, and content review in one admin portal.',
                            style: TextStyle(
                              fontSize: 16,
                              height: 1.5,
                              color: Colors.white.withOpacity(0.82),
                            ),
                          ),
                          const SizedBox(height: 28),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: const [
                              _AdminLoginChip(label: 'Moderation'),
                              _AdminLoginChip(label: 'Site stats'),
                              _AdminLoginChip(label: 'Reports'),
                              _AdminLoginChip(label: 'User control'),
                            ],
                          ),
                        ],
                      ),
                    );

                    final rightPanel = Padding(
                      padding: const EdgeInsets.all(30),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 430),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Admin sign in',
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Use an admin account to enter the portal.',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 22),
                              TextField(
                                controller: _email,
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: TextInputAction.next,
                                onSubmitted: (_) => _passwordFocus.requestFocus(),
                                decoration: const InputDecoration(
                                  labelText: 'Admin email',
                                  prefixIcon: Icon(Icons.mail_outline),
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _password,
                                focusNode: _passwordFocus,
                                obscureText: true,
                                textInputAction: TextInputAction.done,
                                onSubmitted: (_) {
                                  if (!_adminLoginLoading) _adminLogin();
                                },
                                decoration: const InputDecoration(
                                  labelText: 'Password',
                                  prefixIcon: Icon(Icons.lock_outline),
                                ),
                              ),
                              if (_adminLoginError != null) ...[
                                const SizedBox(height: 12),
                                Text(
                                  _adminLoginError!,
                                  style: const TextStyle(color: Color(0xFFD92D20)),
                                ),
                              ],
                              const SizedBox(height: 18),
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton(
                                  onPressed: _adminLoginLoading ? null : _adminLogin,
                                  child: Text(
                                    _adminLoginLoading ? 'Signing in...' : 'Open admin portal',
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: () => context.go('/login'),
                                  child: const Text('Go to main login'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );

                    if (!wide) {
                      return SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: double.infinity,
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [Color(0xFF121A2B), Color(0xFF0F2A3C)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.only(
                                  topLeft: Radius.circular(30),
                                  topRight: Radius.circular(30),
                                ),
                              ),
                              child: leftPanel,
                            ),
                            rightPanel,
                          ],
                        ),
                      );
                    }

                    return Row(
                      children: [
                        Expanded(flex: 11, child: leftPanel),
                        Expanded(flex: 10, child: rightPanel),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAccessDeniedScreen() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Portal'),
        actions: [
          IconButton(
            onPressed: () => context.go('/feed'),
            icon: const Icon(Icons.home_outlined),
          ),
          IconButton(
            onPressed: _logoutAdmin,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.admin_panel_settings_outlined, size: 42),
                  const SizedBox(height: 14),
                  Text(
                    'Admin access required',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'This account does not have admin access to the moderation portal.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    alignment: WrapAlignment.center,
                    children: [
                      OutlinedButton(
                        onPressed: () => context.go('/feed'),
                        child: const Text('Go home'),
                      ),
                      FilledButton(
                        onPressed: _logoutAdmin,
                        child: const Text('Logout'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModerationTab() {
    if (_loadingStats) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorStats != null) {
      return Center(child: Text(_errorStats!));
    }

    return RefreshIndicator(
      onRefresh: _loadStats,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _OverviewSection(
            title: 'Posts to verify',
            child: Column(
              children: _recentPosts.isEmpty
                  ? [const Text('No recent posts found.')]
                  : _recentPosts
                      .map((post) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _AdminPostPreviewCard(
                              title: ((post['market_title'] ?? '').toString().trim().isNotEmpty
                                      ? post['market_title']
                                      : post['content'])!
                                  .toString(),
                              subtitle:
                                  '${_adminPostTypeLabel((post['post_type'] ?? '').toString())} • ${(post['created_at'] ?? '').toString()}',
                              imageUrl: (post['image_url'] ?? '').toString(),
                              body: (post['content'] ?? '').toString(),
                              onRemove: () => _softDeletePost((post['id'] ?? '').toString()),
                            ),
                          ))
                      .toList(),
            ),
          ),
          const SizedBox(height: 18),
          _OverviewSection(
            title: 'Users to review',
            child: Column(
              children: _recentUsers.isEmpty
                  ? [const Text('No users found.')]
                  : _recentUsers
                      .map((user) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _AdminUserListTile(
                              title: ((user['full_name'] ?? 'Unnamed user')).toString(),
                              subtitle: _adminUserTypeLabel(user),
                              onBan: () => _setUserBan((user['id'] ?? '').toString(), true),
                              onUnban: () => _setUserBan((user['id'] ?? '').toString(), false),
                            ),
                          ))
                      .toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoteLine(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Icon(Icons.circle, size: 8, color: Color(0xFFCC7A00)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }

  String _adminPostTypeLabel(String value) {
    switch (value) {
      case 'market':
        return 'Marketplace';
      case 'service_offer':
        return 'Gig offer';
      case 'service_request':
        return 'Gig request';
      case 'food_ad':
      case 'food':
        return 'Food ad';
      case 'lost_found':
        return 'Lost & found';
      case 'post':
      case '':
        return 'General post';
      default:
        return value;
    }
  }

  String _adminUserTypeLabel(Map<String, dynamic> user) {
    final type = ((user['profile_type'] ?? user['account_type']) ?? '').toString();
    final orgKind = (user['org_kind'] ?? '').toString();

    if (type == 'org' && orgKind.isNotEmpty) {
      return 'Organization • $orgKind';
    }
    if (type.isEmpty) return 'Unknown type';
    return type[0].toUpperCase() + type.substring(1);
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
  final bool visible;

  const _StatusChips({
    required this.value,
    required this.onChanged,
    this.visible = true,
  });

  @override
  Widget build(BuildContext context) {
    if (!visible) {
      return const SizedBox.shrink();
    }
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

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final bool danger;

  const _StatCard({
    required this.title,
    required this.value,
    required this.subtitle,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: danger ? const Color(0xFFD92D20) : const Color(0xFFE6DDCE),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: danger ? const Color(0xFFD92D20) : null,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminActionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const _AdminActionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFE6DDCE)),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: const Color(0xFFF4EBDD),
              child: Icon(icon, color: const Color(0xFFCC7A00)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}

class _OverviewSection extends StatelessWidget {
  final String title;
  final Widget child;

  const _OverviewSection({
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE6DDCE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _MiniStatCard extends StatelessWidget {
  final String title;
  final String value;

  const _MiniStatCard({
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 170,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE6DDCE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
        ],
      ),
    );
  }
}

class _AdminLoginChip extends StatelessWidget {
  final String label;

  const _AdminLoginChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: Colors.white.withOpacity(0.9),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _AdminPostListTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onRemove;

  const _AdminPostListTile({
    required this.title,
    required this.subtitle,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE6DDCE)),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 20,
            backgroundColor: Color(0xFFF4EBDD),
            child: Icon(Icons.article_outlined, color: Color(0xFFCC7A00)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title.trim().isEmpty ? 'Untitled post' : title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: onRemove,
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('Remove'),
          ),
        ],
      ),
    );
  }
}

class _AdminPostPreviewCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String imageUrl;
  final String body;
  final VoidCallback onRemove;

  const _AdminPostPreviewCard({
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.body,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE6DDCE)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: 96,
              height: 96,
              color: const Color(0xFFF4EBDD),
              child: imageUrl.trim().isEmpty
                  ? const Icon(Icons.image_outlined, color: Color(0xFFCC7A00))
                  : Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.broken_image_outlined,
                        color: Color(0xFFCC7A00),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title.trim().isEmpty ? 'Untitled post' : title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                if (body.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    body,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: onRemove,
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('Remove post'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminUserListTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onBan;
  final VoidCallback onUnban;

  const _AdminUserListTile({
    required this.title,
    required this.subtitle,
    required this.onBan,
    required this.onUnban,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE6DDCE)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: const Color(0xFFF4EBDD),
            child: Text(
              title.trim().isEmpty ? '?' : title.trim()[0].toUpperCase(),
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: Color(0xFFCC7A00),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title.trim().isEmpty ? 'Unnamed user' : title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: onBan,
                child: const Text('Ban'),
              ),
              OutlinedButton(
                onPressed: onUnban,
                child: const Text('Unban'),
              ),
            ],
          ),
        ],
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
