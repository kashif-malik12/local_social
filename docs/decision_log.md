# Decision Log & Project Memory

This file is the single source of truth for all project decisions, technical context, and memory across sessions.
Update this file after every significant change — do not wait to be asked.

---

## Project Summary

Flutter social media app for local communities. Supabase backend. Originally built with Codex CLI, migrated to Claude Code on 2026-03-11.
- Tech: Flutter + Riverpod + GoRouter + Supabase. Dart SDK ^3.10.3
- Secrets: `lib/core/config/env.dart` — never commit
- Routes: `lib/app/router.dart`
- Main feed: `lib/screens/feed_screen.dart` (~3471 lines — careful with bulk edits)

---

## Navigation Architecture

- Feed, Search, Chat, Notifications are persistent tabs via `StatefulShellRoute.indexedStack` in `router.dart`.
- Shell widget: `lib/widgets/main_shell.dart` (transparent passthrough — each screen keeps its own Scaffold + GlobalBottomNav).
- Tab switching uses `context.go()` — NOT `context.push()` — for these four routes.
- All other screens (post detail, marketplace, profile, etc.) push on root navigator as before.
- This keeps all four tabs alive in an IndexedStack — switching is instant, state is preserved.

---

## UI Decisions

- The app-side product branding is now `Allonssy` across in-app titles, auth screens, location dialogs, web metadata, and platform display metadata. Package IDs, bundle IDs, namespaces, and native method channel identifiers remain unchanged for stability.
- The mobile video feed scope controls (`Following`, `Radius`, `Public`, `Trending`) belong at the bottom of the video card, not as a top overlay.
- When the mobile video feed has no items, the user must still be able to switch filters from the empty state.
- The mobile video feed should render fast: load the active card first, use lightweight posters for off-screen cards, and avoid blocking first paint on per-post enrichment.
- New uploaded video posts should store a real thumbnail poster in `image_url` so the video feed can render instantly before playback starts.

---

## Notification Settings

- App preferences are stored in `auth.users.raw_user_meta_data.app_settings`.
- `video_autoplay` remains part of `app_settings`.
- In-app notification preferences are also stored in `app_settings`.
- Push notification preferences are stored in `app_settings` for future FCM/web push work, even though push delivery is not connected yet.
- Notification inserts must respect recipient settings centrally in the database, not only in Flutter UI.

---

## Release APK Workarounds

- Android release builds hit a `shared_preferences` plugin channel failure during `Supabase.initialize()`.
- Current workaround in `lib/main.dart` avoids `shared_preferences` during Android release startup by using file-backed auth storage and PKCE storage.
- If this workaround is removed later, verify release APK startup and session persistence before shipping.

---

## Media Flow Decisions

- Quick camera on Android uses the app's own native `MethodChannel` flow in `MainActivity.kt`, not `image_picker`, because the plugin path hit unstable Android `pigeon`/channel failures in this project.
- Android quick video capture must request both `CAMERA` and `RECORD_AUDIO` permissions before launch.
- Android quick video capture must tolerate both return styles from camera apps: file output via `EXTRA_OUTPUT` and fallback `content://` URI results.
- Local video preview in post composers uses a tap-to-play approach: show the FFmpeg-generated thumbnail first, then lazily initialize `VideoPlayerController.file()` only when the user taps the play button. Eager initialization caused freezes/crashes on some Android devices, but lazy init on tap is stable.
- Video uploads should still generate and store a real thumbnail poster in `image_url`; the thumbnail-first composer preview is only a local UI stability decision.
- Android gallery selection in the full create-post screen uses the native `MethodChannel` bridge for images/videos instead of the broken plugin path used earlier.
- Avatar selection in the profile screen should use `image_picker` on Android/iOS and keep `file_picker` only as a desktop/web fallback; the generic picker path was unstable on mobile while post/media selection already had mobile-specific handling.
- Storage object paths must keep the authenticated user ID as the first folder segment for buckets protected by `storage.foldername(name)[1] = auth.uid()::text`. Chat attachments in `post-images` therefore live under `<userId>/chat_attachments/...`, not `chat_attachments/<userId>/...`.

