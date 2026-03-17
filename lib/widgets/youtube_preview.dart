import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../core/utils/youtube_utils.dart';
import '../services/app_settings_service.dart';

class YoutubePreview extends StatelessWidget {
  final String videoUrl;
  final bool startMuted;
  final bool showMuteToggle;

  const YoutubePreview({
    super.key,
    required this.videoUrl,
    this.startMuted = false,
    this.showMuteToggle = false,
  });

  Future<void> _openVideoExternally(BuildContext context, String videoId) async {
    final uri = Uri.parse(youtubeWatchUrlFromId(videoId));
    final launched = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );

    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open YouTube video.')),
      );
    }
  }

  void _openPlayer(BuildContext context, String videoId) {
    final shouldAutoplay = AppSettingsService.currentVideoAutoplayEnabled();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _YoutubePlayerSheet(
        videoId: videoId,
        autoplay: shouldAutoplay,
        startMuted: startMuted,
        showMuteToggle: showMuteToggle,
        onOpenYoutube: () => _openVideoExternally(context, videoId),
      ),
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
                  errorBuilder: (_, _, _) => Container(
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
                  color: Colors.black.withValues(alpha: 0.55),
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
  final Future<void> Function() onOpenYoutube;
  final bool autoplay;
  final bool startMuted;
  final bool showMuteToggle;

  const _YoutubePlayerSheet({
    required this.videoId,
    required this.onOpenYoutube,
    required this.autoplay,
    required this.startMuted,
    required this.showMuteToggle,
  });

  @override
  State<_YoutubePlayerSheet> createState() => _YoutubePlayerSheetState();
}

class _YoutubePlayerSheetState extends State<_YoutubePlayerSheet> {
  late final YoutubePlayerController _controller;
  late bool _muted;

  @override
  void initState() {
    super.initState();
    _muted = widget.startMuted;
    _controller = YoutubePlayerController(
      params: YoutubePlayerParams(
        showFullscreenButton: true,
        mute: widget.startMuted,
        strictRelatedVideos: true,
      ),
    );
    if (widget.autoplay) {
      _controller.loadVideoById(videoId: widget.videoId);
    } else {
      _controller.cueVideoById(videoId: widget.videoId);
    }
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
                return Stack(
                  children: [
                    AspectRatio(
                      aspectRatio: 16 / 9,
                      child: player,
                    ),
                    if (widget.showMuteToggle)
                      Positioned(
                        top: 12,
                        right: 12,
                        child: Material(
                          color: Colors.black.withValues(alpha: 0.5),
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () {
                              if (_muted) {
                                _controller.unMute();
                              } else {
                                _controller.mute();
                              }
                              setState(() => _muted = !_muted);
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Icon(
                                _muted ? Icons.volume_off : Icons.volume_up,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, color: Colors.white),
                      label: const Text(
                        'Close',
                        style: TextStyle(color: Colors.white),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.white24),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: widget.onOpenYoutube,
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Open on YouTube'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
