# Family Tracker — Project Summary

## What We Built

A self-hosted family location tracking system with three components:

### 1. Reporter App ("Recorder") — Pure Kotlin
**APK size:** 1.4 MB release

- Auto-permission flow (notification → fine location → background location → battery optimization)
- Foreground service with persistent notification
- Location posting via OsmAnd HTTP protocol to Traccar
- Idle mode: 10-minute intervals | Live mode: 5-second intervals
- Battery level reporting in each position post
- FCM push command handling (approved, live_mode, idle_mode, removed, ring)
- Ring device: plays alarm at max volume with notification stop button
- Boot recovery (auto-starts on reboot)
- Stable `Settings.Secure.ANDROID_ID` (survives reinstalls)
- FCM token auto-refresh + push to relay
- Solid black screen after approval (nothing for family member to interact with)
- Dark red microphone icon disguised as "Recorder"
- **Activity detection** via Google ActivityRecognitionClient (~30s updates, confidence ≥40%)
- **Offline position queue** (file-based, max 500 entries, auto-flush on reconnect)
- **WatchdogWorker** (WorkManager, 15-min periodic check) restarts foreground service if killed
- EncryptedSharedPreferences for ingest token
- Uncaught exception handler (rotating log files)

### 2. Admin App — Flutter
**APK size:** 19.3 MB release (arm64-v8a only, 20MB via --split-per-abi)

- **Server setup screen** — runtime-configurable URLs (no hardcoded IPs)
- **Login** — Traccar session + relay admin token, with field validation
- **Devices tab** — card-based list with avatars, battery, coordinates, time, live glow effect
- **Map tab** — OpenStreetMap tiles with animated markers
  - Dead-reckoning motion estimation (bounded 6s/100m extrapolation with decay)
  - Position trails with impossible-jump filtering and time-gap segmentation
  - Follow-device mode with "Following X" chip
  - Clear trail button
  - Pulsing ring on markers in live mode
- **Pending tab** — auto-refresh every 30s, badge count on nav, approve with custom device name
- **Device detail sheet** — full info (coords, address, accuracy, speed, fix time, battery, activity)
  - Rename anytime
  - Per-device avatar (11 OpenMoji presets) + color picker
  - Track Live / Stop Live (FCM-pushed, instant)
  - Follow on map
  - Directions (opens Google Maps)
  - Ring device
  - Remove (with confirmation)
  - Copy-to-clipboard on coordinates and address
  - Reverse geocode via OSM Nominatim
  - Live mode banner with countdown
  - **Share location** — generates temporary shareable link
- **WebSocket** real-time position updates with connection state banner
- **About screen** — app info, server URLs, live connection status, change-server-URLs button
- **Dark mode** (system-driven, iOS-inspired colors)
- **Floating pill bottom nav** with swipe between tabs
- **Transparent floating header** with blur
- **Offline resilience** — cached state preserved on network failure, friendly error messages
- **Orphan device detection** + ORPHAN chip + cleanup via Remove
- **Sign-out confirmation dialog**
- **Passcode-protected hidden devices** (4-6 digit)
- **Theme selection** (System/Light/Dark) persisted
- **Rotating crash log** (50-entry ring buffer) viewable from About → Troubleshooting
- **Crash log viewer + clear** + share via `share_plus`

### 3. Go Relay Service
- Join / approve / reject / remove device lifecycle
- Rename device (Traccar PUT)
- Set device appearance (avatar + color in Traccar attributes)
- Track Live / Stop Live / Ring via FCM
- Idle endpoint for Stop Live
- FCM token refresh endpoint (reporter pushes rotated tokens)
- Permissive removal (full row delete, allows re-registration)
- Geofence event webhook forwarding
- Stable `android_id` upsert (no duplicate creation on reinstall)
- Orphan-safe removal (deletes Traccar-only devices)
- **Geofence event persistence** — `geofence_events` table with indexes, paginated query
- **Geofence analytics** — event stats endpoint
- **Location sharing links** — create/list/revoke share tokens, public GET returns device + latest position
- **Pagination** — `ListPending` and `ListApprovedDevices` accept limit/offset
- **Input validation** — device-name cap at 100 chars (server + client)
- **Activity ingestion** — `POST /api/device/activity` (ingest-token auth), stores `last_activity`

