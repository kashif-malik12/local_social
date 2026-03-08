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
import '../services/mention_service.dart';
import '../services/post_service.dart';
import '../widgets/global_bottom_nav.dart';
import '../widgets/mention_picker_sheet.dart';

enum _ComposerMediaMode { none, photos, videoFile, youtube }

class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({super.key});

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  static const int _maxPhotoCount = 2;
  static const int _maxPhotoBytes = 4 * 1024 * 1024;
  static const int _maxVideoBytes = 20 * 1024 * 1024;

  final _contentCtrl = TextEditingController();
  final _videoUrlCtrl = TextEditingController();
  final _marketTitleCtrl = TextEditingController();
  final _marketPriceCtrl = TextEditingController();

  final _picker = ImagePicker();
  final _mentionService = MentionService(Supabase.instance.client);

  String _visibility = 'public';
  PostType _selectedPostType = PostType.post;
  String _selectedMarketCategory = marketMainCategories.first;
  String _selectedMarketIntent = 'selling';
  String _selectedServiceCategory = serviceMainCategories.first;
  String _selectedFoodCategory = foodMainCategories.first;
  String _shareScope = 'none';
  bool _isRestaurantAuthor = false;
  bool _loading = false;

  _ComposerMediaMode _mediaMode = _ComposerMediaMode.none;
  List<XFile> _selectedImages = const [];
  XFile? _selectedVideo;
  List<MentionCandidate> _selectedMentions = const [];

  bool get _isMarketPost => _selectedPostType == PostType.market;
  bool get _isServicePost =>
      _selectedPostType == PostType.serviceOffer ||
      _selectedPostType == PostType.serviceRequest;
  bool get _isFoodAdPost => _selectedPostType == PostType.foodAd;
  bool get _supportsVideoModes => !_isMarketPost && !_isServicePost && !_isFoodAdPost;

  @override
  void initState() {
    super.initState();
    _loadRestaurantFlag();
  }

  @override
  void dispose() {
    _contentCtrl.dispose();
    _videoUrlCtrl.dispose();
    _marketTitleCtrl.dispose();
    _marketPriceCtrl.dispose();
    super.dispose();
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

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _formatMb(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(0);

  bool _isValidYoutubeUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    final host = uri.host.toLowerCase();
    return host.contains('youtube.com') || host.contains('youtu.be');
  }

  Future<int> _fileLength(XFile file) => file.length();

  void _setMediaMode(_ComposerMediaMode mode) {
    setState(() {
      _mediaMode = mode;
      if (mode != _ComposerMediaMode.photos) {
        _selectedImages = const [];
      }
      if (mode != _ComposerMediaMode.videoFile) {
        _selectedVideo = null;
      }
      if (mode != _ComposerMediaMode.youtube) {
        _videoUrlCtrl.clear();
      }
    });
  }

  void _onPostTypeChanged(PostType value) {
    setState(() {
      _selectedPostType = value;
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
      if (!_supportsVideoModes &&
          (_mediaMode == _ComposerMediaMode.videoFile || _mediaMode == _ComposerMediaMode.youtube)) {
        _mediaMode = _ComposerMediaMode.none;
        _selectedVideo = null;
        _videoUrlCtrl.clear();
      }
    });
  }

  Future<void> _pickPhotos() async {
    final files = await _picker.pickMultiImage(imageQuality: 85);
    if (files.isEmpty) return;

    final chosen = files.take(_maxPhotoCount).toList();
    for (final file in chosen) {
      final size = await _fileLength(file);
      if (size > _maxPhotoBytes) {
        if (!mounted) return;
        _showError('Size limit exceeded. Each photo must be under ${_formatMb(_maxPhotoBytes)} MB.');
        return;
      }
    }

    if (!mounted) return;
    setState(() {
      _mediaMode = _ComposerMediaMode.photos;
      _selectedImages = chosen;
      _selectedVideo = null;
      _videoUrlCtrl.clear();
    });

    if (files.length > _maxPhotoCount && mounted) {
      _showError('Only $_maxPhotoCount photos can be attached to one post.');
    }
  }

  Future<void> _pickVideoFile() async {
    final file = await _picker.pickVideo(source: ImageSource.gallery);
    if (file == null) return;

    final size = await _fileLength(file);
    if (size > _maxVideoBytes) {
      if (!mounted) return;
      _showError('Size limit exceeded. Video must be under ${_formatMb(_maxVideoBytes)} MB.');
      return;
    }

    if (!mounted) return;
    setState(() {
      _mediaMode = _ComposerMediaMode.videoFile;
      _selectedVideo = file;
      _selectedImages = const [];
      _videoUrlCtrl.clear();
    });
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

  Future<void> _pickMentions() async {
    try {
      final connections = await _mentionService.fetchMutualConnections();
      if (!mounted) return;
      if (connections.isEmpty) {
        _showError('No mutual connections available to tag');
        return;
      }

      final selected = await showMentionPickerSheet(
        context: context,
        available: connections,
        initialSelection: _selectedMentions,
        title: 'Tag connections',
      );

      if (selected != null && mounted) {
        setState(() => _selectedMentions = selected);
      }
    } catch (e) {
      if (!mounted) return;
      _showError('Tag loading failed: $e');
    }
  }

  Future<void> _submit() async {
    final rawContent = _contentCtrl.text.trim();
    final marketTitle = _marketTitleCtrl.text.trim();
    final marketPriceRaw = _marketPriceCtrl.text.trim();

    if (rawContent.isEmpty) {
      _showError('Write something');
      return;
    }

    if (_isMarketPost && _selectedMarketCategory.isEmpty) {
      _showError('Please select a product category');
      return;
    }

    if (_isServicePost && _selectedServiceCategory.isEmpty) {
      _showError('Please select a service category');
      return;
    }

    if (_isFoodAdPost && marketTitle.isEmpty) {
      _showError('Please enter food name');
      return;
    }

    double? marketPrice;
    if (_isFoodAdPost || _isMarketPost || (_isServicePost && marketPriceRaw.isNotEmpty)) {
      marketPrice = double.tryParse(marketPriceRaw);
      if (marketPrice == null || marketPrice < 0) {
        _showError('Please enter a valid price');
        return;
      }
    }

    if (_isFoodAdPost && marketPriceRaw.isEmpty) {
      _showError('Please enter food price');
      return;
    }

    if (_isFoodAdPost && _selectedFoodCategory.isEmpty) {
      _showError('Please select a food category');
      return;
    }

    String? videoUrl;
    if (_mediaMode == _ComposerMediaMode.youtube) {
      final rawUrl = _videoUrlCtrl.text.trim();
      if (rawUrl.isEmpty || !_isValidYoutubeUrl(rawUrl)) {
        _showError('Please paste a valid YouTube link (youtube.com / youtu.be)');
        return;
      }
      videoUrl = rawUrl;
    }

    setState(() => _loading = true);
    try {
      final supabase = Supabase.instance.client;
      final service = PostService(supabase);
      final allowedTagIds =
          await _mentionService.filterAllowedUserIds(_selectedMentions.map((e) => e.id).toList());
      final content = _mentionService.composeTaggedContent(rawContent, _selectedMentions);

      final profile = await _loadProfileLocation(supabase);
      final city = profile?['city'] as String?;
      final lat = profile?['latitude'] as num?;
      final lng = profile?['longitude'] as num?;

      if (lat == null || lng == null) {
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
      String? secondImageUrl;
      if (_mediaMode == _ComposerMediaMode.photos && _selectedImages.isNotEmpty) {
        imageUrl = await service.uploadPostImage(
          image: _selectedImages.first,
          userId: supabase.auth.currentUser!.id,
        );
        if (_selectedImages.length > 1) {
          secondImageUrl = await service.uploadPostImage(
            image: _selectedImages[1],
            userId: supabase.auth.currentUser!.id,
          );
        }
      }

      if (_mediaMode == _ComposerMediaMode.videoFile && _selectedVideo != null) {
        videoUrl = await service.uploadPostVideo(
          video: _selectedVideo!,
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
        secondImageUrl: secondImageUrl,
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
        shareScope: _shareScope,
        taggedUserIds: allowedTagIds,
      );

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      _showError('Error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _buildPhotoPreview(XFile file) {
    final imageProvider = kIsWeb
        ? NetworkImage(file.path)
        : FileImage(File(file.path)) as ImageProvider;
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image(
            image: imageProvider,
            width: double.infinity,
            height: 180,
            fit: BoxFit.cover,
          ),
        ),
      ],
    );
  }

  Widget _mediaModeTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required _ComposerMediaMode mode,
    required bool enabled,
  }) {
    final selected = _mediaMode == mode;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: InkWell(
        onTap: !enabled || _loading ? null : () => _setMediaMode(mode),
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFF4EBDD) : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? const Color(0xFF0F766E) : const Color(0xFFE6DDCE),
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, color: selected ? const Color(0xFF0F766E) : null),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              Radio<_ComposerMediaMode>(
                value: mode,
                groupValue: _mediaMode,
                onChanged: enabled && !_loading ? (value) => _setMediaMode(value!) : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMediaSection() {
    final photoSubtitle = 'Up to 2 photos, ${_formatMb(_maxPhotoBytes)} MB each';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Media',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        _mediaModeTile(
          title: 'No media',
          subtitle: 'Text only',
          icon: Icons.notes_outlined,
          mode: _ComposerMediaMode.none,
          enabled: true,
        ),
        const SizedBox(height: 8),
        _mediaModeTile(
          title: 'Photos',
          subtitle: photoSubtitle,
          icon: Icons.photo_library_outlined,
          mode: _ComposerMediaMode.photos,
          enabled: true,
        ),
        if (_supportsVideoModes) ...[
          const SizedBox(height: 8),
          _mediaModeTile(
            title: 'Video file',
            subtitle: '1 video, ${_formatMb(_maxVideoBytes)} MB max',
            icon: Icons.video_library_outlined,
            mode: _ComposerMediaMode.videoFile,
            enabled: true,
          ),
          const SizedBox(height: 8),
          _mediaModeTile(
            title: 'YouTube link',
            subtitle: '1 YouTube URL only',
            icon: Icons.smart_display_outlined,
            mode: _ComposerMediaMode.youtube,
            enabled: true,
          ),
        ],
        const SizedBox(height: 12),
        if (_mediaMode == _ComposerMediaMode.photos) ...[
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _selectedImages
                .asMap()
                .entries
                .map(
                  (entry) => Stack(
                    children: [
                      SizedBox(
                        width: 150,
                        child: _buildPhotoPreview(entry.value),
                      ),
                      Positioned(
                        right: 6,
                        top: 6,
                        child: CircleAvatar(
                          radius: 14,
                          backgroundColor: Colors.black54,
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            iconSize: 14,
                            onPressed: () {
                              setState(() {
                                final updated = [..._selectedImages]..removeAt(entry.key);
                                _selectedImages = updated;
                                if (updated.isEmpty) {
                                  _mediaMode = _ComposerMediaMode.none;
                                }
                              });
                            },
                            icon: const Icon(Icons.close, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _loading ? null : _pickPhotos,
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: Text(_selectedImages.isEmpty ? 'Choose photos' : 'Replace photos'),
          ),
        ],
        if (_mediaMode == _ComposerMediaMode.videoFile) ...[
          if (_selectedVideo != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE6DDCE)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.videocam_outlined),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _selectedVideo!.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    onPressed: () => setState(() {
                      _selectedVideo = null;
                      _mediaMode = _ComposerMediaMode.none;
                    }),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _loading ? null : _pickVideoFile,
            icon: const Icon(Icons.video_library_outlined),
            label: Text(_selectedVideo == null ? 'Choose video' : 'Replace video'),
          ),
        ],
        if (_mediaMode == _ComposerMediaMode.youtube) ...[
          TextField(
            controller: _videoUrlCtrl,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'YouTube video URL',
              hintText: 'https://youtube.com/watch?v=...',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Post')),
      bottomNavigationBar: const GlobalBottomNav(),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Card(
              child: ListView(
                padding: const EdgeInsets.all(18),
                children: [
                  TextField(
                    controller: _contentCtrl,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'What is happening?',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: _loading ? null : _pickMentions,
                        icon: const Icon(Icons.alternate_email),
                        label: const Text('Tag connections'),
                      ),
                      if (_selectedMentions.isNotEmpty) ...[
                        const SizedBox(width: 10),
                        Text(
                          '${_selectedMentions.length} selected',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                  if (_selectedMentions.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _selectedMentions
                          .map(
                            (mention) => InputChip(
                              label: Text(mention.name),
                              backgroundColor: const Color(0xFFF4EBDD),
                              side: const BorderSide(color: Color(0xFFD8C8AF)),
                              labelStyle: const TextStyle(
                                color: Color(0xFF12211D),
                                fontWeight: FontWeight.w700,
                              ),
                              deleteIconColor: const Color(0xFF7A5C2E),
                              onDeleted: () {
                                setState(() {
                                  _selectedMentions = _selectedMentions
                                      .where((item) => item.id != mention.id)
                                      .toList();
                                });
                              },
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 12),
                  ],
                  DropdownButtonFormField<PostType>(
                    initialValue: _selectedPostType,
                    items: PostType.values
                        .where((t) => _isRestaurantAuthor || t != PostType.foodAd)
                        .map((t) => DropdownMenuItem(value: t, child: Text(t.label)))
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      _onPostTypeChanged(v);
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
                        hintText: _isFoodAdPost
                            ? 'e.g. 12.99'
                            : (_isServicePost ? 'e.g. 50' : 'e.g. 1200'),
                        prefixText: 'EUR ',
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
                          .map((c) => DropdownMenuItem(value: c, child: Text(marketCategoryLabel(c))))
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
                          .map((c) => DropdownMenuItem(value: c, child: Text(serviceCategoryLabel(c))))
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
                          .map((c) => DropdownMenuItem(value: c, child: Text(foodCategoryLabel(c))))
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
                  _buildMediaSection(),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _visibility,
                    items: const [
                      DropdownMenuItem(value: 'public', child: Text('Public')),
                      DropdownMenuItem(value: 'followers', child: Text('Local')),
                    ],
                    onChanged: (v) => setState(() => _visibility = v ?? 'public'),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Visibility',
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _shareScope,
                    items: const [
                      DropdownMenuItem(value: 'none', child: Text('No sharing')),
                      DropdownMenuItem(value: 'followers', child: Text('Followers can share')),
                      DropdownMenuItem(value: 'connections', child: Text('Connections can share')),
                      DropdownMenuItem(value: 'public', child: Text('Public can share')),
                    ],
                    onChanged: (v) => setState(() => _shareScope = v ?? 'none'),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Allow sharing',
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _loading ? null : _submit,
                    child: _loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Post'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