---

## Android Release Build (R8/ProGuard)

- Release builds require explicit ProGuard rules in `android/app/proguard-rules.pro` with `isMinifyEnabled = true` in `build.gradle.kts`; without this, AGP 8.x fails on missing Play Core classes.
- `image_picker_android` Pigeon `BasicMessageChannel` silently fails in release mode — root cause not resolved; do NOT attempt to fix again. Native `MethodChannel` bridge in `MainActivity.kt` is the confirmed working replacement.
- Camera + gallery go through `com.local_social/camera` MethodChannel: `capturePhoto`, `captureVideo`, `pickImages`, `pickVideoFromGallery`.
- `file_picker` (`com.mr.flutter.plugin.filepicker`) must be kept via `-keep class com.mr.flutter.plugin.filepicker.** { *; }` or R8 renames `FilePickerPlugin` and breaks method dispatch for `FileType.image`, `FileType.video`, etc.
- `ffmpeg_kit_flutter_new` (package `com.antonkarpenko.ffmpegkit`) classes are REMOVED by R8 by default, crashing video compression and thumbnail generation. Fix: `-keep class com.antonkarpenko.ffmpegkit.** { *; }` in `proguard-rules.pro`.
- Google Play Core classes must be suppressed with `-dontwarn com.google.android.play.core.**` rules.
- `FileProvider` config at `android/app/src/main/res/xml/file_paths.xml` is required for camera capture via `FileProvider.getUriForFile`.
- `MainActivity` extends `FlutterFragmentActivity` (not `FlutterActivity`) so that `ActivityResultLauncher` registration in `onCreate` has access to `ComponentActivity.registerForActivityResult`.

---

## Feed Performance Decisions

- The main feed keeps its 20-post pagination size for now, but heavy media should not be eagerly initialized for every visible card on first load.
- In the main feed, only the active card area should build full media widgets; off-focus posts should render lightweight media previews/posters and defer heavier media work until the user scrolls near them.

---

## Architecture Direction

- The project stays on Supabase as the primary backend.
- The app is now running against the self-hosted Supabase deployment on the VPS, not hosted Supabase.
- Firebase may be added later for push notifications and related mobile platform services, not as the primary replacement for the current relational backend.
- The current self-hosted Supabase/test VPS is `87.106.13.170` and the standard SSH user is `deploy`.
- On this development PC, SSH key-based access for `deploy@87.106.13.170` is already configured and should be assumed available for future maintenance commands unless noted otherwise.
- The self-hosted Supabase VPS now has automated `deploy`-user backups every 6 hours via `~/bin/backup_supabase_vps.sh`, writing timestamped database, storage, and config archives under `~/backups/supabase/` with a default 5-day retention window. This is an on-box recovery layer only; offsite replication is still required before launch.
- The VPS monitoring layer is intentionally lightweight and non-root: `~/bin/monitor_vps_health.sh` logs container status, public endpoint health, disk, memory, uptime, and load to `~/monitoring/health.log` every 10 minutes. This is sufficient for test/pre-launch visibility; external alerting can be added later.
- The VPS also sends one daily summary email via `~/bin/daily_server_summary.py`, reusing the existing SMTP config from `~/supabase-project/.env` and summarizing current health, containers, latest backup, and recent monitoring output. Default recipient is `ali.kashifmalik@gmail.com` unless overridden with `ALERT_EMAIL_TO`.
- Critical email alerting now runs separately via `~/bin/critical_server_alert.py` with a 30-minute cooldown. On the small test VPS it is intentionally limited to harder failures: missing/unhealthy containers, app/storage endpoint failures, and high disk usage. Memory/load-based critical alerting is deferred until the larger production VPS.

---

## Flutter Analyze Status

