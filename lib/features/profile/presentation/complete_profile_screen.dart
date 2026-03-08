import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/business_categories.dart';
import '../../../core/restaurant_categories.dart';
import '../../../services/profile_service.dart';
import '../../../widgets/global_app_bar.dart'; // ✅ NEW
import '../../../widgets/global_bottom_nav.dart';

class CompleteProfileScreen extends StatefulWidget {
  const CompleteProfileScreen({super.key});

  @override
  State<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends State<CompleteProfileScreen> {
  final _name = TextEditingController();
  final _bio = TextEditingController();

  final _zipCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  double? _lat;
  double? _lng;
  String? _savedZip;
  bool _zipLocked = false;

  String _accountType = 'person'; // person | business | org
  String? _orgKind; // government | nonprofit | news_agency (only when org)
  bool _isRestaurant = false;
  String? _restaurantType;
  String? _businessType;
  int _radiusKm = 5;

  // ✅ Avatar
  final _picker = ImagePicker();
  String? _avatarUrl;
  bool _uploadingAvatar = false;

  bool _loading = false;
  String? _error;

  bool get _isZipLocked => _zipLocked;

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
    _cityCtrl.dispose();
    super.dispose();
  }

  Future<String?> _resolveCityFromZipcode(String zip) async {
    if (!RegExp(r'^\d{5}$').hasMatch(zip)) return null;

    if (kIsWeb) {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/search?format=json&addressdetails=1&country=France&postalcode=$zip&limit=1',
      );

      final res = await http.get(uri, headers: {
        'User-Agent': 'local-social-app/1.0',
      });

      if (res.statusCode != 200) return null;

      final data = jsonDecode(res.body);
      if (data is! List || data.isEmpty) return null;

      return (data[0]['address']?['city'] ??
              data[0]['address']?['town'] ??
              data[0]['address']?['village'] ??
              data[0]['display_name']?.toString().split(',').first)
          ?.toString()
          .trim();
    }

    final results = await locationFromAddress('$zip, France');
    if (results.isEmpty) return null;

    final placemarks = await placemarkFromCoordinates(
      results.first.latitude,
      results.first.longitude,
    );
    if (placemarks.isEmpty) return null;

