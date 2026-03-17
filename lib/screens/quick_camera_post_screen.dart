import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';

import '../core/localization/app_localizations.dart';
import '../core/platform/local_image_provider.dart';
import '../core/platform/local_video_controller.dart';
import '../services/media_compression_service.dart';
import '../services/mention_service.dart';
import '../services/post_service.dart';
import '../widgets/global_bottom_nav.dart';
import '../widgets/mention_picker_sheet.dart';

enum QuickCaptureMode { photo, video }

class QuickCameraPostScreen extends StatefulWidget {
  const QuickCameraPostScreen({super.key, required this.mode});

  final QuickCaptureMode mode;

  @override
  State<QuickCameraPostScreen> createState() => _QuickCameraPostScreenState();
}

class _QuickCameraPostScreenState extends State<QuickCameraPostScreen> {
  final _contentCtrl = TextEditingController();
  final _mentionService = MentionService(Supabase.instance.client);

  String _visibility = 'public';
  String _shareScope = 'none';
  bool _loading = false;
  bool _capturing = true;
  bool _isOrganization = false;
  XFile? _mediaFile;
  Future<XFile?>? _videoThumbnailFuture;
  VideoPlayerController? _videoController;
  bool _videoPlaying = false;
  List<MentionCandidate> _selectedMentions = const [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _loadAuthorMetadata();
    await _captureMedia();
  }

