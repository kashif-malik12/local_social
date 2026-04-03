# Play Store Release Pack

## Release Status

- App is live on Google Play internal testing track.
- Android release signing uses the dedicated upload keystore at `android/allonssy-upload-keystore.jks` (gitignored — back up securely).
- Google Play App Signing is active — Google re-signs the AAB with their own delivery certificate. SHA-1 and SHA-256 fingerprints for both the upload keystore and the Play Store delivery certificate must be registered in Google Cloud Console (Android OAuth client) and Firebase.

### SHA keys registered

| Certificate | SHA-1 | SHA-256 | Registered in |
|-------------|-------|---------|---------------|
| Debug keystore | `BB:E5:B1:A4:01:7C:10:A1:37:BA:03:15:34:E4:ED:87:D3:D5:AE:F8` | — | Firebase (debug builds) |
| Upload keystore | — | `46:D4:62:90:E1:98:25:4E:E1:0C:D2:87:20:54:59:8B:00:45:E8:AC:9D:D8:73:18:BD:CE:DE:67:DD:79:52:05` | `assetlinks.json` |
| Play Store delivery | (from Play Console) | (from Play Console) | Google Cloud Console Android OAuth + Firebase |

---

## App Identity

- App name: `Allonssy!`
- Package name: `com.allonssy.app`
- Website: `https://app.allonssy.com`
- Company: `Tradister SAS`
- Location: `Ris-Orangis, France`

---

## Short Description

Use this in Google Play short description:

`Local social network for nearby posts, marketplace deals, gigs, food and chat.`

Alternative:

`Discover nearby posts, local deals, services, food ads and community chat.`

---

## Full Description

Use this as the main Play Store description:

`Allonssy is a local community app built to help people connect, share and discover what is happening nearby.

Follow local posts, browse marketplace listings, find services, explore food ads and chat directly inside one app.

With Allonssy you can:

- share updates with people near you
- discover local marketplace offers
- post or browse gigs and services
- explore food listings and nearby businesses
- follow people, businesses and organizations
- chat directly about posts and offers
- control your app language in English or French

Allonssy is designed for real local communities, with location-aware discovery, profile-based preferences and fast access to the content that matters around you.

Key features:

- Local feed with nearby posts
- Marketplace for products and offers
- Gigs and services listings
- Food ads and local business discovery
- Direct chat and offer conversations
- English and French app language support
- Shareable listing links
- Privacy, safety and moderation controls

Whether you want to buy, sell, promote a service, share local news or stay connected with people around you, Allonssy gives you one place to do it.

Join your local network with Allonssy.`

---

## Screenshot Plan

Google Play should show the clearest user value first. Do not use old screenshots with outdated labels like `Local Feed`.

Recommended phone screenshot order:

1. Local feed
   Caption: `See what is happening near you`

2. Marketplace
   Caption: `Buy and sell in your area`

3. Gigs / services
   Caption: `Find local services and opportunities`

4. Food listings
   Caption: `Explore food and nearby places`

5. Chat / offers
   Caption: `Message directly and manage offers`

6. Profile / settings / language
   Caption: `Use Allonssy in French or English`

Optional extra screenshots:

7. Search
   Caption: `Search posts and profiles nearby`

8. Notifications
   Caption: `Stay updated in real time`

---

## Screenshot Requirements

For Play Store phone screenshots, prefer:

- Portrait
- Clean data
- Consistent status bar
- No debug banners
- Real Allonssy branding
- At least one screenshot showing French UI
- At least one screenshot showing marketplace or gigs

Avoid:

- Empty states unless they look intentional
- Placeholder/demo text that looks fake
- Mixed old branding
- Debug/dev visual artifacts

---

## Capture Checklist

Before taking screenshots:

- Use a release-like build, not a debug banner build
- Make sure app title/branding says `Allonssy`
- Use polished demo accounts and realistic listings
- Keep location data valid and consistent
- Turn on the strongest screens: feed, marketplace, gigs, food, chat
- Capture one screenshot with French selected in profile language

---

## Version History

| Version | Build | Date | Notes |
|---------|-------|------|-------|
| 1.0.1+2 | 2 | 2026-03-19 | Google Sign-In SHA fix for Play Store (Play Store delivery SHA-1 added to Google Cloud Console Android OAuth, SHA-256 to Firebase). Debug SHA-1 added as a second Android OAuth client. |
| 1.0.2+3 | 3 | 2026-03-19 | French translations for marketplace/gigs/foods/restaurants/businesses categories, post types, create post launcher, detail screens. Chat read receipt ticks + timestamps. Banned emails admin feature. |
| 1.0.3+4 | 4 | 2026-03-19 | Fixed app name showing "Allonssy" instead of "Allonssy!" after install (restored `android:label="Allonssy!"`). |
| 1.1.0+5 | 5 | 2026-04-03 | Emoji picker in chat, offer chat, comments, and create post. Message reply (long-press → reply with quoted bubble). Message likes (long-press → ❤️). **First production release.** |

---

## Play Store Reviewer Test Account

Created 2026-04-03 for Play Console App Access / Google review.

| Field | Value |
|-------|-------|
| Email | `reviewer@allonssy.com` |
| Password | `AllonssyReview2026!` |
| Name | Allonssy Reviewer |
| City | Évry, France |
| Coordinates | 48.6239, 2.4283 |
| Language | English |
| Auth user ID | `129866d5-95f6-4df0-b53e-cc447f099c56` |

Profile is pre-completed — reviewer lands directly on the feed. Do not delete this account.

---

## Release Checklist (for future releases)

1. Bump `version` in `pubspec.yaml` (name+number).
2. Build: `flutter build appbundle --release`
3. Commit + push.
4. Go to Play Console → Internal testing → Create new release → Upload `.aab`.
5. Add release notes → Save → Review → Start rollout.

AAB output: `build/app/outputs/bundle/release/app-release.aab`

---

## Recommendation

Roll out new versions to internal testing first, then promote to production once verified on device.
