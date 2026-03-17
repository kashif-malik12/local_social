import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/business_categories.dart';
import '../core/localization/app_localizations.dart';
import '../widgets/global_app_bar.dart';
import '../widgets/global_bottom_nav.dart';

class BusinessesScreen extends StatefulWidget {
  const BusinessesScreen({super.key});

  @override
  State<BusinessesScreen> createState() => _BusinessesScreenState();
}

class _BusinessesScreenState extends State<BusinessesScreen> {
  bool _loading = true;
  String? _error;
  String _search = '';
  String _selectedCategory = 'all';
  double _maxDistanceKm = 20;
  final _searchCtrl = TextEditingController();

  double? _meLat;
  double? _meLng;
  List<Map<String, dynamic>> _businesses = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  double _toRad(double d) => d * math.pi / 180;

  double _distanceKm(double lat1, double lng1, double lat2, double lng2) {
    const earth = 6371.0;
    final dLat = _toRad(lat2 - lat1);
    final dLng = _toRad(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRad(lat1)) *
            math.cos(_toRad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earth * c;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final db = Supabase.instance.client;
      final me = db.auth.currentUser;

      if (me != null) {
        final myProfile = await db
            .from('profiles')
            .select('latitude, longitude')
            .eq('id', me.id)
            .maybeSingle();
        _meLat = (myProfile?['latitude'] as num?)?.toDouble();
        _meLng = (myProfile?['longitude'] as num?)?.toDouble();
      }

      List<Map<String, dynamic>> rows;
      try {
        final data = await db
            .from('profiles')
            .select(
                'id, full_name, business_name, job_title, bio, business_profile, avatar_url, city, latitude, longitude, account_type, is_restaurant, business_type, is_disabled')
            .eq('account_type', 'business')
            .eq('is_restaurant', false)
            .eq('is_disabled', false)
            .order('business_name');
        rows = (data as List).cast<Map<String, dynamic>>();
      } on PostgrestException {
        final data = await db
            .from('profiles')
            .select('id, full_name, business_name, job_title, bio, avatar_url, city, latitude, longitude, account_type, business_type, is_disabled')
            .eq('account_type', 'business')
            .order('business_name');

        rows = (data as List)
            .cast<Map<String, dynamic>>()
            .where((r) => r['is_restaurant'] != true && r['is_disabled'] != true)
            .toList();
      }

      var items = rows;

      if (_selectedCategory != 'all') {
        items = items
            .where((r) => (r['business_type'] ?? '').toString() == _selectedCategory)
            .toList();
      }

      if (_search.trim().isNotEmpty) {
        final q = _search.toLowerCase().trim();
        items = items.where((r) {
          return (r['business_name'] ?? '').toString().toLowerCase().contains(q) ||
              (r['full_name'] ?? '').toString().toLowerCase().contains(q) ||
              (r['bio'] ?? '').toString().toLowerCase().contains(q) ||
              (r['business_profile'] ?? '').toString().toLowerCase().contains(q) ||
              (r['city'] ?? '').toString().toLowerCase().contains(q) ||
              businessCategoryLabel((r['business_type'] ?? '').toString())
                  .toLowerCase()
                  .contains(q);
        }).toList();
      }

      if (_meLat != null && _meLng != null) {
        items = items.where((r) {
          final lat = (r['latitude'] as num?)?.toDouble();
          final lng = (r['longitude'] as num?)?.toDouble();
          if (lat == null || lng == null) return false;
          return _distanceKm(_meLat!, _meLng!, lat, lng) <= _maxDistanceKm;
        }).toList();

        items.sort((a, b) {
          final aLat = (a['latitude'] as num?)?.toDouble();
          final aLng = (a['longitude'] as num?)?.toDouble();
          final bLat = (b['latitude'] as num?)?.toDouble();
          final bLng = (b['longitude'] as num?)?.toDouble();
          final ad = (aLat != null && aLng != null)
              ? _distanceKm(_meLat!, _meLng!, aLat, aLng)
              : 9999.0;
          final bd = (bLat != null && bLng != null)
              ? _distanceKm(_meLat!, _meLng!, bLat, bLng)
              : 9999.0;
          return ad.compareTo(bd);
        });
      }

      if (!mounted) return;
      setState(() => _businesses = items);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: GlobalAppBar(
        title: l10n.tr('businesses'),
        showBackIfPossible: true,
        homeRoute: '/feed',
      ),
      bottomNavigationBar: const GlobalBottomNav(),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: l10n.tr('search_businesses'),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _search.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _search = '');
                          _load();
                        },
                        icon: const Icon(Icons.clear),
                      ),
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (v) {
                setState(() => _search = v);
                _load();
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: DropdownButtonFormField<String>(
              initialValue: _selectedCategory,
              items: [
                DropdownMenuItem(value: 'all', child: Text(l10n.tr('all_categories'))),
                ...businessMainCategories.map(
                  (c) => DropdownMenuItem(value: c, child: Text(businessCategoryLabel(c))),
                ),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() => _selectedCategory = v);
                _load();
              },
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: l10n.tr('business_category'),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(
              children: [
                Text(l10n.tr('distance_label')),
                Expanded(
                  child: Slider(
                    value: _maxDistanceKm,
                    min: 1,
                    max: 50,
                    divisions: 49,
                    label: '${_maxDistanceKm.toStringAsFixed(0)} km',
                    onChanged: (v) => setState(() => _maxDistanceKm = v),
                    onChangeEnd: (_) => _load(),
                  ),
                ),
                Text('${_maxDistanceKm.toStringAsFixed(0)} km'),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(l10n.tr('error_with_detail', args: {'error': '$_error'})))
                    : _businesses.isEmpty
                        ? Center(child: Text(l10n.tr('no_businesses_found')))
                        : ListView.separated(
                            itemCount: _businesses.length,
                            separatorBuilder: (_, _) => const Divider(height: 1),
                            itemBuilder: (context, i) {
                              final b = _businesses[i];
                              final lat = (b['latitude'] as num?)?.toDouble();
                              final lng = (b['longitude'] as num?)?.toDouble();
                              final dist = (_meLat != null &&
                                      _meLng != null &&
                                      lat != null &&
                                      lng != null)
                                  ? _distanceKm(_meLat!, _meLng!, lat, lng)
                                  : null;

                              final id = (b['id'] ?? '').toString();

                                final userName = (b['full_name'] as String?) ?? '';
                                final bName = (b['business_name'] as String?) ?? userName;
                                final job = b['job_title'] as String?;
                                final businessProfile =
                                    (b['business_profile'] as String?) ?? '';

                                return Card(
                                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  child: ListTile(
                                  onTap: id.isEmpty ? null : () => context.push('/p/$id'),
                                  contentPadding: const EdgeInsets.all(12),
                                  leading: ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Container(
                                      width: 64,
                                      height: 64,
                                      color: Colors.grey.shade200,
                                      padding: const EdgeInsets.all(6),
                                      child: (b['avatar_url'] ?? '').toString().isNotEmpty
                                          ? Image.network(
                                              (b['avatar_url'] ?? '').toString(),
                                              fit: BoxFit.contain,
                                            )
                                          : const Icon(Icons.business),
                                    ),
                                  ),
                                  title: Text(userName.isNotEmpty ? userName : bName),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      if (bName.isNotEmpty && bName != userName)
                                        Padding(
                                          padding: const EdgeInsets.only(bottom: 2),
                                          child: Text(
                                            bName,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                      if (job != null && job.isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(bottom: 2),
                                          child: Text(
                                            job,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      Text(
                                        '${(b['business_type'] ?? '').toString().isNotEmpty ? businessCategoryLabel((b['business_type'] ?? '').toString()) : l10n.tr('business')}'
                                        '${dist != null ? ' • ${dist.toStringAsFixed(1)} km' : ''}'
                                        '${(b['city'] ?? '').toString().isNotEmpty ? ' • ${(b['city'] ?? '').toString()}' : ''}',
                                      ),
                                      if (businessProfile.trim().isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 4),
                                          child: Text(
                                            businessProfile.trim(),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                    ],
                                  ),
                                  ),
                                );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}
