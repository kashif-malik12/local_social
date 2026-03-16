import 'dart:io' show File;

import 'package:video_player/video_player.dart';

VideoPlayerController createLocalVideoController(String path) =>
    VideoPlayerController.file(File(path));
