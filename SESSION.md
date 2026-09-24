# Family Tracker — Session Changelog

Generated: 2026-07-14  
Scope: v3.0 release + Ubuntu deployment setup + secrets tracking + documentation updates, plus all bug fixes and enhancements since v2.0.

---

## Session 2026-09-22 → 2026-09-23 (Windows bring-up + testing)

Live-tested the full loop on Ryzen 5 5500U laptop + Realme Narzo 30A
(`android-153aba2d511ab8fb`, Traccar device 5). Join → approve → live
tracking → ring all verified end-to-end.

### Backend fixes (relay + Postgres)
- **`/join` HTTP 500** — `relay.*` tables owned by `postgres`, `relay_user`
  had zero grants. Granted live; `deploy/docker/postgres-init/02_relay_schema.sql`
  now ends with table/sequence/type GRANTs + default privileges.
- **Approve HTTP 500 `internal error`** — `reporter_device_meta` lacked the
  `ingest_token` column the code inserts/selects (schema drift, no migration
  runner). `ALTER TABLE … ADD COLUMN ingest_token TEXT` live; column added to
  `02_relay_schema.sql` for fresh installs.
- **FCM `invalid_grant: Invalid JWT Signature`** — old service-account key
  dead server-side. New key generated in Firebase console
  (`family-tracker-df860`), installed as `secrets/fcm-service-account.json`.
  Ring/locate/live/idle all work after restart.

### Reporter app (no-rebuild server address)
- `Storage`: new `relayBaseUrl` (default `Config.RELAY_BASE_URL`) +
  `serverConfirmed` prefs.
- `RelayClient(baseUrl: () -> String)`: live provider (all 3 call sites:
  MainActivity, FcmService, LocationForegroundService) + new `checkHealth()`
  (`GET /healthz`) for validation.
- `MainActivity`: after permissions → **Server address** screen (normalize +
  health-check before save); registration connection-failure shows secondary
  **Change server** button; error text names the URL being tried.
- `Config.RELAY_BASE_URL` default follows the reserved LAN IP (`.36`).

### Admin app (Flutter)
- Offline banner overlapped header (hardcoded 72px drop) → banner + header in
  one top `Column`, no magic offset.
- Geofence save `TraccarUnauthorized` (stale JSESSIONID) → `_savePlacement`
  catches it, logs out, prompts re-sign-in.
- **Glass blur toggle** (⋮ → checked `Glass blur` item): new
  `DisplayController` (persisted) + `GlassBlur` helper gate all 6
  `BackdropFilter`s (header, pill nav, detail sheet, `_Card`, map pin card,
  geofence toast) with opaque-tint fallbacks. `flutter analyze` clean.
- Admin debug APK **not buildable on the 8 GB laptop** (Gradle OOM even at
  `-Xmx2G`/`workers.max=1`; `android/gradle.properties` tuned, `NDK
  28.2.13676358` installed, missing `google-services.json` diagnosed —
  admin copy must be downloaded for `com.familytracker.admin_app`). Build on
  bigger hardware/CI. Flutter 3.47.5 + Developer Mode needed for plugin
  symlinks.
- Tools installed: `C:\tools\flutter`, NDK; ADB forced to port 5038;
  wireless debugging paired (`adb pair`/`connect`) after port rotated.

### Network
- Laptop DHCP drifted `.35 → .36 → .37 → .36`. Fix: Syrotech **Network → LAN
  → IPv4 → Edit Reserved IP Address** (laptop Wi-Fi MAC `10-6F-D9-F1-1C-E3`
  → `192.168.1.36`) + `ipconfig /release` + `/renew`. New files:
  `deploy/windows/{start,stop,init-db,start-traccar}.ps1`,
  `deploy/traccar/traccar.windows.xml`, `.env.relay.windows`
  (`INGEST_URL=http://192.168.1.36:5055`).
- Full fresh-setup guide: `docs/SETUP_WINDOWS.md`.

---

## Commits Since Last Session (2026-07-09 → 2026-07-14)