    return (placemarks.first.locality?.trim().isNotEmpty == true
            ? placemarks.first.locality
            : placemarks.first.subAdministrativeArea)
        ?.trim();
  }

  Future<void> _backfillCityIfMissing({
    required String userId,
    required String zip,
  }) async {
    final resolved = await _resolveCityFromZipcode(zip);
    if (resolved == null || resolved.isEmpty) return;

    await Supabase.instance.client
        .from('profiles')
        .update({'city': resolved})
        .eq('id', userId);

    if (!mounted) return;
    setState(() => _cityCtrl.text = resolved);
  }

  Future<void> _loadProfile() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

       Map<String, dynamic>? data;
      try {
        data = await Supabase.instance.client
            .from('profiles')
            .select(
             'full_name, bio, zipcode, city, latitude, longitude, profile_type, account_type, org_kind, radius_km, avatar_url, is_restaurant, restaurant_type, business_type',
            )
            .eq('id', user.id)
            .maybeSingle();
      } on PostgrestException {
        data = await Supabase.instance.client
            .from('profiles')
            .select(
              'full_name, bio, zipcode, city, latitude, longitude, profile_type, account_type, org_kind, radius_km, avatar_url',
            )
            .eq('id', user.id)
            .maybeSingle();
      }

      if (data == null || !mounted) return;

      setState(() {
        _name.text = (data?['full_name'] as String?) ?? '';
        _bio.text = (data?['bio'] as String?) ?? '';
        _zipCtrl.text = (data?['zipcode'] as String?) ?? '';
        _cityCtrl.text = (data?['city'] as String?) ?? '';
        _savedZip = (data?['zipcode'] as String?)?.trim();
        _zipLocked = _savedZip != null && RegExp(r'^\d{5}$').hasMatch(_savedZip!);

        _avatarUrl = (data?['avatar_url'] as String?);

        _lat = (data?['latitude'] as num?)?.toDouble();
        _lng = (data?['longitude'] as num?)?.toDouble();

        _accountType = (data?['profile_type'] as String?) ??
            (data?['account_type'] as String?) ??
            'person';

        _orgKind = data?['org_kind'] as String?;
        _isRestaurant = data?['is_restaurant'] == true;
        _restaurantType = data?['restaurant_type'] as String?;
        _businessType = data?['business_type'] as String?;
        _radiusKm = (data?['radius_km'] as int?) ?? 5;
      });

      final zip = (data['zipcode'] as String?)?.trim() ?? '';
      final city = (data['city'] as String?)?.trim() ?? '';
      if (city.isEmpty && zip.isNotEmpty) {
        await _backfillCityIfMissing(userId: user.id, zip: zip);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Failed to load profile: $e');
    }
  }

  Future<void> _pickAndUploadAvatar() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      final image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 75,
      );
      if (image == null) return;

      if (!mounted) return;
      setState(() {
        _uploadingAvatar = true;
        _error = null;
      });

      final svc = ProfileService(Supabase.instance.client);
      final url = await svc.uploadAvatar(image: image, userId: user.id);
      await svc.updateAvatarUrl(userId: user.id, avatarUrl: url);

      if (!mounted) return;
      setState(() => _avatarUrl = url);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Avatar updated ✅')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Avatar upload failed: $e');
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  Future<void> _setFromZipcode() async {
    // ✅ Block changes once zip is set
    if (_isZipLocked) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Postal code is locked after first set.')),
      );
      return;
    }

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
      String? city;

      if (kIsWeb) {
        final uri = Uri.parse(
          'https://nominatim.openstreetmap.org/search?format=json&addressdetails=1&country=France&postalcode=$zip&limit=1',
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
        city = await _resolveCityFromZipcode(zip);

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
        city = await _resolveCityFromZipcode(zip);
      }

      if (!mounted) return;

      setState(() {
        _lat = lat;
        _lng = lng;
        if (city != null && city.trim().isNotEmpty) {
          _cityCtrl.text = city.trim();
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _cityCtrl.text.trim().isNotEmpty
                ? 'Location set for $zip • ${_cityCtrl.text.trim()}'
                : 'Location set for $zip. Add your city manually if needed.',
          ),
        ),
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
      final city = _cityCtrl.text.trim();
      if (!_isZipLocked) {
        if (!RegExp(r'^\d{5}$').hasMatch(zip)) {
          throw 'Enter a valid 5-digit French postal code (e.g. 91000)';
        }
        if (_lat == null || _lng == null) {
          throw 'Please set your location (zip code) first';
        }
      }
      if (city.isEmpty) {
        throw 'City is required';
      }

      if (_accountType == 'org' && _orgKind == null) {
        throw 'Please select Government, Non-profit, or News agency';
      }

      if (_accountType == 'business') {
        if (_isRestaurant && _restaurantType == null) {
          throw 'Please select restaurant type';
        }
        if (!_isRestaurant && _businessType == null) {
          throw 'Please select business type';
        }
      }
      
      final updateData = <String, dynamic>{
        'full_name': fullName,
        'bio': _bio.text.trim().isEmpty ? null : _bio.text.trim(),

        'account_type': _accountType,
        'profile_type': _accountType,
        'org_kind': _accountType == 'org' ? _orgKind : null,
        'is_restaurant': _accountType == 'business' ? _isRestaurant : false,
        'restaurant_type': (_accountType == 'business' && _isRestaurant) ? _restaurantType : null,
        'business_type': (_accountType == 'business' && !_isRestaurant) ? _businessType : null,
        
        'radius_km': _radiusKm,
        'city': city,

        // ✅ keep avatar
        'avatar_url': _avatarUrl,
      };

      if (_isZipLocked) {
        updateData['zipcode'] = _savedZip;
      } else {
        updateData.addAll({
          'zipcode': zip,
          'latitude': _lat,
          'longitude': _lng,
        });
      }

      try {
        await Supabase.instance.client.from('profiles').upsert({
          'id': user.id,
          ...updateData,
        });
      } on PostgrestException catch (e) {
        final msg = (e.message).toLowerCase();
        if (!msg.contains('is_restaurant') &&
            !msg.contains('restaurant_type') &&
            !msg.contains('business_type')) {
          rethrow;
        }

        final fallback = Map<String, dynamic>.from(updateData)
          ..remove('is_restaurant')
          ..remove('restaurant_type')
           ..remove('business_type');

        await Supabase.instance.client.from('profiles').upsert({
          'id': user.id,
          ...fallback,
        });
      }

      if (!mounted) return;
      setState(() {
        _savedZip = zip;
        _zipLocked = RegExp(r'^\d{5}$').hasMatch(zip);
      });
      context.go('/feed');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final zipLocked = _isZipLocked;

    return Scaffold(
      // ✅ Global sticky app bar (title clickable -> /feed)
      appBar: const GlobalAppBar(
        title: 'Local Feed ✅',
        showBackIfPossible: true,
        homeRoute: '/feed',
      ),

      bottomNavigationBar: const GlobalBottomNav(),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
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
                    'Edit profile',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Update your identity, categories, location, and feed settings in one place.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFFE6DDCE)),
              ),
              child: Column(
                children: [
            Center(
              child: Column(
                children: [
                  GestureDetector(
                    onTap: _uploadingAvatar ? null : _pickAndUploadAvatar,
                    child: Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        CircleAvatar(
                          radius: 46,
                          backgroundImage:
                              (_avatarUrl != null && _avatarUrl!.isNotEmpty)
                                  ? NetworkImage(_avatarUrl!)
                                  : null,
                          child: (_avatarUrl == null || _avatarUrl!.isEmpty)
                              ? const Icon(Icons.person, size: 46)
                              : null,
                        ),
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Theme.of(context).colorScheme.surface,
                            border: Border.all(
                              color: Theme.of(context).dividerColor,
                            ),
                          ),
                          child: _uploadingAvatar
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.camera_alt, size: 16),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Tap to change avatar',
                    style: TextStyle(
                      color: Theme.of(context).hintColor,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),

            DropdownButtonFormField<String>(
              initialValue: _accountType,
              items: const [
                DropdownMenuItem(value: 'person', child: Text('Person')),
                DropdownMenuItem(value: 'business', child: Text('Business')),
                DropdownMenuItem(value: 'org', child: Text('Organization')),
              ],
              onChanged: (v) {
                setState(() {
                  _accountType = v ?? 'person';
                  if (_accountType != 'org') _orgKind = null;
                  if (_accountType != 'business') {
                    _isRestaurant = false;
                    _restaurantType = null;
                    _businessType = null;
                  }
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
                initialValue: _orgKind,
                items: const [
                  DropdownMenuItem(value: 'government', child: Text('Government')),
                  DropdownMenuItem(value: 'nonprofit', child: Text('Non-profit')),
                  DropdownMenuItem(value: 'news_agency', child: Text('News agency')),
                ],
                onChanged: (v) => setState(() => _orgKind = v),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Organization type',
                ),
              ),
              const SizedBox(height: 12),
            ],

            if (_accountType == 'business') ...[
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _isRestaurant,
                onChanged: (v) {
                  setState(() {
                    _isRestaurant = v ?? false;
                    if (_isRestaurant) {
                      _businessType = null;
                    } else {
                      _restaurantType = null;
                    }
                  });
                },
                title: const Text('Are you a restaurant?'),
                secondary: Icon(
                  _isRestaurant ? Icons.verified : Icons.verified_outlined,
                  color: _isRestaurant ? Colors.green : null,
                ),
              ),
              const SizedBox(height: 8),
              if (_isRestaurant) ...[
                DropdownButtonFormField<String>(
                  initialValue: _restaurantType,
                  items: restaurantMainCategories
                      .map((c) => DropdownMenuItem(
                            value: c,
                            child: Text(restaurantCategoryLabel(c)),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _restaurantType = v),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Restaurant category',
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (!_isRestaurant) ...[
                DropdownButtonFormField<String>(
                  initialValue: _businessType,
                  items: businessMainCategories
                      .map((c) => DropdownMenuItem(
                            value: c,
                            child: Text(businessCategoryLabel(c)),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _businessType = v),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Business category',
                  ),
                ),
                const SizedBox(height: 12),
              ],
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
                    enabled: !zipLocked,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      labelText: 'Postal Code',
                      hintText: 'e.g. 91000',
                      helperText: zipLocked ? 'Locked after first set' : null,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: (_loading || zipLocked) ? null : _setFromZipcode,
                  child: Text(zipLocked ? 'Set ✅' : 'Set'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _cityCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'City',
                hintText: 'Auto-filled from postal code, or enter manually',
              ),
            ),
            const SizedBox(height: 8),
            if (_lat != null && _lng != null)
              Text(
                _cityCtrl.text.trim().isNotEmpty
                    ? 'City: ${_cityCtrl.text.trim()} • Lat/Lng: ${_lat!.toStringAsFixed(5)}, ${_lng!.toStringAsFixed(5)}'
                    : 'Lat/Lng: ${_lat!.toStringAsFixed(5)}, ${_lng!.toStringAsFixed(5)}',
              ),

            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _radiusKm,
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
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
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
          ],
        ),
      ),
      ),
    );
  }
}
