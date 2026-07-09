# Family Tracker — Session Changelog

Generated: 2026-07-09  
Scope: Bug fixes (BUG-3, BUG-4, BUG-5, BUG-6) + Enhancements (Crash Reporting, Geofence History & Analytics, Location Sharing Links, Activity Detection) + Documentation, plus live debugging of server startup, build, and device re-registration issues.

---

## Commits This Session

| SHA | Title |
|---|---|
| `41e9323` | Fix: scan NULL `last_activity` into `*string` + expose activity in `/admin/devices` |
| `5428b5c` | Enhancement: Documentation |
| `f53690f` | Enhancement: Activity Detection |
| `6b584b4` | Enhancement: Location Sharing Links |
| `dc1a1b3` | Enhancement: Geofence History & Analytics |
| `a6ac328` | Enhancement: Crash Reporting (admin app + reporter) |
| `24bf4e0` | Batch 2 (partial): PERF-1 pagination + SEC-6 client-side name validation |
| `50c3e93` | Fix Pending screen crash: use mutable list instead of `const []` |
| `3953dd8` | Fix `InsertPendingDevice`: cast CASE branches to `approval_status` enum so removed devices can re-register |

---

## Bug Fixes Implemented

### BUG-3 — Live-mode locate interruption
- **Files:** `apps/reporter/.../service/LocationForegroundService.kt`
- **Fix:** When a `locate` intent arrives while already in LIVE mode, the service now posts a single position without stopping live tracking. FCM `live` commands are ignored while already live (`stopAfter = false` branch).

### BUG-4 — Silent FCM failure
- **Files:** `apps/admin_app/lib/main.dart`, `apps/admin_app/lib/services/fcm_service.dart`
- **Fix:** `registerTokenWithRelay` records `lastError`; the About screen shows push-notification status with a retry button; the relay also re-pushes the FCM token on every poll cycle.

### BUG-5 — Orphaned Traccar device on approve failure
- **Files:** `services/notify_relay/internal/http/handlers.go`, `services/notify_relay/internal/store/postgres.go`
- **Fix:** `approve` now rolls back the Traccar device (`DeleteDevice`) if `ApprovePendingDeviceWithMeta` fails, preventing orphaned Traccar rows.

### BUG-6 — Refresh spam / unbounded concurrent refreshes
- **Files:** `apps/admin_app/lib/state/devices_controller.dart`, `apps/admin_app/lib/screens/home_screen.dart`
- **Fix:** `DevicesController` adds a 60s throttle + `_refreshing` concurrency guard; the pending auto-refresh timer was bumped 5s → 30s.

---

## Enhancements Implemented

### Crash Reporting
- **Admin app** (`apps/admin_app/lib/services/crash_reporter.dart` + `crash_log_screen.dart`):
  - `CrashReporter` hooks `FlutterError.onError` and `PlatformDispatcher.onError`, writes errors to a rotating JSONL file, and exposes them in-app via About → Troubleshooting → Crash & Error Logs.
  - Share crash logs via `share_plus`.
- **Reporter** (`apps/reporter/app/src/main/kotlin/com/familytracker/reporter/ReporterApp.kt`):
  - Process-wide uncaught-exception handler writing to `filesDir/crash/crash_log.txt`, registered as `Application` in the manifest.

### Geofence History & Analytics
- **Schema / store** (`deploy/docker/postgres-init/02_relay_schema.sql`, `services/notify_relay/internal/store/postgres.go`):
  - New `geofence_events` table with indexes; `EnsureSchema` creates it at startup for existing deployments.
  - `RecordGeofenceEvent`, `ListGeofenceEvents` (paginated), `GeofenceEventStats`.
- **Relay** (`services/notify_relay/internal/http/handlers.go`):
  - `traccarWebhook` persists `geofenceEnter`/`geofenceExit` events.
  - `GET /admin/geofence-events` (paginated) + `GET /admin/geofence-stats`.
- **Admin app** (`apps/admin_app/lib/models/geofence_event.dart`, `state/geofence_history_controller.dart`, `screens/geofence_history_screen.dart`, `screens/home_screen.dart`):
  - New Geofence History screen (menu item) showing recent events + an analytics card.

### Location Sharing Links
- **Schema / store**: New `share_links` table.
- **Relay** (`handlers.go`):
  - `POST /admin/share` (create), `GET /admin/share` (list), `DELETE /admin/share/{token}` (revoke).
  - Public `GET /share/{token}` returning device name + latest position from Traccar (`GetLatestPosition` added to `traccar/client.go`).
