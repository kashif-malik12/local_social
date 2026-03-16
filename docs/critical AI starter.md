# CRITICAL — Read This Before Doing Anything

> **IMPORTANT: Always read this file at the start of every session before making any changes to this project.**

This file must be read at the start of every session before making any changes to this project.

---

## Web Release Process

Every web release MUST go through these steps in order. Never run `flutter build web` or `firebase deploy` directly — always use the build script or FCM push notifications will silently break.

```bash
# Step 1 — ensure .env.local exists with the real key
cat .env.local   # should show FIREBASE_WEB_API_KEY=...

# Step 2 — build + deploy to VPS in one command
bash scripts/build_web.sh --deploy

# Build only (no deploy)
bash scripts/build_web.sh
```

Web is hosted on VPS at `deploy@87.106.13.170:/var/www/local_social_web/`, served by **Caddy** at `https://app.allonssy.com`.
Firebase is used only for **FCM push notifications** and **in-app messaging** — NOT for hosting.

After deploying, verify:
- App loads at https://app.allonssy.com
- No Firebase errors in browser console (F12)
- Send a test FCM message from Firebase Console → Engage → Messaging → Send test message

---

## Files That Must NEVER Be Committed

| File | Reason |
|------|--------|
| `android/app/google-services.json` | Contains Android Firebase API key |
| `ios/Runner/GoogleService-Info.plist` | Contains iOS Firebase API key |
| `web/firebase-messaging-sw.js` | Generated at build time — contains web API key |
| `.env.local` | Contains `FIREBASE_WEB_API_KEY` |
| `lib/core/config/env.dart` | Contains Supabase URL + anon key |

These are all gitignored. If git ever shows them as untracked or modified, do NOT stage them.

---

## Local Setup (New Machine or Fresh Clone)

1. Copy `.env.local.example` → `.env.local` and fill in `FIREBASE_WEB_API_KEY`
2. Download `google-services.json` from Firebase Console → Project Settings → Android app → place at `android/app/google-services.json`
3. Download `GoogleService-Info.plist` from Firebase Console → Project Settings → iOS app → place at `ios/Runner/GoogleService-Info.plist`
4. Run `bash scripts/build_web.sh` once to generate `web/firebase-messaging-sw.js`
5. Create `lib/core/config/env.dart` with Supabase credentials

---

## Firebase API Key Restrictions

The web API key is restricted in Google Cloud Console to:
- **HTTP referrers**: Firebase Hosting domains only
- **APIs**: FCM Registration, Firebase Installations, Firebase Hosting, Identity Toolkit, Token Service, Cloud Logging, Firebase App Check, Firebase In-App Messaging

Do not add new APIs to the key without documenting it here and in `decision_log.md`.

---

## Key Reference Files

| File | Purpose |
|------|---------|
| `docs/decision_log.md` | Full project decisions and technical context |
| `docs/critical AI starter.md` | This file — rules and release process |
| `scripts/build_web.sh` | Web build + service worker generation |
| `.env.local.example` | Template for local environment setup |
