import 'package:flutter/material.dart';

import 'network_video_player.dart';
import 'youtube_preview.dart';

class PostMediaView extends StatefulWidget {
  final String? imageUrl;
  final String? secondImageUrl;
  final String? videoUrl;
  final double maxHeight;
  final void Function(String imageUrl)? onImageTap;
  final bool singleImagePreview;

  const PostMediaView({
    super.key,
    this.imageUrl,
    this.secondImageUrl,
    this.videoUrl,
    this.maxHeight = 360,
    this.onImageTap,
    this.singleImagePreview = false,
  });

  @override
  State<PostMediaView> createState() => _PostMediaViewState();
}

class _PostMediaViewState extends State<PostMediaView> {
  int _pageIndex = 0;

  bool _isYoutubeUrl(String? value) {
    if (value == null || value.trim().isEmpty) return false;
    final uri = Uri.tryParse(value.trim());
    if (uri == null) return false;
    final host = uri.host.toLowerCase();
    return host.contains('youtube.com') || host.contains('youtu.be');
  }

  Widget _buildImage(String url, {double? width}) {
    final image = ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: width ?? double.infinity,
        constraints: BoxConstraints(maxHeight: widget.maxHeight),
        color: Colors.black.withOpacity(0.04),
        child: Image.network(
          url,
          width: width ?? double.infinity,
          fit: BoxFit.contain,
          alignment: Alignment.center,
        ),
      ),
    );

    if (widget.onImageTap == null) return image;
    return GestureDetector(
      onTap: () => widget.onImageTap!(url),
      child: image,
    );
  }

  Widget _buildTwoImageLayout(List<String> images, BuildContext context) {
    final isCompact = MediaQuery.of(context).size.width < 700;

    if (!isCompact) {
      return Row(
        children: [
          Expanded(child: _buildImage(images.first)),
          const SizedBox(width: 10),
          Expanded(child: _buildImage(images[1])),
        ],
      );
    }

    return Column(
      children: [
        SizedBox(
          height: widget.maxHeight.clamp(220, 420),
          child: PageView.builder(
            itemCount: images.length,
            onPageChanged: (index) => setState(() => _pageIndex = index),
            itemBuilder: (_, index) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: _buildImage(images[index]),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            images.length,
            (index) => AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: _pageIndex == index ? 18 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: _pageIndex == index ? const Color(0xFF0F766E) : const Color(0xFFD8C8AF),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final images = [widget.imageUrl, widget.secondImageUrl]
        .whereType<String>()
        .map((url) => url.trim())
        .where((url) => url.isNotEmpty)
        .toList();

    final trimmedVideo = widget.videoUrl?.trim();
    if (trimmedVideo != null && trimmedVideo.isNotEmpty) {
      if (_isYoutubeUrl(trimmedVideo)) {
        return YoutubePreview(videoUrl: trimmedVideo);
      }
      return NetworkVideoPlayer(videoUrl: trimmedVideo, maxHeight: widget.maxHeight);
    }

    if (images.isEmpty) {
      return const SizedBox.shrink();
    }

    if (images.length == 1) {
      return _buildImage(images.first);
    }

    if (widget.singleImagePreview) {
      return _buildImage(images.first);
    }

    return _buildTwoImageLayout(images, context);
  }
}