| Date | SHA | Title |
|---|---|---|
| 2026-07-14 | `c19e01d` | new file |
| 2026-07-12 | `d2c82cb` | Add Ubuntu setup script |
| 2026-07-12 | `04b8b37` | Add Dockerfile, Caddyfile, env template for fresh Ubuntu deploy |
| 2026-07-12 | `2877b13` | Track reporter release keystore and FCM secrets (private repo) |
| 2026-07-12 | `5c14173` | Track .env.relay and FCM service account (private repo) |
| 2026-07-10 | `68a7e99` | Add README.md |
| 2026-07-10 | `ac24e14` | v3.0: offline/cached state, connectivity monitor, geofence fixes, crash reporting, activity detection |
| 2026-07-10 | `4871a4b` | Fix: resolve device name from pending model when Traccar GetDevice fails; add error logging |
| 2026-07-10 | `fbdbaa8` | Fix reporter NetworkOnMainThreadException in requestSingleLocation by wrapping postLocation in scope.launch(Dispatchers.IO); drain position queue after locate |
| 2026-07-09 | `02a5bd5` | Fix: subscribe detail sheet to DevicesController via addListener, add delay to locate refresh |
| 2026-07-09 | `59a1f0a` | Fix: reactive detail sheet via context.watch in build, header refresh sends locate to all devices, locate no longer pops sheet |
| 2026-07-09 | `4613a2b` | Fix: live-reactive detail sheet, auto-refresh DevicesController after approve, locate refreshes + pops sheet |
| 2026-07-09 | `7a5525d` | Fix: auto-locate after approval so admin sees coordinates immediately |

---

## v3.0 Release (2026-07-10) — Major Features

### Offline Resilience & Connectivity
- **ConnectivityMonitor** — pings `/healthz` every 15s, tracks online/offline state
- **Red gradient offline banner** — shows elapsed offline time
- **Stale-data warning** — orange banner "showing cached data — last updated X ago"
- **Last-known data preserved** on refresh failure (no blank screens)
- **WebSocket connection status** — colored dot on Devices tab

### Crash Reporting
- **Admin app** (`crash_reporter.dart` + `crash_log_screen.dart`):
  - Hooks `FlutterError.onError` and `PlatformDispatcher.onError`
  - Rotating JSONL file (50-entry ring buffer)
  - Viewable in-app via About → Troubleshooting → Crash & Error Logs
  - Share via `share_plus`
- **Reporter** (`ReporterApp.kt`):
  - Process-wide uncaught-exception handler
  - Writes to `filesDir/crash/crash_log.txt`
  - Registered as `Application` in manifest

### Activity Detection
- **Reporter**: `ActivityRecognitionClient` in `LocationForegroundService`
  - Requests ~30s activity updates → `ActivityReceiver` (BroadcastReceiver)
  - Filters by confidence (≥40%)
  - Reports via `RelayClient.reportActivity`
- **Relay**: `POST /api/device/activity` (ingest-token auth)
  - `reporter_device_meta.last_activity` text column
  - `SetDeviceActivityByToken` store method
- **Admin app**: Activity row in device detail sheet with friendly labels

### Geofence Fixes
- Traccar webhook now properly parses nested JSON (Traccar 6.6 format)
- Device name resolution: falls back to pending model when Traccar GetDevice fails
- Geofence events persisted to `geofence_events` table with indexes
- New endpoints: `GET /admin/geofence_events` (paginated) + `GET /admin/geofence-stats`
- Geofence History screen in admin app (menu item)

### Bug Fixes in v3.0
| Bug | Fix |
|---|---|
| Live-mode locate interruption | Service posts single position without stopping live tracking |
| Silent FCM failure | About screen shows push status with retry; relay re-pushes on poll |
| Orphaned Traccar device on approve failure | Approve rolls back Traccar device if relay approval fails |
| Refresh spam / unbounded concurrent refreshes | 60s throttle + `_refreshing` guard; pending timer 5s → 30s |
| Reporter NetworkOnMainThreadException | `postLocation` wrapped in `scope.launch(Dispatchers.IO)` |
| Detail sheet not reactive | Added `addListener` + `context.watch` in build |
| Locate refresh pops sheet | Locate no longer pops sheet; polls in background |
| Auto-locate after approval | Admin sees coordinates immediately post-approval |

---

## Infrastructure & Deployment (2026-07-12)

### Ubuntu VPS One-Script Setup
- **`deploy/setup.sh`** — installs Docker, Docker Compose v2, Go 1.25.8 on fresh Ubuntu 22.04/24.04
- **`deploy/docker/Dockerfile`** — multi-stage Go build for relay
- **`deploy/docker/Caddyfile`** — reverse proxy with TLS, `/traccar/*` routing
- **`.env.relay.example`** — template with all required env vars
- **`deploy/docker/docker-compose.yml`** — PostgreSQL + Traccar + Relay
- **`deploy/docker/postgres-init/`** — schema initialization scripts

### Secrets Management
- `secrets/reporter-release.jks` — release keystore (tracked in private repo)
- `secrets/fcm-service-account.json` — Firebase Admin SDK key (tracked in private repo)
- `.env.relay` — runtime config (tracked in private repo)

