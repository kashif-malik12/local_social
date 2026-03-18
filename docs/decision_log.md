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
- App UI language is stored in `profiles.app_language` with allowed values `en` and `fr`.
- The app locale is now driven at startup and after profile saves by `lib/core/localization/app_locale_controller.dart`, so Flutter mobile and Flutter web switch language from the same profile-backed preference.
- The language selector lives in `lib/features/profile/presentation/complete_profile_screen.dart` and must remain available in both complete-profile and edit-profile flows.
- Logged-out/auth screens default to French via `app_locale_controller.dart`; signed-in users still use their saved profile preference.
- Current translated surfaces include the shared navigation/app bar, complete/edit profile, profile settings, main profile detail actions/portfolio UI, auth screens, notifications, create-post, and quick-camera-post flows. User-generated post/comment content must remain in its original language and is not translated by the app.

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
- Unread badge streams in `unread_badge_controller.dart` listen to the entire `messages` and `offer_messages` tables unfiltered — every message from any user triggers an RPC call. Low priority now but will degrade at scale. (See `todo.md`)

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
# Debug run only (service worker must already exist locally)
flutter run -d chrome --dart-define=FIREBASE_WEB_API_KEY=<your_key>
```

### Releasing / deploying web
Web is hosted on VPS at `deploy@87.106.13.170:/var/www/local_social_web/`, served by **Caddy v2** at `https://app.allonssy.com`. Firebase is used only for FCM and in-app messaging — NOT for hosting.

Every web release MUST go through the build script — never run `flutter build web` directly or the service worker won't be generated and FCM will break.

```bash
# Build + deploy in one command
bash scripts/build_web.sh --deploy

# Build only (no deploy)
bash scripts/build_web.sh
```

After deploying, verify:
- App loads at https://app.allonssy.com
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

---

## Docs Organization

---

## Localization Expansion

- As of 2026-03-16, fixed-text localization was extended further across `search_screen.dart` and `feed_screen.dart`.
- Search UI labels, filters, empty states, and fixed result metadata now follow the profile-backed app language.
- Feed translation now covers filter controls, share/status messages, desktop sidebars, top-trending cards, profile completeness cards, and feed error/open-original actions.
- User-generated content remains in its original language and is not auto-translated.
- Browse/list screens for marketplace, gigs, foods, businesses, and restaurants now localize their fixed titles, search/filter controls, sort labels, CTA buttons, and empty/error states.
- As of 2026-03-17, French is the default app language across logged-out/auth flows and as the fallback for profile-backed locale resolution. The language selector remains in `lib/features/profile/presentation/complete_profile_screen.dart`; it is not part of `profile_settings_screen.dart`.
- The `profiles.app_language` migration default/backfill was corrected to `fr`, and remaining localization call sites were aligned to `tr(..., args: ...)` to match the custom localization API.

- As of 2026-03-16, all repository Markdown files were consolidated under `docs/`.
- Moved files: root `README.md` → `docs/README.md`, root `CLAUDE.md` → `docs/CLAUDE.md`, `ios/Runner/Assets.xcassets/LaunchImage.imageset/README.md` → `docs/ios_launch_screen_assets.md`.

---

## Feed UX Changes (2026-03-18)

### Collapsible filters — marketplace & gigs
- Both `marketplace_screen.dart` and `gigs_screen.dart` now use an `AnimatedSize`-wrapped collapsible filter panel toggled by an `ActionChip` that shows an active-filter count badge. A "Clear" `TextButton` resets all filters. Previously filters were always visible and took excessive vertical space.

### Video feed — single feed-level mute
- Removed per-video mute toggle from `NetworkVideoPlayer` when used inside the video feed.
- Added a single `_feedMuted` bool in `mobile_video_feed.dart`. All videos in the feed share this state via the `muted:` prop on `NetworkVideoPlayer`.
- `NetworkVideoPlayer` gained a `final bool? muted` prop and a `didUpdateWidget` override that syncs the external mute state to the controller volume.

### Video feed — gradient tap-through fix
- The gradient `DecoratedBox` overlay in `mobile_video_feed.dart` was absorbing all pointer events, blocking pause/mute taps. Fixed by wrapping it in `IgnorePointer`.

