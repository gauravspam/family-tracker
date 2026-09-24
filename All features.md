## Admin App (Flutter)

### Map & Tracking
- Live map (flutter_map + OSM) with satellite/aerial toggle
- Real-time device positions via Traccar WebSocket
- Smooth marker motion estimation (speed+course extrapolation, decay, blend)
- Pulsing ring animation for LIVE-mode devices
- Geofence overlay (translucent blue circles)
- Pin-drop with reverse-geocoding (Nominatim)
- Recenter button (fit all devices)
- Movement trail with gap detection (>60s breaks line)
- Trail history playback slider with arrow marker
- Follow-mode peek sheet (device name, LIVE badge, battery %, speed)
- Auto-center on followed device

### Device Management
- Device list (sorted: online first → alpha) with avatar, battery %, relative time
- Device detail bottom sheet (copyable coords, address, speed, accuracy, battery, activity, status)
- Device renaming
- Device appearance editor (11 SVG avatars + 12 colors)
- Device removal with confirmation
- Orphan device detection (in Traccar but no relay metadata)
- Online/offline status (2-min threshold)
- Low battery banner (<20%)
- LIVE card highlight (green glow + chip)
- **Share location** — generates temporary shareable link with device name + latest position

### Remote Commands
- One-shot locate (polls up to 3x for position)
- 30-min live tracking with auto-expiry
- Stop live tracking
- Ring device (30s alarm)
- Open route in external nav app

### Device Approvals
- Pending requests screen (model, OS version, request time)
- Approve with custom name (fallback to model)
- Reject with confirmation
- Auto-refresh every 30s (pauses when backgrounded)
- Badge count on nav pill

### Geofences
- Geofence list sheet (type/radius, delete)
- Create geofence (tap pin + radius slider 25-2000m)
- Geofence deletion with confirmation
- CRUD via Traccar API

### Event Log
- Geofence enter/exit events with device name, type icon, relative time
- Pull-to-refresh
- Persisted in relay PostgreSQL
- Offline stale-data banner
- **Geofence History screen** — recent events + analytics card (menu item)
- **Geofence analytics** — stats endpoint

### Push Notifications
- FCM init, notification channel, permission request
- Token registration with relay
- Foreground frosted-glass toast (geofence alerts)
- Background system notification (high priority, sound, vibration)
- Token refresh listener
- **About screen shows push status** with retry button

### Offline Resilience
- ConnectivityMonitor pings relay /healthz every 15s
- Red gradient offline banner with elapsed time
- Stale-data warning (orange "showing cached data — last updated X ago")
- WebSocket connection status on Devices tab
- Last-known data preserved on refresh failure
- 60s throttle + concurrency guard on refresh