- **Admin app** (`lib/models/share_link.dart`, `api/relay_api.dart`, `screens/device_detail_sheet.dart`):
  - "Share location" action in device detail sheet creates a link and shares the URL.

### Activity Detection
- **Reporter** (`apps/reporter/app/src/main/kotlin/com/familytracker/reporter/...`):
  - `ActivityRecognitionClient` in `LocationForegroundService` requests ~30s activity updates delivered to `ActivityReceiver` (BroadcastReceiver registered in manifest).
  - `ActivityReceiver` filters by confidence (≥40%) and reports via `RelayClient.reportActivity`.
- **Relay** (`internal/store/postgres.go`, `internal/http/handlers.go`):
  - `reporter_device_meta.last_activity` text column; `SetDeviceActivityByToken`; `POST /api/device/activity` (ingest-token auth).
- **Admin app** (`packages/tracker_core/lib/models/approved_device.dart`, `apps/admin_app/lib/models/device_view.dart`, `device_detail_sheet.dart`):
  - Activity row shown in device detail sheet with friendly labels.

### Pagination (PERF-1)
- Relay `ListPending` and `ListApprovedDevices` accept `limit`/`offset`, return `{items, total, limit, offset}` envelopes.
- Admin `RelayApi` + `PendingController` + `DevicesController` consume pagination; `loadMore()` added to `PendingController`.

### Input Validation (SEC-6)
- Server-side: device-name cap at 100 chars enforced in `approve` and `renameByTraccarId` handlers.
- Client-side: `device_detail_sheet.dart` rename dialog and `pending_screen.dart` approval dialog validate length client-side.

---

## Bugs / Issues We Encountered During This Session (Fixed)

| Issue | Root Cause | Fix |
|---|---|---|
| Android listener crash: `Cannot add to an unmodifiable list` | `pending_controller.dart` used `const []` then called `addAll()` | Changed to mutable `[]` (commit `50c3e93`) |
| Share link crash: `type 'Null' is not a subtype of type 'int'` | Go returned key `"deviceId"` but Dart expected `"traccarDeviceId"` | Fixed Go response key (`41e9323`) |
| `INSERT ... CASE status` SQL error | `CASE` produced `text` but column is enum `approval_status` | Cast branches with `::approval_status` (`3953dd8`) |
| `EnsureSchema` "must be owner of table" | Relay connected as `relay_user` (non-owner) | User switched `DATABASE_URL` to postgres superuser |
| `ListApprovedDevices: cannot scan NULL into *string` | `last_activity` is nullable but scanned into non-pointer `string` | Changed `ApprovedDeviceRow.Activity` to `*string` (`41e9323`) |

---

## Documentation Updated
- `Family Tracker Project.md` updated to document all new components, bug fixes this session, and next-session priorities.

---

## Current State / Pending

- The reporter currently shows **"Device removed"** for your own device. To re-add it from the reporter without rebuilding:
  ```bash
  adb shell pm clear com.familytracker.reporter
  adb shell am start -n com.familytracker.reporter/.ui.MainActivity
  ```
  With the relay fix (`3953dd8`), re-registration now succeeds; the device will reappear in the admin **Pending** tab for re-approval.
- Admin APK is installed (`57.3 MB` release build).
- Reporter APK is installed (debug build, ABI split `app-arm64-v8a-debug.apk`).
- Relays runs on `:8080`, Postgres on `127.0.0.1:5432`, Traccar on `8082`/`5055`.
- The Kotlin Activity Detection code contains a non-fatal Elvis warning in `ActivityReceiver.kt` (already cleaned up in this session).

---

## How to Run (Reminder)

### Relay
```bash
cd /home/dev/family-tracker/services/notify_relay
set -a && source ../../.env.relay && set +a
export DATABASE_URL='postgres://postgres:hSy1ht9ZAxCHRjA4AlyYsbtex57PrHZJKMTPw1lCS0s=@localhost/postgres?search_path=relay&sslmode=disable'
go run ./cmd/server
```

### Admin app rebuild (if needed)
```bash
cd /home/dev/family-tracker/apps/admin_app
flutter build apk --release
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

### Reporter rebuild (if needed)
```bash
cd /home/dev/family-tracker/apps/reporter
./gradlew assembleDebug
adb install -r app/build/outputs/apk/debug/app-arm64-v8a-debug.apk
```

---

## Notes
- Reporter `Config.kt` hardcodes `RELAY_BASE_URL` to `http://192.168.1.35:8080`; change + rebuild if your machine uses a different LAN IP.
- FCM is optional — unset `FCM_SERVICE_ACCOUNT_JSON` to run without push notifications.