  @override
  void dispose() {
    _contentCtrl.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _loadAuthorMetadata() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      final row = await Supabase.instance.client
          .from('profiles')
          .select('profile_type, account_type')
          .eq('id', user.id)
          .maybeSingle();
      if (!mounted) return;
      setState(() {
        final authorType = (row?['profile_type'] as String?) ??
            (row?['account_type'] as String?) ??
            'person';
        _isOrganization = authorType == 'org';
        if (_isOrganization) {
          _visibility = 'public';
        }
      });
    } catch (_) {
      // Keep defaults
    }
  }

  Future<void> _captureMedia() async {
    if (!mounted) return;
    _videoController?.dispose();
    setState(() {
      _capturing = true;
      _mediaFile = null;
      _videoThumbnailFuture = null;
      _videoController = null;
      _videoPlaying = false;
    });

    try {
      const channel = MethodChannel('com.local_social/camera');
      final String? path = await channel.invokeMethod<String>(
        widget.mode == QuickCaptureMode.photo ? 'capturePhoto' : 'captureVideo',
      );

      if (!mounted) return;
      if (path == null) {
        Navigator.pop(context, false);
        return;
      }

      setState(() {
        _mediaFile = XFile(path);
        _videoThumbnailFuture = widget.mode == QuickCaptureMode.video
            ? MediaCompressionService.generateVideoThumbnail(_mediaFile!)
            : null;
      });
    } catch (e) {
      if (mounted) {
        _showError(context.l10n.tr('camera_failed', args: {'error': '$e'}));
        Navigator.pop(context, false);
      }
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  Future<void> _pickMentions() async {
    final l10n = context.l10n;
    try {
      final connections = await _mentionService.fetchMutualConnections();
      if (!mounted) return;
      if (connections.isEmpty) {
        _showError(l10n.tr('no_mutual_connections'));
        return;
      }

      final selected = await showMentionPickerSheet(
        context: context,
        available: connections,
        initialSelection: _selectedMentions,
        title: l10n.tr('tag_connections'),
      );

      if (selected != null && mounted) {
        setState(() => _selectedMentions = selected);
      }
    } catch (e) {
      _showError(l10n.tr('tag_loading_failed', args: {'error': '$e'}));
    }
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

  Future<void> _submit() async {
    final l10n = context.l10n;
    final mediaFile = _mediaFile;
    if (mediaFile == null) {
      _showError(l10n.tr('capture_something_first'));
      return;
    }

    setState(() => _loading = true);
    try {
      final supabase = Supabase.instance.client;
      final service = PostService(supabase);
      final rawContent = _contentCtrl.text.trim();
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

      final allowedTagIds = await _mentionService
          .filterAllowedUserIds(_selectedMentions.map((e) => e.id).toList());
      final content = _mentionService.composeTaggedContent(
        rawContent,
        _selectedMentions,
      );

      String? imageUrl;
      String? videoUrl;
      if (widget.mode == QuickCaptureMode.photo) {
        imageUrl = await service.uploadPostImage(
          image: mediaFile,
          userId: supabase.auth.currentUser!.id,
        );
      } else {
        final upload = await service.uploadPostVideo(
          video: mediaFile,
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
        videoUrl: videoUrl,
        postType: 'post',
        shareScope: _shareScope,
        taggedUserIds: allowedTagIds,
      );

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      _showError(l10n.tr('error_with_detail', args: {'error': '$e'}));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _buildPreview() {
    final mediaFile = _mediaFile;
    if (_capturing) {
      return const Center(child: CircularProgressIndicator());
    }
    if (mediaFile == null) {
      return Center(child: Text(context.l10n.tr('no_media_captured')));
    }

    if (widget.mode == QuickCaptureMode.photo) {
      final provider = kIsWeb
          ? NetworkImage(mediaFile.path)
          : localImageProvider(mediaFile.path);
      return ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Image(
          image: provider,
          width: double.infinity,
          height: 320,
          fit: BoxFit.cover,
        ),
      );
    }

    // If video player is initialised and playing, show it
    if (_videoController != null && _videoController!.value.isInitialized) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: double.infinity,
              height: 320,
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _videoController!.value.size.width,
                  height: _videoController!.value.size.height,
                  child: VideoPlayer(_videoController!),
                ),
              ),
            ),
            GestureDetector(
              onTap: () {
                setState(() {
                  if (_videoController!.value.isPlaying) {
                    _videoController!.pause();
                    _videoPlaying = false;
                  } else {
                    _videoController!.play();
                    _videoPlaying = true;
                  }
                });
              },
              child: AnimatedOpacity(
                opacity: _videoPlaying ? 0.0 : 1.0,
                duration: const Duration(milliseconds: 200),
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.play_arrow, color: Colors.white, size: 32),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return FutureBuilder<XFile?>(
      future: _videoThumbnailFuture,
      builder: (context, snapshot) {
        final thumbnail = snapshot.data;
        final imageProvider = thumbnail != null
            ? (kIsWeb
                ? NetworkImage(thumbnail.path)
                : localImageProvider(thumbnail.path))
            : null;

        return ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: double.infinity,
                height: 320,
                color: Colors.black,
                child: imageProvider != null
                    ? Image(
                        image: imageProvider,
                        fit: BoxFit.cover,
                      )
                    : const Center(
                        child: CircularProgressIndicator(),
                      ),
              ),
              if (snapshot.connectionState == ConnectionState.done)
                GestureDetector(
                  onTap: () async {
                    final mediaFile = _mediaFile;
                    if (mediaFile == null) return;
                    final controller = createLocalVideoController(mediaFile.path);
                    await controller.initialize();
                    if (!mounted) {
                      controller.dispose();
                      return;
                    }
                    setState(() {
                      _videoController = controller;
                      _videoPlaying = true;
                    });
                    controller.play();
                  },
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.play_arrow, color: Colors.white, size: 32),
                  ),
                )
              else
                Container(color: Colors.black.withValues(alpha: 0.24)),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.tr('quick_camera_post'))),
      bottomNavigationBar: const GlobalBottomNav(),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildPreview(),
              const SizedBox(height: 16),
              TextField(
                controller: _contentCtrl,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: l10n.tr('what_is_happening'),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _loading ? null : _captureMedia,
                      icon: const Icon(Icons.refresh),
                      label: Text(l10n.tr('retake')),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _loading ? null : _pickMentions,
                      icon: const Icon(Icons.alternate_email),
                      label: Text(l10n.tr('tag_connections')),
                    ),
                  ),
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
              ],
              const SizedBox(height: 12),
              if (!_isOrganization) ...[
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
                          l10n.tr('this_quick_post_public'),
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
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _loading || _capturing ? null : _submit,
                child: _loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l10n.tr('post_now')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