### Video feed — pull-to-refresh
- Pull-down refresh on first video: uses `PageController.addListener` reading `position.pixels < 0`. Threshold is 80 logical pixels of drag. Shows an arrow indicator → spinner on trigger.
- End-of-feed refresh button rendered in the same outer `Stack` at the bottom of the last card.
- `BouncingScrollPhysics(parent: PageScrollPhysics())` enables overscroll on the vertical `PageView`.

### Main feed — deferred media loading
- Each feed card is wrapped in `VisibilityDetector` with a 50% visibility threshold. Media (photo/video) is only rendered when the card is at least half visible.
- Replaced scroll-position estimate with a `Set<int> _visiblePostIndices` updated per card.

### Main feed — quick session filters
- Session-only filter chips: All, Marketplace, Gigs, Food, Lost & Found, Organization.
- Only chips for enabled post types appear (driven by the same feature-flag booleans used by the rest of the feed).
- Mobile: hidden pill toggle near the bottom nav; tapping opens an animated chip overlay. Web: always-visible bar above the feed.
- State is not persisted — resets to "All" on every app start.
- Filter popup had a white `Container` background removed; chips now float transparently over the feed.

### Main feed & video feed — FAB visibility
- FABs (post button + scroll-to-top) are hidden when the user is on the video feed page (`_mobileFeedPage == 1`).

---

## Sharing Module (2026-03-18)

### Overview
Listing share links for marketplace products, gigs, and food ads. Share button appears only on the three detail pages — not on feed cards.

### Share URLs
| Type | URL pattern |
|------|-------------|
| Product | `https://app.allonssy.com/marketplace/product/{id}` |
| Gig | `https://app.allonssy.com/gigs/service/{id}` |
| Food | `https://app.allonssy.com/foods/{id}` |

### Widget (`lib/widgets/share_button.dart`)
- `ShareButton` — icon button (`Icons.share_outlined`) placed in the app bar `actions`.
  - Mobile (Android/iOS): opens native OS share sheet via `share_plus`.
  - Web (mobile browser): uses Web Share API via `share_plus`.
  - Web (desktop/unsupported browsers): falls back to `Clipboard.setData` + snackbar "Link copied".
- `ShareSheet` — optional bottom-sheet variant (copy + native share) for future use.
- Helper functions: `marketplaceShareUrl()`, `gigShareUrl()`, `foodShareUrl()`.

### Detail screens updated
`marketplace_product_detail_screen.dart`, `gig_detail_screen.dart`, `food_ad_detail_screen.dart` — `GlobalAppBar` now receives `actions: [ShareButton(...)]` when the post is loaded. The `const` keyword was removed from the `GlobalAppBar` constructor call.

### Dynamic routing (desktop vs mobile vs app)
Links are plain HTTPS URLs pointing to the web app:
- **Desktop browser** → opens web app directly.
- **Android (app installed)** → Android App Links intercept → opens native app at the correct route.
- **Android (no app)** → opens mobile browser → loads web app.
- **iOS (app installed)** → Universal Links intercept → opens native app at the correct route.
- **iOS (no app)** → opens mobile browser → loads web app.

### Android App Links
Three `<intent-filter android:autoVerify="true">` blocks added to `AndroidManifest.xml` with `pathPrefix`:
- `/marketplace/product`
- `/gigs/service`
- `/foods`

Verification file: `web/.well-known/assetlinks.json` — SHA-256 fingerprint is populated from the debug keystore (release build currently uses `signingConfig = signingConfigs.getByName("debug")`).
SHA-256: `7A:70:86:F0:EC:30:94:64:FB:40:02:14:95:11:74:99:B4:F6:2F:F5:80:6E:DE:89:21:72:8F:6F:49:0D:D0:A9`
**If a dedicated release keystore is added later**, update `assetlinks.json` with the new fingerprint and redeploy web.

### iOS Universal Links
`ios/Runner/Runner.entitlements` created with `com.apple.developer.associated-domains` → `applinks:app.allonssy.com`.
**Requires linking in Xcode**: Open `ios/Runner.xcodeproj` → Runner target → Signing & Capabilities → + Capability → Associated Domains. Xcode will use the `.entitlements` file automatically once linked.

Verification file: `web/.well-known/apple-app-site-association` — **requires Apple Team ID** (placeholder `REPLACE_WITH_TEAM_ID`).
Find it in Apple Developer Portal → Membership. Replace and redeploy.