### UI / UX
- iOS-style frosted-glass (BackdropFilter blur + semi-transparent surfaces)
- Theme selection (System/Light/Dark) persisted
- 11 OpenMoji avatar presets (father, mother, brother, sister, grandparents, boy, girl, friends, generic)
- 12-color palette per device (stored as #RRGGBB)
- Passcode-protected hidden devices (4-6 digit)
- Three-tab pill nav with pending badge
- Floating header with overflow menu
- PageView with haptic feedback
- Auto-logout on 401
- Transparent floating header with blur
- Floating pill bottom nav with swipe between tabs

### Debug / Admin
- Rotating crash log (50-entry ring buffer)
- Crash log viewer + clear
- Share crash logs via `share_plus`
- App/session/server info screen
- Live WebSocket status with colored dot
- Change server URLs
- First-run server URL setup screen

---

## Reporter App (Kotlin/Android)

### Registration
- Stable device ID (ANDROID_ID with fallback)
- Join request submission (androidId, model, FCM token, OS version)
- Approval polling every 15s
- Stepped permission sequence (location → fine + notifications → background → battery exemption)

### Location
- Foreground location service (Fused Location Provider, high accuracy)
- One-shot locate (single GPS fix, then stops)
- Live tracking (5s interval, auto-expires after 30 min)
- OsmAnd protocol ingestion (batt, activity, speed, course, altitude, accuracy)
- Command polling loop (every 5 min)
- **Locate during live mode** — posts single position without stopping live tracking

### FCM Commands
- approved — receive ingest token, one-shot locate
- live_mode — enable continuous GPS with expiry
- idle_mode — stop continuous GPS
- locate — one-shot position
- removed — stop service, set REMOVED
- ring — play alarm

### Ring / Find My Phone
- System alarm at max volume, looping
- Configurable duration (default 30s)
- Volume save/restore
- "Stop" notification action button
- **Guard against repeat commands** — extends timer instead of restarting MediaPlayer

### Resilience
- WatchdogWorker (WorkManager, 15-min periodic check)
- Boot receiver (restarts after reboot)
- Offline position queue (file-based, max 500, retried on success)
- FCM token auto-refresh + push to relay on rotation
- Proactive FCM sync on each poll cycle
- **NetworkOnMainThreadException fixed** — postLocation wrapped in IO dispatcher

### Other
- Speed-based activity detection (still, walking, running, bicycle, vehicle) via ActivityRecognitionClient
- Battery level reporting
- Uncaught exception handler (rotating log files)
- EncryptedSharedPreferences for ingest token
- Activity ingestion endpoint (`POST /api/device/activity`)

---

## Relay Backend (Go)

### API Endpoints
- `POST /join` — Device registration
- `GET /api/device/status` — Reporter polls for approval (androidId)
- `POST /api/device/refresh-fcm` — FCM token rotation (androidId + ingestToken auth)
- `POST /api/device/activity` — Activity ingestion (ingest-token auth)
- `GET /admin/pending` — List pending (paginated)
- `GET /admin/devices` — List approved devices (paginated)
- `POST /admin/approve/{pendingId}` — Approve with optional name
- `POST /admin/reject/{pendingId}` — Reject
- `POST /admin/remove/{id}` — Remove (permissive: DELETE rows)
- `DELETE /admin/device-by-traccar/{traccarId}` — Remove by Traccar ID (orphan-safe)
- `PUT /admin/rename/{traccarId}` — Rename device
- `PUT /admin/appearance/{traccarId}` — Set avatar + color
- `POST /admin/live/{deviceId}` — Start live mode (with expiresAt)
- `POST /admin/idle/{deviceId}` — Stop live mode
- `POST /admin/ring/{deviceId}` — Ring device
- `POST /admin/locate/{deviceId}` — One-shot locate
- `POST /admin/fcm-token` — Register admin FCM token
- `GET /admin/geofence_events` — List geofence events (paginated, filterable)
- `GET /admin/geofence-stats` — Geofence event analytics
- `POST /admin/share` — Create share link
- `GET /admin/share` — List share links
- `DELETE /admin/share/{token}` — Revoke share link
- `GET /share/{token}` — Public share link (device name + latest position)
- `POST /webhook/traccar/event` — Traccar webhook (geofence events)
- `GET /healthz` — Health check

### Integrations
- Traccar session-based auth (JSESSIONID) with auto-reauth
- Device CRUD (create, get, delete, rename via full PUT + merge)
- Ingest token generation (16-byte base64)
- Firebase Admin SDK (single + multicast FCM sends)
- Graceful FCM degradation if key file missing
- **Approve rolls back Traccar device on failure** (prevents orphans)
- **FCM token re-push on every poll** (handles rotation)

### Database
- `pending_devices` table (upsert on android_id)
- `reporter_device_meta` table (state, mode, expiry, ingest token, last command, last_activity)
- `admin_push_tokens` table
- `geofence_events` table (indexed by device, geofence, created_at)
- `share_links` table (token, traccar_device_id, created_at, expires_at)
- Schema separation (traccar schema / relay schema, no cross-access)
- **Indexes** on geofence_events for query performance
- **EnsureSchema** creates tables at startup for existing deployments

---

## Infrastructure / Deploy

- Docker Compose: PostgreSQL 15 + Traccar 6.6 + relay
- Traccar config: schema isolation, OsmAnd port 5055, event forwarding, registration disabled
- Relay Dockerfile (multi-stage Go build)
- Caddy reverse proxy (TLS, /traccar/* path routing)
- PostgreSQL init scripts (schemas, users, permissions)
- `.env.relay.example` template
- **setup.sh** — auto-installs Docker + Docker Compose + Go 1.25.8 on Ubuntu
- FCM service account + reporter keystore tracked (private repo)
- Movement simulation script (Python)
- **Ubuntu VPS one-script deployment** — `./deploy/setup.sh` then `docker compose up -d`

---

## APK Builds

- v3.0 published on GitHub (2026-07-10)
- Admin: arm64-v8a only, 20MB (via --split-per-abi)
- Reporter: arm64-v8a only, 1.4MB
- v2.0: on-demand location, frosted-glass UI, geofence alerts via FCM (2026-07-08)
- v1.1.0: UI polish (2026-07-03)
- v1.0.0: First release (2026-07-05)