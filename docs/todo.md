# TODO

## Unread Badge Streams — Optimize Realtime Scope

**File**: `lib/features/chat/services/unread_badge_controller.dart`

The two realtime streams that power the unread chat badge listen to the entire `messages` and `offer_messages` tables with no user filter. Every message sent by any user in the app triggers an RPC refresh call on every logged-in device.

**Fix**: Scope the realtime subscriptions to only the current user's conversations, e.g. filter by `conversation_id` in the user's conversation list, or use a Postgres `filter` on the channel so only relevant rows trigger the listener.

**Priority**: Low now, but will degrade battery and backend load as user base grows.

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
