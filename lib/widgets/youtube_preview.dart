import 'package:flutter/material.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../core/utils/youtube_utils.dart';

class YoutubePreview extends StatelessWidget {
  final String videoUrl;
  const YoutubePreview({super.key, required this.videoUrl});

  void _openPlayer(BuildContext context, String videoId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _YoutubePlayerSheet(videoId: videoId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final videoId = extractYoutubeId(videoUrl);
    if (videoId == null) return const SizedBox.shrink();

    final thumb = youtubeThumbnailUrlFromId(videoId);

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openPlayer(context, videoId),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            alignment: Alignment.center,
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Image.network(
                  thumb!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: Colors.black12,
                    alignment: Alignment.center,
                    child: const Icon(Icons.play_circle_outline, size: 48),
                  ),
                ),
              ),
              Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.55),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.play_arrow, color: Colors.white, size: 40),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _YoutubePlayerSheet extends StatefulWidget {
  final String videoId;
  const _YoutubePlayerSheet({required this.videoId});

  @override
  State<_YoutubePlayerSheet> createState() => _YoutubePlayerSheetState();
}

class _YoutubePlayerSheetState extends State<_YoutubePlayerSheet> {
  late final YoutubePlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = YoutubePlayerController(
      params: const YoutubePlayerParams(
        showFullscreenButton: true,
        mute: false,
      ),
    );
       _controller.loadVideoById(videoId: widget.videoId);

  }

  @override
  void dispose() {
    _controller.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.only(top: 80),
        decoration: const BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Container(
                width: 46,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            YoutubePlayerScaffold(
              controller: _controller,
              builder: (context, player) {
                return AspectRatio(
                  aspectRatio: 16 / 9,
                  child: player,
                );
              },
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: TextButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: Colors.white),
                label: const Text('Close', style: TextStyle(color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}