import 'dart:io' show File;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/food_categories.dart';
import '../core/market_categories.dart';
import '../core/post_types.dart';
import '../core/service_categories.dart';
import '../services/post_service.dart';

class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({super.key});

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final _contentCtrl = TextEditingController();
  final _videoUrlCtrl = TextEditingController();
  final _marketTitleCtrl = TextEditingController();
  final _marketPriceCtrl = TextEditingController();

  String _visibility = 'public';
  PostType _selectedPostType = PostType.post;
  String _selectedMarketCategory = marketMainCategories.first;
  String _selectedMarketIntent = 'selling';
  String _selectedServiceCategory = serviceMainCategories.first;
  String _selectedFoodCategory = foodMainCategories.first;
  bool _isRestaurantAuthor = false;

  XFile? _imageXFile;
  bool _loading = false;

  final _picker = ImagePicker();

  bool get _isMarketPost => _selectedPostType == PostType.market;
  bool get _isServicePost =>
      _selectedPostType == PostType.serviceOffer ||
      _selectedPostType == PostType.serviceRequest;
  bool get _isFoodAdPost => _selectedPostType == PostType.foodAd;

  @override
  void initState() {
    super.initState();
    _loadRestaurantFlag();
  }

  Future<void> _loadRestaurantFlag() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      final row = await Supabase.instance.client
          .from('profiles')
          .select('is_restaurant')
          .eq('id', user.id)
          .maybeSingle();
      if (!mounted) return;
      setState(() => _isRestaurantAuthor = row?['is_restaurant'] == true);
    } on PostgrestException {
      if (!mounted) return;
      setState(() => _isRestaurantAuthor = false);
    }
  }
  
  @override
  void dispose() {
    _contentCtrl.dispose();
    _videoUrlCtrl.dispose();
    _marketTitleCtrl.dispose();
    _marketPriceCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final x = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (x == null) return;
    setState(() => _imageXFile = x);
  }

  Future<Map<String, dynamic>?> _loadProfileLocation(SupabaseClient supabase) async {
    final user = supabase.auth.currentUser;
    if (user == null) return null;

    return supabase
        .from('profiles')
        .select('city, latitude, longitude')
        .eq('id', user.id)
        .maybeSingle();
  }

  bool _isValidYoutubeUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;

    final host = uri.host.toLowerCase();
    return host.contains('youtube.com') || host.contains('youtu.be');
  }

  Future<void> _submit() async {
    final content = _contentCtrl.text.trim();
    if (content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Write something')),
      );
      return;
    }

    final videoUrlRaw = _videoUrlCtrl.text.trim();
    final videoUrl = videoUrlRaw.isEmpty ? null : videoUrlRaw;
    final marketTitle = _marketTitleCtrl.text.trim();
    final marketPriceRaw = _marketPriceCtrl.text.trim();
    
    if (_isMarketPost && _selectedMarketCategory.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a product category')),
      );
      return;
    }

    if (_isServicePost && _selectedServiceCategory.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a service category')),
      );
      return;
    }

    if (_isFoodAdPost && marketTitle.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter food name')),
      );
      return;
    }

    double? marketPrice;
    if (_isFoodAdPost || _isMarketPost || (_isServicePost && marketPriceRaw.isNotEmpty)) {
      marketPrice = double.tryParse(marketPriceRaw);
      if (marketPrice == null || marketPrice < 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a valid price')),
        );
        return;
      }
    }

    if (_isFoodAdPost && marketPriceRaw.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter food price')),
      );
      return;
    }

    if (_isFoodAdPost && _selectedFoodCategory.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a food category')),
      );
      return;
    }
    
    if (videoUrl != null && !_isValidYoutubeUrl(videoUrl)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please paste a valid YouTube link (youtube.com / youtu.be)'),
        ),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final supabase = Supabase.instance.client;
      final service = PostService(supabase);

      final profile = await _loadProfileLocation(supabase);
      final city = profile?['city'] as String?;
      final lat = profile?['latitude'] as num?;
      final lng = profile?['longitude'] as num?;

      final hasLocation = lat != null && lng != null;
      if (!hasLocation) {
        if (!mounted) return;

        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Location required'),
            content: const Text(
              'To post in the local feed, please set your location in your profile.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  context.go('/complete-profile');
                },
                child: const Text('Complete Profile'),
              ),
            ],
          ),
        );

        return;
      }

      String? imageUrl;
      if (_imageXFile != null) {
        imageUrl = await service.uploadPostImage(
          image: _imageXFile!,
          userId: supabase.auth.currentUser!.id,
        );
      }

      await service.createPost(
        content: content,
        visibility: _visibility,
        latitude: lat.toDouble(),
        longitude: lng.toDouble(),
        locationName: city,
        imageUrl: imageUrl,
        videoUrl: videoUrl,
        postType: _selectedPostType.dbValue,
        marketCategory: _isMarketPost
            ? _selectedMarketCategory
            : (_isServicePost 
                ? _selectedServiceCategory
                : (_isFoodAdPost ? _selectedFoodCategory : null)),
        marketIntent: _isMarketPost ? _selectedMarketIntent : null,
        marketTitle: (_isMarketPost || _isServicePost || _isFoodAdPost) ? marketTitle : null,
        marketPrice: (_isMarketPost || _isServicePost || _isFoodAdPost) ? marketPrice : null,
      );

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Post')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            TextField(
              controller: _contentCtrl,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'What’s happening?',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<PostType>(
              initialValue: _selectedPostType,
              items: PostType.values
                  .where((t) => _isRestaurantAuthor || t != PostType.foodAd)
                  .map((t) => DropdownMenuItem(value: t, child: Text(t.label)))
                  .toList(),
              onChanged: (v) {
                setState(() {
                  _selectedPostType = v ?? PostType.post;
                  if (!_isMarketPost) {
                    _selectedMarketCategory = marketMainCategories.first;
                    _selectedMarketIntent = 'selling';
                  }
                  if (!_isServicePost) {
                    _selectedServiceCategory = serviceMainCategories.first;
                  }
                  if (!_isFoodAdPost) {
                    _selectedFoodCategory = foodMainCategories.first;
                  }
                });
              },
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Post category',
              ),
            ),
            const SizedBox(height: 12),
             if (_isMarketPost || _isServicePost || _isFoodAdPost) ...[
              TextField(
                controller: _marketTitleCtrl,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: _isFoodAdPost
                      ? 'Food name'
                      : (_isServicePost ? 'Service title' : 'Product title'),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _marketPriceCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: _isFoodAdPost
                      ? 'Food price'
                      : (_isServicePost ? 'Rate/Budget (optional)' : 'Price (optional)'),
                  hintText: _isFoodAdPost ? 'e.g. 12.99' : (_isServicePost ? 'e.g. 50' : 'e.g. 1200'),
                  prefixText: '€ ',
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (_isMarketPost) ...[
              DropdownButtonFormField<String>(
                initialValue: _selectedMarketIntent,
                items: const [
                  DropdownMenuItem(value: 'selling', child: Text('Selling')),
                  DropdownMenuItem(value: 'buying', child: Text('Buying')),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _selectedMarketIntent = v);
                },
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Marketplace type',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _selectedMarketCategory,
                items: marketMainCategories
                    .map(
                      (c) => DropdownMenuItem(
                        value: c,
                        child: Text(marketCategoryLabel(c)),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _selectedMarketCategory = v);
                },
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Product category',
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (_isServicePost) ...[
              DropdownButtonFormField<String>(
                initialValue: _selectedServiceCategory,
                items: serviceMainCategories
                    .map(
                      (c) => DropdownMenuItem(
                        value: c,
                        child: Text(serviceCategoryLabel(c)),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _selectedServiceCategory = v);
                },
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Service category',
                ),
              ),
              const SizedBox(height: 12),
            ],

             if (_isFoodAdPost) ...[
              DropdownButtonFormField<String>(
                initialValue: _selectedFoodCategory,
                items: foodMainCategories
                    .map(
                      (c) => DropdownMenuItem(
                        value: c,
                        child: Text(foodCategoryLabel(c)),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _selectedFoodCategory = v);
                },
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Food category',
                ),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _videoUrlCtrl,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'YouTube video URL (optional)',
                hintText: 'https://youtube.com/watch?v=...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _visibility,
              items: const [
                DropdownMenuItem(value: 'public', child: Text('Public')),
                DropdownMenuItem(value: 'local', child: Text('Local')),
              ],
              onChanged: (v) => setState(() => _visibility = v ?? 'public'),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Visibility',
              ),
            ),
            const SizedBox(height: 12),
            if (_imageXFile != null) ...[
              Container(
                height: 200,
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  image: DecorationImage(
                    image: kIsWeb
                        ? NetworkImage(_imageXFile!.path)
                        : FileImage(File(_imageXFile!.path)) as ImageProvider,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            ElevatedButton.icon(
              onPressed: _pickImage,
              icon: const Icon(Icons.image),
              label: const Text('Add Photo'),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _loading ? null : _submit,
              child: _loading
                  ? const CircularProgressIndicator()
                  : const Text('Post'),
            ),
          ],
        ),
      ),
    );
  }
}