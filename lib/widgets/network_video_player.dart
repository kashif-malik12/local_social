import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../app/router.dart';
import '../services/app_settings_service.dart';

class NetworkVideoPlayer extends StatefulWidget {
  final String videoUrl;
  final double maxHeight;
  final bool startMuted;
  final bool showMuteToggle;
  final bool? autoplay;
  final double muteTopOffset;
  /// When non-null, overrides internal mute state (controlled externally).
  final bool? muted;

  const NetworkVideoPlayer({
    super.key,
    required this.videoUrl,
    this.maxHeight = 360,
    this.startMuted = false,
    this.showMuteToggle = false,
    this.autoplay,
    this.muteTopOffset = 12,
    this.muted,
  });

  @override
  State<NetworkVideoPlayer> createState() => _NetworkVideoPlayerState();
}

class _NetworkVideoPlayerState extends State<NetworkVideoPlayer>
    with WidgetsBindingObserver, RouteAware {
  VideoPlayerController? _controller;
  bool _loading = true;
  bool _failed = false;
  bool _muted = false;
  bool _userPaused = false;
  bool _showControls = true;
  Timer? _hideControlsTimer;
  ModalRoute<dynamic>? _route;
  final _visibilityKey = UniqueKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void didUpdateWidget(NetworkVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.muted != null && widget.muted != oldWidget.muted) {
      _muted = widget.muted!;
      _controller?.setVolume(_muted ? 0 : 1);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Pause when hidden inside an IndexedStack (tab switch).
    if (!TickerMode.valuesOf(context).enabled) {
      _pauseSafely();
    }
    // Route observer subscription for push/pop pausing.
    final route = ModalRoute.of(context);
    if (_route == route) return;
    if (_route is PageRoute) {
      appRouteObserver.unsubscribe(this);
    }
    _route = route;
    if (route is PageRoute) {
      appRouteObserver.subscribe(this, route);
    }
  }

  @override
  void deactivate() {
    _pauseSafely();
    super.deactivate();
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    if (_route is PageRoute) {
      appRouteObserver.unsubscribe(this);
    }
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  void _onTapVideo() {
    final controller = _controller;
    if (controller == null) return;
    if (controller.value.isPlaying) {
      controller.pause();
      _userPaused = true;
      _hideControlsTimer?.cancel();
      setState(() => _showControls = true);
    } else {
      controller.play();
      _userPaused = false;
      setState(() => _showControls = true);
      _hideControlsTimer?.cancel();
      _hideControlsTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _showControls = false);
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _pauseSafely();
    }
  }

  @override
  void didPushNext() => _pauseSafely();

  @override
  void didPop() => _pauseSafely();

  void _pauseSafely() {
    final controller = _controller;
    if (controller != null && controller.value.isInitialized && controller.value.isPlaying) {
      controller.pause();
    }
  }

  Future<void> _init() async {
    final controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
    try {
      await controller.initialize();
      controller.setLooping(true);
      _muted = widget.muted ?? widget.startMuted;
      await controller.setVolume(_muted ? 0 : 1);
      final shouldAutoplay = widget.autoplay ?? AppSettingsService.currentVideoAutoplayEnabled();
      if (shouldAutoplay) {
        await controller.play();
      }
      if (shouldAutoplay) {
        _hideControlsTimer?.cancel();
        _hideControlsTimer = Timer(const Duration(seconds: 2), () {
          if (mounted) setState(() => _showControls = false);
        });
      }
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _loading = false;
      });
    } catch (_) {
      await controller.dispose();
      if (!mounted) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  Future<void> _toggleMute() async {
    final controller = _controller;
    if (controller == null) return;

    final nextMuted = !_muted;
    await controller.setVolume(nextMuted ? 0 : 1);
    if (!mounted) return;
    setState(() => _muted = nextMuted);
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (_loading) {
      return Container(
        height: 220,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const CircularProgressIndicator(),
      );
    }

    if (_failed || controller == null) {
      return Container(
        height: 180,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text('Video unavailable'),
      );
    }

    final aspectRatio = controller.value.aspectRatio == 0 ? 16 / 9 : controller.value.aspectRatio;
    final expandToFill = widget.maxHeight == double.infinity;
    return VisibilityDetector(
      key: _visibilityKey,
      onVisibilityChanged: (info) {
        if (!mounted) return;
        if (info.visibleFraction < 0.3) {
          _pauseSafely();
        } else if (!_userPaused && info.visibleFraction >= 0.3) {
          final shouldAutoplay = widget.autoplay ?? AppSettingsService.currentVideoAutoplayEnabled();
          if (shouldAutoplay && !controller.value.isPlaying) {
            controller.play();
            _hideControlsTimer?.cancel();
            _hideControlsTimer = Timer(const Duration(seconds: 2), () {
              if (mounted) setState(() => _showControls = false);
            });
          }
        }
      },
      child: ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        constraints: BoxConstraints(maxHeight: widget.maxHeight),
        color: Colors.black,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: expandToFill
                  ? FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(
                        width: controller.value.size.width,
                        height: controller.value.size.height,
                        child: VideoPlayer(controller),
                      ),
                    )
                  : AspectRatio(
                      aspectRatio: aspectRatio,
                      child: VideoPlayer(controller),
                    ),
            ),
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _onTapVideo,
                child: AnimatedOpacity(
                  opacity: _showControls ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: Center(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        shape: BoxShape.circle,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Icon(
                          controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
                          color: Colors.white,
                          size: 30,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (widget.showMuteToggle)
              Positioned(
                top: widget.muteTopOffset,
                right: 12,
                child: GestureDetector(
                  onTap: _toggleMute,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      _muted ? Icons.volume_off : Icons.volume_up,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      ),
    );
  }
}

