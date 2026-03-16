# Flutter image_picker_android — keep Pigeon-generated channel classes from R8 obfuscation
-keep class io.flutter.plugins.imagepicker.** { *; }
-keep class dev.flutter.pigeon.** { *; }

# Flutter plugins general
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# file_picker — keep plugin class and all method handlers from R8 obfuscation
-keep class com.mr.flutter.plugin.filepicker.** { *; }

# Google Play Core — referenced by Flutter engine but not required at runtime
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.SplitInstallException
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManager
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManagerFactory
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest$Builder
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest
-dontwarn com.google.android.play.core.splitinstall.SplitInstallSessionState
-dontwarn com.google.android.play.core.splitinstall.SplitInstallStateUpdatedListener
-dontwarn com.google.android.play.core.tasks.OnFailureListener
-dontwarn com.google.android.play.core.tasks.OnSuccessListener
-dontwarn com.google.android.play.core.tasks.Task

# FFmpeg Kit — kept entirely to prevent R8 from removing native bridge classes
-keep class com.antonkarpenko.ffmpegkit.** { *; }
-keepclassmembers class com.antonkarpenko.ffmpegkit.** { *; }
-dontwarn com.antonkarpenko.ffmpegkit.**

# Supabase / OkHttp
-dontwarn okhttp3.**
-dontwarn okio.**
-keepclassmembers class * extends java.lang.Enum { *; }