### 4. Infrastructure
- Traccar 6.6 (pinned Docker image) as tracking engine
- PostgreSQL 15 with `traccar` + `relay` schema separation
- Firebase Cloud Messaging for push commands
- Docker Compose orchestration
- **Caddy reverse proxy** — TLS, `/traccar/*` path routing
- **Ubuntu setup script** — auto-installs Docker + Docker Compose + Go 1.25.8
- **Secrets tracked** — reporter-release.jks, fcm-service-account.json (private repo)
- **Environment template** — `.env.relay.example`
- **Movement simulation script** — Python script for testing

---

## Bugs Found and Fixed Along the Way

| Bug | Root Cause | Fix |
|---|---|---|
| Duplicate devices on reinstall | Timestamp-based androidId regenerated on every `pm clear` | Switched to `Settings.Secure.ANDROID_ID` |
| Duplicate Traccar device on re-approval | Join upsert flipped `approved` back to `pending` | Removed `status = 'pending'` from upsert's DO UPDATE |
| Reporter stuck on "Device removed" after reinstall | Meta row `state=removed` blocked re-registration | Changed to permissive removal (DELETE rows instead of marking removed) |
| FCM "Requested entity was not found" | Token rotated by Firebase but relay still had old one | Added `/api/device/refresh-fcm` endpoint + proactive sync on each poll |
| Admin shows orphan Traccar devices | Partial approve failures left Traccar devices without relay rows | Added orphan detection chip + orphan-safe remove endpoint |
| Positions not reaching Traccar from phone | `ingestUrl` pointed to `localhost` instead of LAN IP | Fixed relay to use `INGEST_URL` env var |
| Reporter posting to wrong IP after DHCP change | Hardcoded LAN IP in config | Added runtime server URL config screen |
| WebSocket auth failure → immediate logout | Couldn't distinguish transient WS drop from real auth expiry | WebSocket auto-reconnects with exponential backoff |
| Trail lines zigzagging through buildings | Raw GPS points connected with straight lines | Added impossible-jump filter (>40 m/s = skip) + time-gap segmentation |
| Admin app 401 on Traccar restart | JSESSIONID invalidated on server restart | Auto-logout + re-login flow |
| Ring stops after 2-3 seconds | Repeat FCM commands restarted the MediaPlayer | Guard against re-starting; extend timer instead |
| Pending list shows error on offline | Empty list + refresh failure showed full error page | Preserve last-known state; only show error when no previous data |
| **Live-mode locate interruption** | Locate intent stopped live tracking | Service now posts single position without stopping live tracking |
| **Silent FCM failure** | No visibility into token registration failures | About screen shows push status with retry; relay re-pushes on poll |
| **Orphaned Traccar device on approve failure** | Traccar device created but relay approval failed | Approve now rolls back Traccar device on failure |
| **Refresh spam / unbounded concurrent refreshes** | No throttle or concurrency guard | 60s throttle + `_refreshing` guard; pending timer 5s → 30s |
| **Reporter NetworkOnMainThreadException** | `postLocation` called on main thread | Wrapped in `scope.launch(Dispatchers.IO)` |
| **Detail sheet not reactive** | Wasn't subscribed to DevicesController changes | Added `addListener` + `context.watch` in build |
| **Locate refresh pops sheet** | Header refresh triggered sheet dismiss | Locate no longer pops sheet; polls in background |

---

## What's Not Done Yet

### Phase 6: Cloud Deployment
**Status:** **In progress** — Ubuntu VPS deployment ready
**Plan:**
1. Provision Ubuntu VPS (Oracle Cloud Always Free ARM, or any cloud)
2. Run `./deploy/setup.sh` — installs Docker, Docker Compose, Go
3. Configure `.env.relay` with FCM credentials and domain
4. Run `docker compose -f deploy/docker/docker-compose.yml up -d`
5. Point DNS at VPS IP, Caddy handles TLS automatically
6. Update admin app server URLs to the new HTTPS endpoints
7. Update reporter's `Config.kt` with the public URLs → rebuild APK
8. Test from mobile data (not wifi) — full end-to-end

**Alternative:** Cloudflare Tunnel on laptop (`cloudflared` daemon) for local testing without VPS.

**Effort:** 1-2 hours for Cloudflare Tunnel. 2-3 hours for full VPS deployment with setup.sh.

### Phase 7: Hardening
**Status:** Not started
**Plan:**
1. **OEM battery optimization prompts** — Xiaomi/Realme/Samsung have their own battery killers. The reporter should detect the OEM and show device-specific instructions (e.g., "Go to Settings → Battery → App launch management → Recorder → Allow background activity")
2. **WorkManager watchdog** — Already implemented (15-min periodic check). Could enhance with OEM-specific restart logic.
3. **Data retention cron** — Traccar accumulates positions indefinitely. Add a 30-day rolling cleanup as specified in the architecture doc.
4. **Tests** — unit tests for the relay endpoints, integration tests for the approve/remove/live flows

