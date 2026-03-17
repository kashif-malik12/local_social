import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/food_categories.dart';
import '../core/localization/app_localizations.dart';
import '../core/market_categories.dart';
import '../core/platform/local_image_provider.dart';
import '../core/platform/platform_info.dart';
import '../core/post_types.dart';
import '../core/service_categories.dart';
import '../services/media_compression_service.dart';
import '../services/media_limits.dart';
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
  static const int _maxPhotoBytes = MediaLimits.maxPhotoBytes;
  static const MethodChannel _cameraChannel = MethodChannel('com.local_social/camera');

  final _contentCtrl = TextEditingController();
  final _videoUrlCtrl = TextEditingController();
  final _marketTitleCtrl = TextEditingController();
  final _marketPriceCtrl = TextEditingController();

  final _mentionService = MentionService(Supabase.instance.client);

  String _visibility = 'public';
  PostType _selectedPostType = PostType.post;
  String _selectedMarketCategory = marketMainCategories.first;
  String _selectedMarketIntent = 'selling';
  String _selectedServiceCategory = serviceMainCategories.first;
  String _selectedFoodCategory = foodMainCategories.first;
  String _shareScope = 'none';
  bool _isRestaurantAuthor = false;
  String _authorType = 'person';
  bool _loading = false;

  _ComposerMediaMode _mediaMode = _ComposerMediaMode.none;
  List<XFile> _selectedImages = const [];
  XFile? _selectedVideo;
  Future<XFile?>? _selectedVideoThumbnailFuture;
  List<MentionCandidate> _selectedMentions = const [];

  bool get _isAndroid => !kIsWeb && isAndroidPlatform;
  bool get _isMarketPost => _selectedPostType == PostType.market;
  bool get _isServicePost =>
      _selectedPostType == PostType.serviceOffer ||
      _selectedPostType == PostType.serviceRequest;
  bool get _isFoodAdPost => _selectedPostType == PostType.foodAd;
  bool get _supportsVideoModes => !_isMarketPost && !_isServicePost && !_isFoodAdPost;
  bool get _isOrganization => _authorType == 'org';

  @override
  void initState() {
    super.initState();
    _loadAuthorMetadata();
  }

  @override
  void dispose() {
    _contentCtrl.dispose();
    _videoUrlCtrl.dispose();
    _marketTitleCtrl.dispose();
    _marketPriceCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAuthorMetadata() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      final row = await Supabase.instance.client
          .from('profiles')
          .select('is_restaurant, profile_type, account_type')
          .eq('id', user.id)
          .maybeSingle();
      if (!mounted) return;
      setState(() {
        _isRestaurantAuthor = row?['is_restaurant'] == true;
        _authorType = (row?['profile_type'] as String?) ??
            (row?['account_type'] as String?) ??
            'person';
      });
    } on PostgrestException {
      if (!mounted) return;
      setState(() {
        _isRestaurantAuthor = false;
        _authorType = 'person';
      });
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
        _selectedVideoThumbnailFuture = null;
      }
      if (mode != _ComposerMediaMode.youtube) {
        _videoUrlCtrl.clear();
      }
    });
  }

  void _onPostTypeChanged(PostType value) {
    setState(() {
      _selectedPostType = value;
      // Enforce public for everything except general posts by persons
      if (value != PostType.post || _isOrganization) {
        _visibility = 'public';
      }
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
    List<XFile> files;
    if (_isAndroid) {
      final paths = await _cameraChannel.invokeListMethod<String>('pickImages');
      if (paths == null || paths.isEmpty) return;
      files = paths.whereType<String>().where((path) => path.isNotEmpty).map(XFile.new).toList();
    } else {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: true,
      );
      if (result == null || result.files.isEmpty) return;
      files = result.files
          .where((f) => f.path != null)
          .map((f) => XFile(f.path!))
          .toList();
    }
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
    XFile? file;
    if (_isAndroid) {
      final path = await _cameraChannel.invokeMethod<String>('pickVideoFromGallery');
      if (path == null || path.isEmpty) return;
      file = XFile(path);
    } else {
      final result = await FilePicker.platform.pickFiles(type: FileType.video);
      if (result == null || result.files.isEmpty || result.files.first.path == null) return;
      file = XFile(result.files.first.path!);
    }

    final size = await _fileLength(file);
    if (size > MediaLimits.maxVideoBytes) {
      if (!mounted) return;
      _showError('Video too large. Maximum size is ${_formatMb(MediaLimits.maxVideoBytes)} MB.');
      return;
    }

    if (!mounted) return;
    setState(() {
      _mediaMode = _ComposerMediaMode.videoFile;
      _selectedVideo = file;
      _selectedVideoThumbnailFuture = MediaCompressionService.generateVideoThumbnail(file!);
      _selectedImages = const [];
      _videoUrlCtrl.clear();
    });
  }

  Widget _buildVideoPreviewThumbnail(XFile video) {
    return FutureBuilder<XFile?>(
      future: _selectedVideoThumbnailFuture,
      builder: (context, snapshot) {
        final thumbnail = snapshot.data;
        final imageProvider = thumbnail != null
            ? (kIsWeb
                ? NetworkImage(thumbnail.path)
                : localImageProvider(thumbnail.path))
            : null;

        return ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: double.infinity,
                height: 220,
                color: Colors.black,
                child: imageProvider != null
                    ? Image(image: imageProvider, fit: BoxFit.cover)
                    : const Center(child: CircularProgressIndicator()),
              ),
              Container(color: Colors.black.withValues(alpha: 0.24)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  video.name.isNotEmpty ? video.name : 'Video selected',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
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
        _showError(context.l10n.tr('no_mutual_connections'));
        return;
      }

      final selected = await showMentionPickerSheet(
        context: context,
        available: connections,
        initialSelection: _selectedMentions,
        title: context.l10n.tr('tag_connections'),
      );

      if (selected != null && mounted) {
        setState(() => _selectedMentions = selected);
      }
    } catch (e) {
      if (!mounted) return;
      _showError(context.l10n.tr('tag_loading_failed', args: {'error': '$e'}));
    }
  }

  Future<void> _submit() async {
    final rawContent = _contentCtrl.text.trim();
    final marketTitle = _marketTitleCtrl.text.trim();
    final marketPriceRaw = _marketPriceCtrl.text.trim();

    if (rawContent.isEmpty) {
      _showError(context.l10n.tr('write_something'));
      return;
    }

    if (_isMarketPost && _selectedMarketCategory.isEmpty) {
      _showError(context.l10n.tr('select_product_category'));
      return;
    }

    if (_isServicePost && _selectedServiceCategory.isEmpty) {
      _showError(context.l10n.tr('select_service_category'));
      return;
    }

    if (_isFoodAdPost && marketTitle.isEmpty) {
      _showError(context.l10n.tr('enter_food_name'));
      return;
    }

    double? marketPrice;
    if (_isMarketPost ||
        ((_isFoodAdPost || _isServicePost) && marketPriceRaw.isNotEmpty)) {
      marketPrice = double.tryParse(marketPriceRaw);
      if (marketPrice == null || marketPrice < 0) {
        _showError(context.l10n.tr('enter_valid_price'));
        return;
      }
    }

    if (_isMarketPost && marketPriceRaw.isEmpty) {
      _showError(context.l10n.tr('enter_product_price'));
      return;
    }

    if (_isFoodAdPost && _selectedFoodCategory.isEmpty) {
      _showError(context.l10n.tr('select_food_category'));
      return;
    }

    String? videoUrl;
    if (_mediaMode == _ComposerMediaMode.youtube) {
      final rawUrl = _videoUrlCtrl.text.trim();
      if (rawUrl.isEmpty || !_isValidYoutubeUrl(rawUrl)) {
        _showError(context.l10n.tr('paste_valid_youtube'));
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
            title: Text(context.l10n.tr('location_required')),
            content: Text(context.l10n.tr('set_location_in_profile')),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(context.l10n.tr('cancel')),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  context.go('/complete-profile');
                },
                child: Text(context.l10n.tr('complete_profile')),
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
        final upload = await service.uploadPostVideo(
          video: _selectedVideo!,
          userId: supabase.auth.currentUser!.id,
        );
        videoUrl = upload.videoUrl;
        imageUrl = upload.thumbnailUrl;
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
      _showError(context.l10n.tr('error_with_detail', args: {'error': '$e'}));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _buildPhotoPreview(XFile file) {
    final imageProvider = kIsWeb
        ? NetworkImage(file.path)
        : localImageProvider(file.path);
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
    final l10n = context.l10n;
    final photoSubtitle = 'Up to 2 photos, ${_formatMb(_maxPhotoBytes)} MB each';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.tr('media'),
          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        _mediaModeTile(
          title: l10n.tr('no_media'),
          subtitle: l10n.tr('text_only'),
          icon: Icons.notes_outlined,
          mode: _ComposerMediaMode.none,
          enabled: true,
        ),
        const SizedBox(height: 8),
        _mediaModeTile(
          title: l10n.tr('photos'),
          subtitle: photoSubtitle,
          icon: Icons.photo_library_outlined,
          mode: _ComposerMediaMode.photos,
          enabled: true,
        ),
        if (_supportsVideoModes) ...[
          const SizedBox(height: 8),
          _mediaModeTile(
            title: l10n.tr('video_file'),
            subtitle: l10n.tr('one_video_from_gallery'),
            icon: Icons.video_library_outlined,
            mode: _ComposerMediaMode.videoFile,
            enabled: true,
          ),
          const SizedBox(height: 8),
          _mediaModeTile(
            title: l10n.tr('youtube_link'),
            subtitle: l10n.tr('one_youtube_only'),
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
            label: Text(
              _selectedImages.isEmpty
                  ? l10n.tr('choose_photos')
                  : l10n.tr('replace_photos'),
            ),
          ),
        ],
        if (_mediaMode == _ComposerMediaMode.videoFile) ...[
          if (_selectedVideo != null)
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE6DDCE)),
              ),
              child: Column(
                children: [
                  _buildVideoPreviewThumbnail(_selectedVideo!),
                  Align(
                    alignment: Alignment.centerRight,
                    child: IconButton(
                      onPressed: () => setState(() {
                        _selectedVideo = null;
                        _selectedVideoThumbnailFuture = null;
                        _mediaMode = _ComposerMediaMode.none;
                      }),
                      icon: const Icon(Icons.close),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _loading ? null : _pickVideoFile,
            icon: const Icon(Icons.video_library_outlined),
            label: Text(
              _selectedVideo == null
                  ? l10n.tr('choose_video')
                  : l10n.tr('replace_video'),
            ),
          ),
        ],
        if (_mediaMode == _ComposerMediaMode.youtube) ...[
          TextField(
            controller: _videoUrlCtrl,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              labelText: l10n.tr('youtube_video_url'),
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
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.tr('create_post'))),
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
                    decoration: InputDecoration(
                      labelText: l10n.tr('what_is_happening'),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: _loading ? null : _pickMentions,
                        icon: const Icon(Icons.alternate_email),
                        label: Text(l10n.tr('tag_connections')),
                      ),
                      if (_selectedMentions.isNotEmpty) ...[
                        const SizedBox(width: 10),
                        Text(
                          l10n.tr('selected_count', args: {'count': '${_selectedMentions.length}'}),
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
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      labelText: l10n.tr('post_category'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_isMarketPost || _isServicePost || _isFoodAdPost) ...[
                    TextField(
                      controller: _marketTitleCtrl,
                      decoration: InputDecoration(
                        border: const OutlineInputBorder(),
                        labelText: _isFoodAdPost
                            ? l10n.tr('food_name')
                            : (_isServicePost
                                ? l10n.tr('service_title')
                                : l10n.tr('product_title')),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _marketPriceCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        border: const OutlineInputBorder(),
                        labelText: _isFoodAdPost
                            ? l10n.tr('food_price_optional')
                            : (_isServicePost
                                ? l10n.tr('rate_budget_optional')
                                : l10n.tr('price')),
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
                      items: [
                        DropdownMenuItem(value: 'selling', child: Text(l10n.tr('selling'))),
                        DropdownMenuItem(value: 'buying', child: Text(l10n.tr('buying'))),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() => _selectedMarketIntent = v);
                      },
                      decoration: InputDecoration(
                        border: const OutlineInputBorder(),
                        labelText: l10n.tr('marketplace_type'),
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
                      decoration: InputDecoration(
                        border: const OutlineInputBorder(),
                        labelText: l10n.tr('product_category'),
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
                      decoration: InputDecoration(
                        border: const OutlineInputBorder(),
                        labelText: l10n.tr('service_category'),
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
                      decoration: InputDecoration(
                        border: const OutlineInputBorder(),
                        labelText: l10n.tr('food_category'),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  _buildMediaSection(),
                  const SizedBox(height: 12),
                  if (_selectedPostType == PostType.post && !_isOrganization) ...[
                    DropdownButtonFormField<String>(
                      initialValue: _visibility,
                      items: [
                        DropdownMenuItem(value: 'public', child: Text(l10n.tr('public'))),
                        DropdownMenuItem(value: 'followers', child: Text(l10n.tr('local'))),
                      ],
                      onChanged: (v) => setState(() => _visibility = v ?? 'public'),
                      decoration: InputDecoration(
                        border: const OutlineInputBorder(),
                        labelText: l10n.tr('visibility'),
                      ),
                    ),
                  ] else ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.public, color: Colors.blue),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              l10n.tr('this_post_public_nearby'),
                              style: TextStyle(color: Colors.blue),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _shareScope,
                    items: [
                      DropdownMenuItem(value: 'none', child: Text(l10n.tr('no_sharing'))),
                      DropdownMenuItem(value: 'followers', child: Text(l10n.tr('followers_can_share'))),
                      DropdownMenuItem(value: 'connections', child: Text(l10n.tr('connections_can_share'))),
                      DropdownMenuItem(value: 'public', child: Text(l10n.tr('public_can_share'))),
                    ],
                    onChanged: (v) => setState(() => _shareScope = v ?? 'none'),
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      labelText: l10n.tr('allow_sharing'),
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
                        : Text(l10n.tr('post_label')),
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
