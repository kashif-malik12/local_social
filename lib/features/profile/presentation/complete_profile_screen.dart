import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geocoding/geocoding.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

class CompleteProfileScreen extends StatefulWidget {
  const CompleteProfileScreen({super.key});

  @override
  State<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends State<CompleteProfileScreen> {
  final _name = TextEditingController();
  final _bio = TextEditingController();

  final _zipCtrl = TextEditingController();
  double? _lat;
  double? _lng;

  String _accountType = 'person'; // person | business | org
  String? _orgKind; // government | nonprofit (only when org)
  int _radiusKm = 5;

  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _name.dispose();
    _bio.dispose();
    _zipCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      final data = await Supabase.instance.client
          .from('profiles')
          .select(
              'full_name, bio, zipcode, latitude, longitude, profile_type, account_type, org_kind, radius_km')
          .eq('id', user.id)
          .maybeSingle();

      if (data == null || !mounted) return;

      setState(() {
        _name.text = (data['full_name'] as String?) ?? '';
        _bio.text = (data['bio'] as String?) ?? '';
        _zipCtrl.text = (data['zipcode'] as String?) ?? '';

        _lat = (data['latitude'] as num?)?.toDouble();
        _lng = (data['longitude'] as num?)?.toDouble();

        // Prefer profile_type; fallback to account_type for older rows
        _accountType = (data['profile_type'] as String?) ??
            (data['account_type'] as String?) ??
            'person';

        _orgKind = data['org_kind'] as String?;
        _radiusKm = (data['radius_km'] as int?) ?? 5;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Failed to load profile: $e');
    }
  }

  Future<void> _setFromZipcode() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final zip = _zipCtrl.text.trim();

      if (!RegExp(r'^\d{5}$').hasMatch(zip)) {
        throw 'Enter a valid 5-digit French postal code (e.g. 91000)';
      }

      double? lat;
      double? lng;

      if (kIsWeb) {
        final uri = Uri.parse(
          'https://nominatim.openstreetmap.org/search'
          '?format=json&country=France&postalcode=$zip&limit=1',
        );

        final res = await http.get(uri, headers: {
          'User-Agent': 'local-social-app/1.0',
        });

        if (res.statusCode != 200) {
          throw 'Geocoding failed (HTTP ${res.statusCode}). Try again.';
        }

        final data = jsonDecode(res.body);
        if (data is! List || data.isEmpty) {
          throw 'Postal code not found. Try another one.';
        }

        lat = double.tryParse(data[0]['lat']?.toString() ?? '');
        lng = double.tryParse(data[0]['lon']?.toString() ?? '');

        if (lat == null || lng == null) {
          throw 'Geocoding returned invalid coordinates. Try another zip.';
        }
      } else {
        final results = await locationFromAddress('$zip, France');
        if (results.isEmpty) {
          throw 'Postal code not found. Try another one.';
        }
        lat = results.first.latitude;
        lng = results.first.longitude;
      }

      if (!mounted) return;

      setState(() {
        _lat = lat;
        _lng = lng;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Location set for $zip')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw 'Not logged in';

      final fullName = _name.text.trim();
      if (fullName.isEmpty) throw 'Name is required';

      final zip = _zipCtrl.text.trim();
      if (!RegExp(r'^\d{5}$').hasMatch(zip)) {
        throw 'Enter a valid 5-digit French postal code (e.g. 91000)';
      }

      if (_accountType == 'org' && _orgKind == null) {
        throw 'Please select Government or Non-profit';
      }

      if (_lat == null || _lng == null) {
        throw 'Please set your location (zip code) first';
      }

      final updateData = {
        'full_name': fullName,
        'bio': _bio.text.trim().isEmpty ? null : _bio.text.trim(),

        // keep old + new fields (so nothing breaks)
        'account_type': _accountType,
        'profile_type': _accountType, // person|business|org
        'org_kind': _accountType == 'org' ? _orgKind : null,

        'radius_km': _radiusKm,

        'zipcode': zip,
        'latitude': _lat,
        'longitude': _lng,
      };

      await Supabase.instance.client.from('profiles').upsert({
        'id': user.id,
        ...updateData,
      });

      if (mounted) context.go('/feed');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Complete Profile')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            DropdownButtonFormField<String>(
              value: _accountType,
              items: const [
                DropdownMenuItem(value: 'person', child: Text('Person')),
                DropdownMenuItem(value: 'business', child: Text('Business')),
                DropdownMenuItem(value: 'org', child: Text('Organization')),
              ],
              onChanged: (v) {
                setState(() {
                  _accountType = v ?? 'person';
                  if (_accountType != 'org') _orgKind = null;
                });
              },
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Account type',
              ),
            ),
            const SizedBox(height: 12),

            if (_accountType == 'org') ...[
              DropdownButtonFormField<String>(
                value: _orgKind,
                items: const [
                  DropdownMenuItem(
                      value: 'government', child: Text('Government')),
                  DropdownMenuItem(value: 'nonprofit', child: Text('Non-profit')),
                ],
                onChanged: (v) => setState(() => _orgKind = v),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Organization type',
                ),
              ),
              const SizedBox(height: 12),
            ],

            TextField(
              controller: _name,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Name',
              ),
            ),
            const SizedBox(height: 12),

            TextField(
              controller: _bio,
              maxLines: 3,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Bio (optional)',
              ),
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _zipCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Postal Code',
                      hintText: 'e.g. 91000',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: _loading ? null : _setFromZipcode,
                  child: const Text('Set'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_lat != null && _lng != null)
              Text(
                'Lat/Lng: ${_lat!.toStringAsFixed(5)}, ${_lng!.toStringAsFixed(5)}',
              ),

            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              value: _radiusKm,
              items: const [
                DropdownMenuItem(value: 5, child: Text('5 km')),
                DropdownMenuItem(value: 10, child: Text('10 km')),
                DropdownMenuItem(value: 20, child: Text('20 km')),
              ],
              onChanged: (v) => setState(() => _radiusKm = v ?? 5),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Feed radius',
              ),
            ),

            const SizedBox(height: 16),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.red),
                ),
              ),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading ? null : _save,
                child: Text(_loading ? 'Saving...' : 'Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