### Remaining Polish (Optional)
- **C2:** Glassmorphism on map overlays (BackdropFilter) — skipped
- **C5:** Search/filter on device list — skipped (useful at >5 devices)
- **OSRM road-snapping** for Mumbai/Navi Mumbai — deferred
- **Geofence CRUD** in admin app — Traccar supports it, UI not built
- **Admin app FCM registration** for geofence event notifications

---

## Architecture Decisions Made During Development

| Decision | Rationale |
|---|---|
| Kotlin reporter instead of Flutter | 1.4 MB vs 176 MB; 40 MB RAM vs 180 MB; foreground service is native |
| Flutter admin instead of Kotlin | Map, live updates, multiple screens — Flutter's widget composition wins |
| `Settings.Secure.ANDROID_ID` over pairing codes | Non-tech-friendly parents shouldn't type codes |
| Permissive removal (DELETE rows) | Family members reinstall for legitimate reasons |
| Dead-reckoning with bounded extrapolation | Smooth motion without requiring road-snapping infrastructure |
| Per-device appearance in Traccar attributes | No relay-side storage needed; Traccar already has a JSON attributes field |
| FCM data messages (not notification) | Guarantees the app processes the command in `onMessageReceived` |
| OsmAnd HTTP protocol for ingest | Simplest Traccar integration; no session management on reporter side |
| Polling + FCM dual path | Polling handles FCM delivery failures; FCM handles instant mode changes |
| Schema separation (traccar/relay) | Zero cross-access; each service owns its data |
| Caddy for TLS | Automatic HTTPS with zero config; handles path routing to Traccar/Relay |
| setup.sh for Ubuntu | One-command bootstrap for fresh VPS; no manual dependency installation |

---

## GitHub Releases

- **v1.0.0** — First release with all core features (2026-07-05)
- **v1.1.0** — UI polish (richer cards, live glow, transparent header, iOS-inspired theme) (2026-07-03)
- **v2.0.0** — On-demand location, frosted-glass UI, geofence alerts via FCM (2026-07-08)
- **v3.0.0** — Offline/cached state, connectivity monitor, geofence fixes, crash reporting, activity detection (2026-07-10)

Repository: `https://github.com/gauravspam/family-tracker`

---

## Next Session Priority

When you're ready to continue:

1. **Deploy to VPS** — Run `./deploy/setup.sh` on Ubuntu, configure `.env.relay`, `docker compose up -d`
2. **Configure DNS + TLS** — Point domain at VPS, Caddy handles HTTPS automatically
3. **Rebuild APKs with production URLs** — Update `Config.kt` (reporter) and admin app server config
4. **Test from mobile data** — Full end-to-end verification outside home WiFi
5. **Geofence CRUD in admin app** — Draw zones on map, get push notifications
6. **Hardening** — OEM battery workarounds, data retention cron, tests

The app is feature-complete for daily family use. **Deployment is the only blocker** — and now there's a one-script Ubuntu setup.

---

## Recent Commits (since last session)

| Date | SHA | Title |
|---|---|---|
| 2026-07-14 | `c19e01d` | new file |
| 2026-07-12 | `d2c82cb` | Add Ubuntu setup script |
| 2026-07-12 | `04b8b37` | Add Dockerfile, Caddyfile, env template for fresh Ubuntu deploy |
| 2026-07-12 | `2877b13` | Track reporter release keystore and FCM secrets (private repo) |
| 2026-07-12 | `5c14173` | Track .env.relay and FCM service account (private repo) |
| 2026-07-10 | `68a7e99` | Add README.md |
| 2026-07-10 | `ac24e14` | v3.0: offline/cached state, connectivity monitor, geofence fixes, crash reporting, activity detection |
| 2026-07-10 | `4871a4b` | Fix: resolve device name from pending model when Traccar GetDevice fails |
| 2026-07-10 | `fbdbaa8` | Fix reporter NetworkOnMainThreadException in requestSingleLocation |
| 2026-07-09 | `02a5bd5` | Fix: subscribe detail sheet to DevicesController via addListener |
| 2026-07-09 | `59a1f0a` | Fix: reactive detail sheet via context.watch in build |
| 2026-07-09 | `4613a2b` | Fix: live-reactive detail sheet, auto-refresh after approve |
| 2026-07-09 | `7a5525d` | Fix: auto-locate after approval so admin sees coordinates immediately |