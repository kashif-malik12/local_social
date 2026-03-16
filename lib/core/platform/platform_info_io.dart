import 'dart:io' show Directory, Platform;

bool get isAndroidPlatform => Platform.isAndroid;
bool get isIOSPlatform => Platform.isIOS;
bool get isMacOSPlatform => Platform.isMacOS;
String get systemTempPath => Directory.systemTemp.path;