- ~126 issues (all infos), no errors or blocking warnings.
- Do NOT remove `_buildQaPreview` in `feed_screen.dart:3031` — it cascades into many more warnings.
- Common infos: `withOpacity` deprecated → replace gradually with `.withValues(alpha: x)`.

---

## Known Pitfalls

- `feed_screen.dart` has lots of dead code. Removing one unused method cascades into more warnings. Only remove simple unused imports/variables in small files.
- Always restore from git (`git checkout HEAD -- <file>`) if a deletion cascades badly.
- Unread badge streams in `unread_badge_controller.dart` listen to the entire `messages` and `offer_messages` tables unfiltered — every message from any user triggers an RPC call. Low priority now but will degrade at scale. (See `docs/todo.md`)

---

## Firebase Security & Secrets (2026-03-16)

### What happened
Android `google-services.json` and web `firebase-messaging-sw.js` were accidentally committed and pushed to the public GitHub repo, exposing two Firebase API keys. Google and GitGuardian both sent alerts.

### What was done
- Both API keys rotated in Google Cloud Console immediately
- `android/app/google-services.json` removed from git tracking, added to `.gitignore`
- `web/firebase-messaging-sw.js` removed from git tracking, added to `.gitignore`
- `lib/core/config/firebase_web_config.dart` — hardcoded key replaced with `String.fromEnvironment('FIREBASE_WEB_API_KEY')`
- `web/firebase-messaging-sw.js.template` created — placeholder `{{FIREBASE_WEB_API_KEY}}` substituted at build time
- `scripts/build_web.sh` created — loads `.env.local`, generates service worker, runs `flutter build web`
- `.env.local.example` created as setup reference
- Web API key restricted in Google Cloud Console: HTTP referrers (Firebase Hosting domains only) + 8 Firebase APIs only

### Gitignored secrets (must be present locally — never commit)
| File | How to obtain |
|------|--------------|
| `android/app/google-services.json` | Firebase Console → Project Settings → Android app → Download |
| `ios/Runner/GoogleService-Info.plist` | Firebase Console → Project Settings → iOS app → Download |
| `web/firebase-messaging-sw.js` | Auto-generated by `scripts/build_web.sh` |
| `.env.local` | Copy `.env.local.example`, set `FIREBASE_WEB_API_KEY` |
| `lib/core/config/env.dart` | Manually created — contains Supabase URL + anon key |

### Running web locally
```bash
# Full build (generates service worker + builds)
bash scripts/build_web.sh

# Debug run only (service worker must already exist locally)
flutter run -d chrome --dart-define=FIREBASE_WEB_API_KEY=<your_key>
```

### Releasing / deploying web
Every web release MUST go through these steps in order — never run `flutter build web` or `firebase deploy` directly without generating the service worker first, or FCM push notifications will break.

```bash
# Step 1 — ensure .env.local exists with the real key
cat .env.local   # should show FIREBASE_WEB_API_KEY=...

# Step 2 — build (generates firebase-messaging-sw.js + flutter build web)
bash scripts/build_web.sh

# Step 3 — deploy to Firebase Hosting
firebase deploy --only hosting
```

After deploying, verify:
- App loads at your Firebase Hosting URL
- No Firebase errors in browser console (F12)
- Send a test FCM message from Firebase Console → Engage → Messaging → Send test message

### Firebase web API key restriction (Google Cloud Console)
Allowed APIs: FCM Registration, Firebase Installations, Firebase Hosting, Identity Toolkit, Token Service, Cloud Logging, Firebase App Check, Firebase In-App Messaging.
Allowed referrers: Firebase Hosting domains only.
Verified working: `curl` from outside allowed domain returns `403 PERMISSION_DENIED / API_KEY_HTTP_REFERRER_BLOCKED`.

---

## Working Rules

- Read this file before changing video feed layout, startup/auth persistence, navigation, or notification behavior.
- Update this file after every significant change without waiting to be asked.
- Never commit `google-services.json`, `GoogleService-Info.plist`, `firebase-messaging-sw.js`, `.env.local`, or `env.dart`.
