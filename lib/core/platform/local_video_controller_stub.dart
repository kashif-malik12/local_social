import 'package:video_player/video_player.dart';

VideoPlayerController createLocalVideoController(String path) =>
    VideoPlayerController.networkUrl(Uri.parse(path));