### Server
Caddy (`/etc/caddy/Caddyfile`) updated with:
- `handle /.well-known/apple-app-site-association` → serves with `Content-Type: application/json` (required by iOS, file has no extension).
- `handle /.well-known/*` → serves other well-known files statically.
- Both placed before the `try_files → index.html` catch-all handler.
Both `.well-known` files are deployed as part of `flutter build web` output in `web/.well-known/`.

### Package added
`share_plus: ^10.1.4` added to `pubspec.yaml`.

---

## Legal Pages — About Us, Terms & Conditions, Privacy Policy (2026-03-18)

### Routes
Three new public routes added to `router.dart` — no authentication required:
- `/about` → `LegalScreen(page: LegalPage.about)`
- `/terms` → `LegalScreen(page: LegalPage.terms)`
- `/privacy` → `LegalScreen(page: LegalPage.privacy)`

Router redirect updated: unauthenticated users are allowed through to these routes (alongside existing `/login`, `/register`, `/forgot-password`).

### Screen
Single file: `lib/screens/legal_screen.dart` with a `LegalPage` enum (`about`, `terms`, `privacy`). The screen has no `GlobalBottomNav` (intentionally — works without a session). Content is entirely inline.

### Content
| Page | Key details |
|------|-------------|
| About Us | Allonssy platform intro; Tradister SAS; SIREN 988 318 945; Ris-Orangis, France; hello@allonssy.com |
| Terms & Conditions | Eligibility (16+), account rules, acceptable use, user content licence, marketplace disclaimer, moderation, liability limit, governing law (France) |
| Privacy Policy | GDPR-compliant; data types collected; legal bases; user rights (access, rectification, erasure, portability, objection); CNIL reference; data retention 30 days after account deletion |

### Entry Points
| Surface | How links appear |
|---------|-----------------|
| Mobile bottom nav | Account sheet — About Us / Terms / Privacy list tiles with icons, separated by a `Divider`, placed above the logout tile |
| Web app bar (≥1100 px) | "More" popup menu — About Us / Terms / Privacy items separated by `PopupMenuDivider`, placed above logout |
| Login screen | Small teal underlined links in a `Wrap` at bottom of the login card (both mobile and web) |
| Register screen | Same footer at bottom of the register card |

---

## Price Range Feature (2026-03-18)

### Overview
Marketplace and gigs posts now support an optional price range (min + max) in addition to a single price.

### Database
- Migration `supabase/migrations/20260318120000_add_market_price_max.sql` adds `market_price_max double precision` to `posts`.
- Applied to production VPS via `docker exec supabase-db psql -U postgres -d postgres`.

### Model
- `Post` model: added `final double? marketPriceMax` field mapped from `market_price_max`.

### Service
- `PostService.createPost()`: added `double? marketPriceMax` parameter, included in insert payload as `market_price_max`.

### Create post screen
- For marketplace and gigs post types only, a **Single / Range** `ChoiceChip` toggle appears above the price field.
- "Single" mode: single EUR price field (existing behavior).
- "Range" mode: two side-by-side fields — "Min price" and "Max price". Validation ensures max > min.
- Food ad posts retain a single price field; the toggle is not shown for them.
- `_marketPriceMaxCtrl` added and disposed properly. `_priceIsRange` resets when switching away from market/service post types.

### Display — price formatting rule
All five display locations use this rule:
- Both min and max present (max > min): `EUR X.XX – EUR Y.XX`
- Min only: `EUR X.XX`
- Neither: fallback label (e.g. "Price on request", "Rate on request", "Looking to buy")

### Display locations updated
| File | Change |
|------|--------|
| `lib/widgets/post_card.dart` | `_MarketListingBody` now uses `post.marketPrice` + `post.marketPriceMax` directly instead of legacy content parsing. Intent and title also read from Post model fields with content fallback. |
| `lib/screens/marketplace_screen.dart` | Grid card price label updated to show range. |
| `lib/screens/gigs_screen.dart` | Grid card price label updated to show range. |
| `lib/screens/marketplace_product_detail_screen.dart` | Detail price row updated. |
| `lib/screens/gig_detail_screen.dart` | Detail price row updated. |