---

## Previous Session Summary (2026-07-09)

### Bug Fixes Implemented
| Bug | Files | Fix |
|---|---|---|
| BUG-3: Live-mode locate interruption | `LocationForegroundService.kt` | Post single position without stopping live tracking |
| BUG-4: Silent FCM failure | `main.dart`, `fcm_service.dart` | About screen shows push status + retry; relay re-pushes on poll |
| BUG-5: Orphaned Traccar device on approve failure | `handlers.go`, `postgres.go` | Rollback Traccar device on approval failure |
| BUG-6: Refresh spam / unbounded concurrent refreshes | `devices_controller.dart`, `home_screen.dart` | 60s throttle + concurrency guard; pending timer 5s → 30s |

### Enhancements Implemented
| Feature | Components |
|---|---|
| Crash Reporting | Admin: `crash_reporter.dart`, `crash_log_screen.dart`; Reporter: `ReporterApp.kt` |
| Geofence History & Analytics | Schema: `geofence_events` table; Relay: webhook persistence + endpoints; Admin: `geofence_history_screen.dart` |
| Location Sharing Links | Schema: `share_links` table; Relay: CRUD + public GET; Admin: share action in detail sheet |
| Activity Detection | Reporter: `ActivityRecognitionClient` + `ActivityReceiver`; Relay: activity ingestion; Admin: activity row in detail sheet |
| Pagination (PERF-1) | Relay: limit/offset on ListPending/ListApprovedDevices; Admin: loadMore() |
| Input Validation (SEC-6) | Server: 100-char cap on device name; Client: validation in rename/approve dialogs |

### Issues Encountered & Fixed (Previous Session)
| Issue | Root Cause | Fix |
|---|---|---|
| Android listener crash: `Cannot add to an unmodifiable list` | `pending_controller.dart` used `const []` | Changed to mutable `[]` |
| Share link crash: `type 'Null' is not a subtype of type 'int'` | Go returned `"deviceId"` but Dart expected `"traccarDeviceId"` | Fixed Go response key |
| `INSERT ... CASE status` SQL error | CASE produced `text` but column is enum | Cast branches with `::approval_status` |
| `EnsureSchema` "must be owner of table" | Relay connected as `relay_user` (non-owner) | Switched `DATABASE_URL` to postgres superuser |
| `ListApprovedDevices: cannot scan NULL into *string` | `last_activity` nullable but scanned into non-pointer | Changed `ApprovedDeviceRow.Activity` to `*string` |

---

## Current State / Pending

- ✅ **v3.0 released** — APKs on GitHub releases
- ✅ **Ubuntu deployment ready** — `./deploy/setup.sh` + `docker compose up -d`
- ✅ **Secrets tracked** — keystore, FCM key, .env.relay in private repo
- ✅ **All core features complete** — offline resilience, crash reporting, activity detection, geofence history, location sharing
- ⏳ **Deploy to VPS** — provision Ubuntu, run setup.sh, configure DNS, test from mobile data
- ⏳ **Rebuild APKs with production URLs** — update `Config.kt` (reporter) and admin server config
- ⏳ **Geofence CRUD in admin app** — draw zones on map, push notifications
- ⏳ **Hardening** — OEM battery workarounds, data retention cron, tests

### To re-add your own device (shows "Device removed"):
```bash
adb shell pm clear com.familytracker.reporter
adb shell am start -n com.familytracker.reporter/.ui.MainActivity
```
With the relay fix (`3953dd8`), re-registration now succeeds; device reappears in admin **Pending** tab for re-approval.

### Running Locally (Reminder)
```bash
# Relay
cd services/notify_relay
set -a && source ../../.env.relay && set +a
export DATABASE_URL='postgres://postgres:hSy1ht9ZAxCHRjA4AlyYsbtex57PrHZJKMTPw1lCS0s=@localhost/postgres?search_path=relay&sslmode=disable'
go run ./cmd/server

# Admin app rebuild
cd apps/admin_app
flutter build apk --release
adb install -r build/app/outputs/flutter-apk/app-release.apk

# Reporter rebuild
cd apps/reporter
./gradlew assembleDebug
adb install -r app/build/outputs/apk/debug/app-arm64-v8a-debug.apk
```

### Notes
- Reporter `Config.kt` hardcodes `RELAY_BASE_URL` to `http://192.168.1.35:8080`; change + rebuild for different LAN IP
- FCM is optional — unset `FCM_SERVICE_ACCOUNT_JSON` to run without push notifications
- For production: update reporter `Config.kt` and admin app with public HTTPS URLs after VPS deployment