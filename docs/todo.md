# TODO

## iOS Universal Links — Complete Setup When iOS Release Is Ready

**Files**: `ios/Runner/Runner.entitlements`, `web/.well-known/apple-app-site-association`

The entitlements file is in place but two manual steps remain before iOS share links open the native app:

1. **Xcode**: Open `ios/Runner.xcodeproj` → Runner target → Signing & Capabilities → add **Associated Domains** capability with `applinks:app.allonssy.com`. Xcode will link the existing `.entitlements` file automatically.
2. **Team ID**: Replace `REPLACE_WITH_TEAM_ID` in `web/.well-known/apple-app-site-association` with the Apple Team ID from developer.apple.com, then redeploy: `scp web/.well-known/apple-app-site-association deploy@87.106.13.170:/var/www/local_social_web/.well-known/apple-app-site-association`

Until done, iOS share links open in the mobile browser (web app) instead of the native app — which still works, just not as seamless.

**Priority**: Before iOS App Store release.

---

## Critical Alerting - Re-enable Memory Threshold Later

**File**: `scripts/critical_server_alert.py`

The low-available-memory critical alert was intentionally disabled while the app runs on the small test VPS (`2 vCPU / 4 GB RAM`). On this box it would generate noisy alerts continuously and reduce signal quality.

**Fix later**: Re-enable the available-memory threshold check once the backend is moved back to a larger production-sized VPS. At that point, low free memory becomes a meaningful critical signal again.

**Priority**: Medium before launch infrastructure cutover.

## Critical Alerting - Re-enable Load Threshold Later

**File**: `scripts/critical_server_alert.py`

The load-average critical alert was intentionally disabled while the app runs on the small test VPS (`2 vCPU / 4 GB RAM`). On this box short CPU bursts from Docker, backups, deploys, or admin activity create noisy alerts without indicating a real outage.

**Fix later**: Re-enable load-based critical alerting once the backend is moved to the larger production VPS, ideally with either a higher threshold or repeated-failure logic instead of a single sample.

**Priority**: Medium before launch infrastructure cutover.
