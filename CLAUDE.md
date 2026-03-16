# local_social — Project Context for Claude

> **IMPORTANT: Always read `docs/critical AI starter.md` before doing anything in this project.**

## Overview
A Flutter social media app for local communities. Built with Supabase as the backend. Originally developed with Codex CLI; migrated to Claude Code on 2026-03-11.

## Tech Stack
- **Flutter** 3.x / Dart SDK ^3.10.3
- **State management**: flutter_riverpod ^2.5.1
- **Routing**: go_router ^14.2.0
- **Backend**: Supabase (auth, database, storage, realtime)
- **Media**: flutter_image_compress, ffmpeg_kit_flutter_new, video_player
- **Other**: shared_preferences, image_picker, geocoding, file_picker, youtube_player_iframe

## Project Structure
```
lib/
  main.dart               # App entry point, Supabase init, Android release auth workaround
  app/
    app.dart              # Root MaterialApp + GoRouter setup
    router.dart           # All route definitions
    chat_singletons.dart  # Chat singleton services
  core/
    config/env.dart       # Supabase URL + anon key (not committed)
    utils/               # Shared utilities
  features/
    auth/                 # Login, register, forgot/reset password screens
    chat/                 # Chat list, chat screen, offer chat, services
    home/                 # Home tab
    moderation/           # Admin review screen
    notifications/        # Notification settings
    profile/              # Profile detail, complete profile, settings, follow list
  screens/                # Flat screens (feed, search, comments, marketplace, etc.)
  services/               # Shared services (post, reaction, follow, mention, etc.)
  widgets/                # Shared widgets (post card, video feed, global nav, etc.)
supabase/
  migrations/             # SQL migrations (timestamped)
```

## Key Files
| File | Purpose |
|------|---------|
| `lib/core/config/env.dart` | Supabase credentials — never commit |
| `lib/core/config/firebase_web_config.dart` | Firebase web config — uses `String.fromEnvironment()`, no secrets in source |
| `lib/app/router.dart` | All GoRouter routes |
| `lib/screens/feed_screen.dart` | Main social feed (large, ~3471 lines) |
| `lib/screens/create_post_screen.dart` | Post creation |
| `lib/services/post_service.dart` | Post CRUD + media upload |
| `lib/services/reaction_service.dart` | Likes/reactions |
| `lib/features/chat/` | Full chat feature with offer chat |
| `lib/widgets/mobile_video_feed.dart` | TikTok-style video feed widget |
| `web/firebase-messaging-sw.js.template` | FCM service worker template — generated into `firebase-messaging-sw.js` at build time |
| `scripts/build_web.sh` | Web build script — loads `.env.local`, generates service worker, runs flutter build web |

## Database (Supabase)
- Tables: `profiles`, `posts`, `comments`, `reactions`, `conversations`, `messages`, `follows`, `blocks`, `reports`
- Storage buckets: `avatars`, `post-images`
- RPC functions: `search_profiles`, `search_profiles_nearby`, `search_posts_scoped`, `search_posts_nearby_scoped`
- Realtime: used for feed posts, notifications, chat messages

## Flutter Analyze Status (as of 2026-03-11)
- **Before cleanup**: 140 issues, ~12 warnings
- **After cleanup**: 125 issues, 1 warning
- Remaining warning: `_buildQaPreview` unused in `feed_screen.dart:3031` — intentionally left (removing cascades into larger dead-code chain)
- Remaining infos: `withOpacity` deprecations (use `.withValues()`), BuildContext async gaps, control_flow_in_finally

## What Was Cleaned (2026-03-11)
- Removed unused imports: `dart:typed_data` (chat_attachment_service, profile_service), `package:flutter/foundation.dart` (profile_service), `chat_user_actions.dart` (offer_chat_screen), `dart:io` (profile_service)
- Removed unused methods: `_imageContentType` (chat_attachment_service), `_contentTypeFromExt` (profile_service, post_service), `_buildUserManagement` + `_buildUserManagementV2` (admin_review_screen), `_followRequestsButtonWithBadge` (profile_detail_screen), `_buildSearchControls` (search_screen)
- Removed unused fields/variables: `_otherUserId` (offer_chat_screen), `isOwner` (comments_screen, food_ad_detail_screen)

## Firebase / Secrets Setup

### Gitignored files (must be present locally — never commit)
| File | How to obtain |
|------|--------------|
| `android/app/google-services.json` | Download from Firebase Console → Project Settings → Android app |
| `ios/Runner/GoogleService-Info.plist` | Download from Firebase Console → Project Settings → iOS app |
| `web/firebase-messaging-sw.js` | Generated automatically by `scripts/build_web.sh` from the template |
| `.env.local` | Copy `.env.local.example` and fill in values |
| `lib/core/config/env.dart` | Manually created — contains Supabase URL + anon key |

### `.env.local` required keys
```
FIREBASE_WEB_API_KEY=<from Google Cloud Console → APIs & Services → Credentials>
```

### Running web locally
```bash
# Generate service worker + build
bash scripts/build_web.sh

# Or debug run (service worker already generated)
flutter run -d chrome --dart-define=FIREBASE_WEB_API_KEY=<your_key>
```

### Firebase API key restrictions (Google Cloud Console)
The web API key is restricted to:
- HTTP referrers: Firebase Hosting domains only
- APIs: FCM Registration, Firebase Installations, Firebase Hosting, Identity Toolkit, Token Service, Cloud Logging, Firebase App Check, Firebase In-App Messaging

## Known Issues / TODOs
- `withOpacity` deprecated throughout — replace with `.withValues(alpha: x)` gradually
- `BuildContext` across async gaps — several screens need `mounted` guards
- `control_flow_in_finally` — `return` inside `finally` in businesses_screen, feed_screen, report sheets
- `Radio` widget deprecations (`groupValue`, `onChanged`) in create_post_screen — migrate to `RadioGroup`
- `flutter_web_plugins` used in main.dart but not listed in pubspec dependencies

## Memory & Decision Log

- **`docs/decision_log.md`** is the single source of truth for all project decisions, technical context, and session memory.
- After every significant change (architecture, Android build, media flow, navigation, etc.), update `docs/decision_log.md` immediately — do not wait to be asked.

## Changelog
| Date | Description |
|------|-------------|
| 2026-03-11 | Initial Claude Code session. Ran `flutter analyze`, cleaned 12 warnings → 1 warning. Created CLAUDE.md. |
| 2026-03-11 | Fixed all 10 BuildContext-across-async-gaps issues. Pattern: capture `ScaffoldMessenger.of(context)` before awaits; add `if (!mounted) return` after awaits; use `ctx.mounted` for dialog contexts. Issues: 140→115. |
| 2026-03-16 | Security: rotated exposed Firebase API keys (were public in git). Gitignored `google-services.json` and `firebase-messaging-sw.js`. Moved web key to `String.fromEnvironment()` + build-time injection via `scripts/build_web.sh`. Applied HTTP referrer + API restrictions in Google Cloud Console. |
