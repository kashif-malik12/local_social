import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/post_types.dart';
import '../services/post_service.dart';


class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({super.key});

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final _contentCtrl = TextEditingController();
  final _videoUrlCtrl = TextEditingController();

  String _visibility = 'public';
  PostType _selectedPostType = PostType.post;

  XFile? _imageXFile;
  bool _loading = false;

  final _picker = ImagePicker();

  @override
  void dispose() {
    _contentCtrl.dispose();
    _videoUrlCtrl.dispose();
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

    final profile = await supabase
        .from('profiles')
        .select('city, latitude, longitude')
        .eq('id', user.id)
        .maybeSingle();

    return profile;
  }

  bool _isValidYoutubeUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;

    final host = uri.host.toLowerCase();
    // Accept common YouTube hosts
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

    // optional: validate youtube link if provided
    if (videoUrl != null && !_isValidYoutubeUrl(videoUrl)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please paste a valid YouTube link (youtube.com / youtu.be)')),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final supabase = Supabase.instance.client;
      final service = PostService(supabase);

      // ✅ Get location from profile
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
        videoUrl: videoUrl, // ✅ NEW
        postType: _selectedPostType.dbValue,
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

            // ✅ Post type
            DropdownButtonFormField<PostType>(
              initialValue: _selectedPostType,
              items: PostType.values.map((t) {
                return DropdownMenuItem(
                  value: t,
                  child: Text(t.label),
                );
              }).toList(),
              onChanged: (v) => setState(() => _selectedPostType = v ?? PostType.post),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Post category',
              ),
            ),
            const SizedBox(height: 12),

            // ✅ Visibility
            DropdownButtonFormField<String>(
              initialValue: _visibility,
              items: const [
                DropdownMenuItem(value: 'public', child: Text('Public')),
                DropdownMenuItem(value: 'followers', child: Text('Followers')),
              ],
              onChanged: (v) => setState(() => _visibility = v ?? 'public'),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Visibility',
              ),
            ),

            const SizedBox(height: 12),

            // ✅ YouTube link
            TextField(
              controller: _videoUrlCtrl,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'YouTube link (optional)',
                hintText: 'https://youtube.com/watch?v=... or https://youtu.be/...',
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 12),

            // ✅ Image picker
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _loading ? null : _pickImage,
                  icon: const Icon(Icons.image),
                  label: const Text('Add Image'),
                ),
                const SizedBox(width: 12),
                if (_imageXFile != null) const Text('Selected ✅'),
              ],
            ),

            const SizedBox(height: 18),

            // ✅ Submit
            ElevatedButton(
              onPressed: _loading ? null : _submit,
              child: _loading
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Post'),
            ),
          ],
        ),
      ),
    );
  }
}