"# Family Tracker — Final Architecture Record

> Single source of truth. All decisions locked. Do not reopen settled items.
>
> Last updated: June 2026

---

## 1. Project Constraints (Non-Negotiable)

| Constraint | Value |
|---|---|
| User count | 3 fixed family + occasional friends, <10 concurrent |
| Admin count | 1 (the operator) |
| Platform | Android only, v1 |
| Cost target | Zero (free tier hosting) |
| Operational model | Self-hosted, single person maintains |
| History/analytics | Out of scope v1 |
| iOS | Out of scope v1 |
| Multi-admin | Out of scope v1 |

---

## 2. Final Tech Stack

### 2.1 Backend

| Component | Technology | Version Policy |
|---|---|---|
| Tracking engine | Traccar Server | Pin exact version in `deploy/traccar/`; never use `latest` |
| Relay/orchestration | Go (single binary) | Pin Go version in `go.mod` |
| Database | PostgreSQL 15+ | Single instance, two schemas |
| Reverse proxy + TLS | Caddy or nginx + Let's Encrypt | Covers Traccar API port and OsmAnd ingest port |
| Push notifications | Firebase Cloud Messaging (FCM) | Server SDK in relay |

### 2.2 Mobile

| Component | Technology |
|---|---|
| Admin app | Flutter (Android) |
| Reporter app | Flutter (Android) |
| Shared logic | Dart package `tracker_core` (monorepo) |
| Map rendering | `flutter_map` + OpenStreetMap tiles |
| Secure storage | `flutter_secure_storage` |
| Location plugin | `geolocator` |
| HTTP client | `dio` or `http` |
| WebSocket client | `web_socket_channel` |
| FCM client | `firebase_messaging` |
| Permissions | `permission_handler` |

### 2.3 Hosting

| Resource | Value |
|---|---|
| Provider | Oracle Cloud Infrastructure (OCI) |
| Shape | VM.Standard.A1.Flex (ARM Ampere) |
| Always Free quota | 1,500 OCPU-hours + 9,000 GB-hours/month ≈ 2 OCPU / 12 GB continuous |
| Storage | 200 GB block volume (Always Free) |
| Region preference | ap-mumbai-1; fallback ap-singapore-1 |

> **Note:** Oracle Always Free quota means ~2 OCPU / 12 GB when run continuously.
>
> Larger shapes consume the monthly quota faster and may incur PAYG charges.
>
> Oracle may reclaim idle Always Free instances (all metrics below 20th percentile for 7+ days). Mitigate with a lightweight cron job maintaining minimal activity.

---

## 3. All Final Decisions with Rationale and Rejected Alternatives

### 3.1 Tracking Backend: Traccar

**Decision:** Use Traccar as the central tracking engine.

**Rationale:** Traccar provides location ingest, device management, geofence detection, event generation, REST API, WebSocket live updates, and PostgreSQL persistence out of the box. Building equivalent infrastructure from scratch would require designing, debugging, and maintaining a tracking platform — a scope increase incompatible with project goals.

**Rejected alternatives:**

| Alternative | Reason rejected |
|---|---|
| OwnTracks Recorder | No integrated permission model, no geofence eventing, no device lifecycle management |
| Custom-built tracker backend | Multiplies scope by 5–10×; correctness edge cases in mobile delivery alone are non-trivial |
| Traccar Cloud (hosted) | Costs money; no self-host control |

---

### 3.2 Mobile Stack: Flutter + Two Separate Apps

**Decision:** Two separate Flutter apps (admin, reporter) sharing a `tracker_core` Dart package.

**Rationale:** Both apps share DTOs, API clients, retry policies, error models, and WebSocket message contracts. A shared Dart package eliminates duplication and keeps the integration contract consistent. Two separate apps enforce the asymmetric trust model at the binary level — the reporter APK has zero admin capability.

**Rejected alternatives:**

| Alternative | Reason rejected |
|---|---|
| One role-based Flutter app | Complicates trust model; admin capability would exist in family APK |
| Native Android Kotlin | No shared business logic across two apps; main complexity is integration, not low-level sensor access |
| React Native | No team familiarity advantage; Flutter equally capable for this scope |

---

### 3.3 Relay Service: Go

**Decision:** Small Go service handling approvals, FCM dispatch, and webhook processing.

**Rationale:** Go produces a single static binary, has excellent HTTP and PostgreSQL library support, compiles fast, and is appropriate for a small policy/orchestration layer. The relay is intentionally thin — it does not duplicate any tracking logic.

**Relay responsibilities:**

- Accept join requests from reporter apps.
- Store pending device records.
- Expose pending list to admin app.
- On approval:
- Create device in Traccar via API with random high-entropy `uniqueId`.
- Store `traccar_device_id` → `android_id` → `ingestToken` mapping.
- Send FCM `approved` command to reporter with `ingestToken` + `ingestUrl`.
- On removal (see §3.17 for full removal contract):
- Send FCM `removed` command to reporter app.
- Delete Traccar device via `DELETE /api/devices/{id}`.
- Receive Traccar geofence event webhooks.
- Convert geofence events to FCM push notifications for admin app.
- Send silent FCM commands to reporter apps.
- Expose polling status endpoint for FCM fallback.

**Rejected alternatives:**

| Alternative | Reason rejected |
|---|---|
| Node.js | No strong advantage; Go binary deployment simpler on ARM |
| Python | Same; Go is more appropriate for a long-running service |
| Extend Traccar directly | Couples custom policy to tracking infrastructure; violates the clean boundary principle |
| No relay (direct Traccar) | Traccar has no native "pending device awaiting approval" concept; geofence-to-FCM routing requires custom code regardless |

---

### 3.4 Database: PostgreSQL with Schema Separation

**Decision:** Single PostgreSQL instance, two separate schemas with separate DB users.

```text
traccar schema -> owned by traccar_user (Traccar manages this entirely)
relay schema   -> owned by relay_user (relay owns all custom tables)
```

**Rationale:** Traccar manages its own schema. Sharing a database without schema separation risks table name collisions on Traccar upgrades and credential coupling. Two schemas with separate users cost nothing operationally and prevent cross-contamination. `relay_user` has no privileges on the `traccar` schema.

**Rejected alternatives:**

| Alternative | Reason rejected |
|---|---|
| Two separate databases | Acceptable alternative; single instance with schemas chosen for simplicity |
| SQLite for relay | No concurrent connection support; insufficient for production |
| Traccar's DB for relay tables | Entangles custom state with tracking infrastructure; violates ownership boundary |

---

### 3.5 Location Ingest Protocol: OsmAnd HTTP

**Decision:** Reporter app posts positions to Traccar using OsmAnd HTTP protocol with a per-device `uniqueId` token.

**Rationale:** OsmAnd is Traccar's documented simple starting point for custom apps. It requires no session management — the device sends a unique identifier token plus position fields over HTTP. The token is set by the relay at approval time (high-entropy random value), not derived from the device identifier.

**Port configuration:** OsmAnd runs on a separate Traccar port (default 5055). Both the main API port (8082) and the OsmAnd ingest port must be behind HTTPS in production via the reverse proxy.

**Auto-registration:** `database.registerUnknown = false` must be set in Traccar config. This prevents any device that can reach the ingest port from creating records. Only relay-provisioned devices exist in Traccar.

**Rejected alternatives:**

| Alternative | Reason rejected |
|---|---|
| Traccar REST API (`POST /api/positions`) | Requires real Traccar user auth per device; session management on reporter side |
| Traccar binary/TCP protocol | Overkill; no advantage for HTTP-capable mobile clients |
| MQTT | Adds broker infrastructure; no benefit at this scale |

---

### 3.6 Reporter Credential Model: Device-Scoped Ingest Token

**Decision:** Reporter receives a high-entropy random `ingestToken` (= Traccar device `uniqueId`) via FCM `approved` command. This is the only credential the reporter holds.

**Approval flow:**

```text
1. Reporter sends join request (no credential required)
2. Admin approves via relay
3. Relay calls Traccar API (server-side; admin auth never leaves relay)
4. Relay creates Traccar device with uniqueId = random 128-bit base64url token
5. Relay sends FCM approved command to reporter
6. Reporter persists ingestToken in flutter_secure_storage
7. Reporter uses ingestToken for all OsmAnd ingest posts
```

**Rejected alternatives:**

| Alternative | Reason rejected |
|---|---|
| Embed admin credentials in APK | Critical security risk; APK is redistributable |
| Shared secret for all devices | Compromise of one device compromises all |
| Per-device Traccar user account | Session management on reporter side; complexity without benefit |

---

### 3.7 FCM Command Payloads (Complete Contract — All Four Commands)

These are the only FCM data messages the system sends to reporter devices. All fields are strings. No other commands exist in v1.

```json
// Relay → reporter: admin approved the join request
{
  "command": "approved",
  "ingestToken": "<128-bit-base64url>",
  "ingestUrl": "https://host:5055"
}

// Relay → reporter: admin triggered Track Live
{
  "command": "live_mode",
  "expiresAt": "2026-06-30T14:30:00Z"
}

// Relay → reporter: admin manually ended Live mode
{
  "command": "idle_mode"
}

// Relay → reporter: admin removed the device
{
  "command": "removed"
}
```

All commands are **data messages** (not notification messages). FCM priority for `approved` must be `HIGH` to maximize delivery through Doze. Verify `RemoteMessage.getPriority() == PRIORITY_HIGH` before attempting background foreground service start.

**FCM reliability:** Silent FCM messages are not guaranteed delivery in Doze, battery saver, or idle states. Polling fallback covers the `approved` command (see §3.10). For `live_mode`/`idle_mode`, delivery failure is tolerable because LIVE expiry is enforced locally per-publish. For `removed`, Traccar device deletion (see §3.17) provides server-side enforcement even if the FCM command is never received.

---

### 3.8 Reporter App Model: Two Variables + reconcile()

**Decision:** Two independent stored variables and a single idempotent `reconcile()` function. No FSM transition table.

**Why not a formal FSM:** The original spec's 7-state FSM modeled permission-denial and bootstrap-failure paths. With all permissions granted upfront, those states collapse. The remaining lifecycle is two orthogonal concerns: approval (monotonically forward: pending → approved → removed) and mode (idle ↔ live). Combining them into compound states like `APPROVED_LIVE` creates impossible states (e.g., `APPROVED_LIVE` with null `ingestToken`) and requires a transition table protecting against situations that cannot occur.

**Stored state:**

```dart
enum ApprovalStatus { pending, approved, removed }
enum TrackingMode { idle, live }

class ReporterState {
  final ApprovalStatus approval;
  final TrackingMode mode;
  final String? ingestToken; // null until approved
  final String? ingestUrl; // null until approved
  final DateTime? liveExpiresAt; // null when idle
}
```

**reconcile() — single authoritative behavior function:**

```dart
Future<void> reconcile() async {
  // 1. Permission gate — includes precise-level check
  if (!await _hasRequiredPermissions()) {
    _stopLocationSchedule();
    _updateNotification(); // "Precise location required"
    return;
  }

  final state = await _loadState();

  // 2. Removed: stop everything
  if (state.approval == ApprovalStatus.removed) {
    _stopLocationSchedule();
    _stopForegroundService();
    return;
  }

  // 3. Pending: poll relay, wait
  if (state.approval == ApprovalStatus.pending) {
    _schedulePendingPoll();
    _updateNotification(); // "Waiting for setup..."
    return;
  }

  // 4. Approved: expiry enforced per-publish (see §3.9)
  _applyInterval(state.mode); // 5s live, 10min idle
  _updateNotification(); // "Location service active"
}
```

**Permission check — must verify precision level:**

```dart
Future<bool> _hasRequiredPermissions() async {
  final fine = await Permission.locationWhenInUse.status;
  final background = await Permission.locationAlways.status;
  final isPrecise = await _checkLocationPrecision();
  // geolocator: LocationAccuracyStatus.precise
  return fine.isGranted && background.isGranted && isPrecise;
}
```

Android 12+ allows users to select Approximate even when Precise is requested. Coarse-only is not acceptable. If downgraded, stop schedule and set notification to `"Precise location required"`. Tap opens `Settings.ACTION_APPLICATION_DETAILS_SETTINGS`.

**Reconcile triggers:**

| Trigger | Action |
|---|---|
| `BOOT_COMPLETED` broadcast | `reconcile()` |
| Service `onStartCommand` | `reconcile()` |
| FCM command received | write state → `reconcile()` |
| Poll response (approval found) | write state → `reconcile()` |
| Each LIVE-mode location publish | check `liveExpiresAt` → `reconcile()` if expired |

**Rejected alternatives:**

| Alternative | Reason rejected |
|---|---|
| Full 7-state FSM with transition table | Overcomplicated; protects against impossible states that cannot occur |
| Ad hoc boolean flags | No authoritative resume point on restart; impossible-state risk |
| Event sourcing / replay | Over-engineered for 3–4 commands over the device lifetime |

---

### 3.9 LIVE Mode Expiry: Per-Publish Check

**Decision:** LIVE expiry is enforced inside each location publish callback. No periodic timer required.

**Rationale:** LIVE mode publishes every 5 seconds. Checking expiry per publish means expiry is enforced within 5 seconds of the deadline with zero additional infrastructure. On service restart, `reconcile()` checks `liveExpiresAt` immediately — no FCM needed to enforce expiry after a reboot.

```dart
Future<void> _publishLocation(Position position) async {
  final state = await _loadState();

  if (state.mode == TrackingMode.live &&
      state.liveExpiresAt != null &&
      DateTime.now().isAfter(state.liveExpiresAt!)) {
    await _saveState(state.copyWith(mode: TrackingMode.idle, liveExpiresAt: null));
    await reconcile(); // drops to idle interval
    return; // skip this publish; reconcile restarts at idle rate
  }

  await _postToTraccar(position, state.ingestToken!, state.ingestUrl!);
}
```

Default LIVE duration: 30 minutes (admin-configurable in admin app UI). `expiresAt` is an absolute UTC timestamp sent in the FCM payload and stored locally.

---

### 3.10 FCM Control Plane: Primary + Polling Fallback

**Decision:** FCM is primary for all commands. Reporter polls relay as fallback while in `pending` state only.

**Polling endpoint:**

```text
GET /api/device/status?androidId=<id>
-> { "status": "pending|approved|removed", "ingestToken": "...", "ingestUrl": "..." }
```

Polling interval: 5 minutes while in `pending` state. Stops once `approved` or `removed`. Once approved, FCM is sufficient for mode commands because LIVE expiry is enforced locally per-publish regardless of FCM delivery.

---

### 3.11 Bootstrap Permission Sequence

**Decision:** Four-step sequential permission flow. Android API behavior enforces the sequence — it cannot be compressed.

**Critical constraint:** Android ignores simultaneous foreground + background location requests and grants neither. The sequence is mandatory, not a recommendation.

```text
Step 1: Request POST_NOTIFICATIONS (Android 13+ / API 33+)
-> system dialog
-> if denied: FGS notification will not appear; treat as blocking — tracker cannot confirm active state to user

Step 2: Request ACCESS_FINE_LOCATION + ACCESS_COARSE_LOCATION
-> system dialog (user chooses Precise or Approximate)
-> if Approximate chosen: stop, update notification, deep-link to Settings

Step 3: After Step 2 granted at Precise level: Request ACCESS_BACKGROUND_LOCATION
-> routes user to Settings app (cannot be an in-app dialog on Android 11+)
-> app resumes when user returns

Step 4: After Step 3 granted: Request IGNORE_BATTERY_OPTIMIZATIONS
-> ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS system dialog

Step 5: All granted
-> read ANDROID_ID + device model + FCM token
-> POST join request to relay
-> save state: approval=pending, mode=idle
-> start foreground service
-> reconcile()
```

---

### 3.12 Notification Text

**Decision:** Notification text reflects current state. No UI elements, no action buttons except one tap target in the permission-degraded state only.

| State | Notification text |
|---|---|
| `pending` | `Waiting for setup...` |
| `approved` | `Location service active` |
| `removed` | Service stops; notification dismissed |
| Permission revoked or downgraded to approximate | `Precise location required` |

Notification priority: `PRIORITY_LOW` — visible in shade, no sound, no heads-up.

Tap behavior: only active when permission is degraded. Tap opens `Settings.ACTION_APPLICATION_DETAILS_SETTINGS`. No tap action during normal operation.

---

### 3.13 Map: flutter_map + OpenStreetMap

**Decision:** Admin map rendered using `flutter_map` with OpenStreetMap tile layer.

**Rationale:** Zero API key friction, zero billing, full developer control over marker rendering and animation. Map stack can be upgraded to a paid tile source without rewriting marker logic, WebSocket handling, or interpolation.

**Marker movement:** Linear interpolation (LERP) between previous and current coordinates over a bounded animation duration. Raw coordinate replacement causes visible teleports at low update frequencies.

**Rejected alternatives:**

| Alternative | Reason rejected |
|---|---|
| Google Maps Flutter SDK | Requires API key; per-map-load billing risk |
| Mapbox | Requires API key; billing above free tier; unnecessary for this scale |

---

### 3.14 Admin WebSocket Auth

**Decision:** Traccar WebSocket (`/api/socket`) accepts only session cookie authentication. Bearer tokens are not supported on the WebSocket endpoint.

**Implementation requirement:**

1. `POST /api/session` with credentials → receive `JSESSIONID` cookie.
2. Attach `JSESSIONID` to WebSocket upgrade request headers manually (`web_socket_channel` does not inherit cookies from the HTTP client automatically; must be injected into the WebSocket handshake headers).
3. On reconnect: detect 401 → re-authenticate via REST → retry WebSocket (reconnect logic must include a re-auth step, not just a retry).
4. Silently discard empty `{}` keepalive messages sent by Traccar every 55 seconds.

**Reconnection policy:** Exponential backoff. On successful reconnect: re-fetch current positions via `GET /api/positions` before resuming WebSocket subscription to fill the gap. Admin UI displays connection state (connected / reconnecting / offline) as a map overlay banner.

---

### 3.15 Hosting: Oracle Cloud Always Free

**Decision:** Oracle Cloud A1 ARM instance is the hosting target.

**Memory budget:**

| Service | Estimated RSS |
|---|---|
| Traccar (JVM) | 300–500 MB |
| PostgreSQL | 200–400 MB |
| Go relay | 30–50 MB |
| OS + Docker | 300–500 MB |
| **Total** | **830 MB – 1.45 GB** |

Fits comfortably within 12 GB. No other always-free provider offers persistent compute at this memory level.

**Rejected alternatives:**

| Alternative | Reason rejected |
|---|---|
| GCP e2-micro | 1 GB RAM; insufficient for Traccar + PostgreSQL + relay |
| AWS t2.micro | 1 GB RAM; 12-month trial limit |
| Azure B1S | 1 GB RAM; trial period only |
| Render free tier | Spins down after 15 min inactivity; Traccar cannot cold-start |
| Railway / Fly.io | No longer true always-free; usage-based credits |
| Hetzner ~$4/month | Best paid fallback if Oracle unavailable; 2 vCPU / 4 GB |

---

### 3.16 Data Retention

**Decision:** Traccar position and event data pruned to 30-day rolling window.

**Rationale:** Traccar stores all positions regardless of whether the admin app surfaces history. Without pruning, data accumulates indefinitely on a 200 GB volume. 30 days is a reasonable default for a live-tracking system with no analytics requirement.

**Implementation:** Scheduled cron job or Traccar's built-in cleanup. Small batch deletes to avoid blocking ingest.

---

### 3.17 Device Removal Contract (Explicit)

When the admin removes a device, the relay must perform both steps in order:

```text
1. Send FCM { "command": "removed" } to reporter (best-effort; may not be delivered)
2. DELETE /api/devices/{traccar_device_id} via Traccar API (authoritative)
```

Step 2 is non-optional. Deleting the Traccar device invalidates the `ingestToken` at the server level. Even if the reporter app is not stopped due to OEM interference or a missed FCM command, any subsequent OsmAnd ingest posts will be rejected because the device no longer exists in Traccar. The FCM command is best-effort; the Traccar deletion is the enforcement mechanism.

---

## 4. Android Manifest — Reporter App (Complete, Android 14+)

```xml
<!-- Foreground service -->
<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>

<!-- Location-typed FGS on Android 14+ -->
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION"/>

<!-- Location access -->
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION"/>

<!-- Reboot recovery -->
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>

<!-- Battery optimization exemption -->
<uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS"/>

<!-- FGS notification visibility on Android 13+ -->
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>

<service
    android:name=".LocationForegroundService"
    android:foregroundServiceType="location"
    android:exported="false"/>

<receiver
    android:name=".BootReceiver"
    android:exported="true">
    <intent-filter>
        <action android:name="android.intent.action.BOOT_COMPLETED"/>
    </intent-filter>
</receiver>
```

**`POST_NOTIFICATIONS`:** Required on Android 13+ for the FGS notification to appear. If denied, tracking cannot be confirmed active. Treat as blocking.

**`foregroundServiceType="location"`:** Without this on Android 14+, `startForeground()` throws `MissingForegroundServiceTypeException`.

**Background start constraint:** A location-typed FGS cannot be started while the app is in the background unless `ACCESS_BACKGROUND_LOCATION` is granted. This is why background location is a mandatory bootstrap permission.

---

## 5. Repository Structure

```text
family-tracker/
├── apps/
│   ├── admin_app/
│   │   └── lib/
│   │       ├── auth/
│   │       ├── map/
│   │       ├── devices/
│   │       ├── geofences/
│   │       ├── approvals/
│   │       └── notifications/
│   └── reporter_app/
│       └── lib/
│           ├── bootstrap/
│           ├── permissions/
│           ├── device_identity/
│           ├── tracking_service/
│           ├── mode_control/
│           ├── push_commands/
│           └── storage/
├── packages/
│   └── tracker_core/
│       └── lib/
│           ├── api/
│           │   ├── traccar_client.dart
│           │   └── relay_client.dart
│           ├── models/
│           │   ├── device.dart
│           │   ├── position.dart
│           │   ├── geofence.dart
│           │   ├── join_request.dart
│           │   └── command.dart
│           ├── ws/
│           │   └── live_updates.dart
│           ├── auth/
│           │   └── session_store.dart
│           └── util/
│               └── retry.dart
├── services/
│   └── notify_relay/
│       ├── cmd/server/main.go
│       ├── internal/
│       │   ├── http/
│       │   │   ├── join.go
│       │   │   ├── approve.go
│       │   │   ├── remove.go
│       │   │   ├── status.go
│       │   │   └── webhook.go
│       │   ├── fcm/
│       │   │   └── client.go
│       │   ├── traccar/
│       │   │   └── client.go
│       │   └── store/
│       │       └── postgres.go
│       └── migrations/
│           └── *.sql
├── deploy/
│   ├── traccar/
│   │   └── traccar.xml
│   ├── docker/
│   │   └── docker-compose.yml
│   └── caddy/
│       └── Caddyfile
└── docs/
    └── architecture/
        └── decisions.md
```

---

## 6. Relay Database Schema

```sql
-- All tables in the relay schema.
-- Traccar schema is managed entirely by Traccar; relay_user has no access to it.

CREATE TYPE approval_status AS ENUM ('pending', 'approved', 'rejected', 'removed');
CREATE TYPE tracking_mode AS ENUM ('idle', 'live');

-- Stores all join requests including pending, approved, and removed devices.
CREATE TABLE pending_devices (
    id BIGSERIAL PRIMARY KEY,
    android_id TEXT UNIQUE NOT NULL,
    device_model TEXT NOT NULL,
    fcm_token TEXT NOT NULL,
    app_version TEXT,
    os_version TEXT,
    status approval_status NOT NULL DEFAULT 'pending',
    traccar_device_id BIGINT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Runtime state for approved reporter devices.
CREATE TABLE reporter_device_meta (
    id BIGSERIAL PRIMARY KEY,
    traccar_device_id BIGINT UNIQUE NOT NULL,
    android_id TEXT UNIQUE NOT NULL,
    fcm_token TEXT NOT NULL,
    state approval_status NOT NULL,
    mode tracking_mode NOT NULL DEFAULT 'idle',
    live_expires_at TIMESTAMPTZ,
    last_command TEXT,
    last_command_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Admin FCM tokens. One token per user per platform.
-- Always upsert on token refresh — never insert a new row.
CREATE TABLE admin_push_tokens (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL,
    fcm_token TEXT UNIQUE NOT NULL,
    platform TEXT NOT NULL DEFAULT 'android',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (user_id, platform) -- upsert target; prevents stale token accumulation
);
```

---

## 7. Relay HTTP Endpoints

| Method | Path | Caller | Purpose |
|---|---|---|---|
| `POST` | `/join` | Reporter | Submit join request |
| `GET` | `/api/device/status?androidId=` | Reporter | Polling fallback for approval |
| `GET` | `/admin/pending` | Admin app | List pending devices |
| `POST` | `/admin/approve/{pendingId}` | Admin app | Approve device |
| `POST` | `/admin/remove/{id}` | Admin app | Remove pending or active device |
| `POST` | `/admin/live/{deviceId}` | Admin app | Trigger LIVE mode with `expiresAt` |
| `POST` | `/admin/fcm-token` | Admin app | Register or refresh admin FCM token |
| `POST` | `/webhook/traccar/event` | Traccar | Geofence event forward receiver |

Admin endpoints require bearer token auth. Webhook endpoint requires shared secret header (`X-Relay-Secret`). `/join` and `/api/device/status` require rate limiting.

---

## 8. Traccar Configuration (v1 Essentials)

```xml
<!-- traccar.xml — key settings only; all other settings use Traccar defaults -->

<!-- Security: only relay-provisioned devices may post positions -->
<entry key='database.registerUnknown'>false</entry>

<!-- OsmAnd ingest protocol listener -->
<entry key='osmand.port'>5055</entry>

<!-- Geofence event forwarding to relay webhook -->
<entry key='event.forward.type'>json</entry>
<entry key='event.forward.url'>https://relay.example.com/webhook/traccar/event</entry>
<entry key='event.forward.header'>X-Relay-Secret: YOUR_SHARED_SECRET</entry>

<!-- PostgreSQL: traccar schema, traccar_user only -->
<entry key='database.driver'>org.postgresql.Driver</entry>
<entry key='database.url'>jdbc:postgresql://localhost/postgres?currentSchema=traccar</entry>
<entry key='database.user'>traccar_user</entry>
<entry key='database.password'>TRACCAR_DB_PASSWORD</entry>
```

---

## 9. Required Software and Accounts

| Software / Service | Purpose | Notes |
|---|---|---|
| Oracle Cloud account | Hosting | ARM capacity may be limited at signup; have fallback region ready |
| Docker + Docker Compose | Service orchestration | All services run containerised |
| Traccar Server | Tracking engine | Pin version in `deploy/traccar/`; never `latest` |
| PostgreSQL 15+ | Persistence | Docker container |
| Caddy or nginx | TLS + reverse proxy | Covers port 8082 (API/WS) and OsmAnd ingest port |
| Go 1.22+ | Relay build | Pin in `go.mod` |
| Flutter 3.x | Mobile builds | Pin in `.fvmrc` or `pubspec.yaml` |
| Firebase project | FCM | Generate service account JSON key for relay; one project covers both apps |
| Android Studio or VS Code | Mobile development | Flutter and Dart plugins required |
| Android 12+ physical device | Testing | OEM battery behavior cannot be reproduced on emulator |
| Domain name | TLS certificates | Required for Let's Encrypt; A record points to OCI instance public IP |

---

## 10. Build Phases

| Phase | Scope |
|---|---|
| 1 | Infrastructure bootstrap (see §10.1 checklist) |
| 2 | `tracker_core` package: DTOs, client abstractions, serialization formats locked |
| 3 | Relay service: join endpoint, pending storage, approve/remove flows, Traccar device creation/deletion, FCM token registration, polling status endpoint |
| 4 | Reporter app: permission bootstrap sequence, join request, FCM setup, foreground service, reconcile loop, IDLE mode posting |
| 5 | Admin app: login + session, device list, map + LERP markers, live WebSocket updates, approvals UI, rename/remove, Track Live trigger |
| 6 | Geofence alerts: Traccar webhook receiver in relay, FCM push to admin, deep link into map/device state |
| 7 | Hardening: reboot recovery, FCM token refresh, OEM battery optimization prompts, offline/reconnect, error states, data retention cron |

### 10.1 Phase 1 Checklist (Start Here)

1. Bring up PostgreSQL + Traccar locally via Docker Compose.
2. Verify Traccar admin login and REST API (`GET /api/devices`, `GET /api/session`).
3. Verify `/api/socket` WebSocket connects using `JSESSIONID` session cookie.
4. Configure OsmAnd ingest: post a test position and confirm it appears in Traccar positions table.
5. Configure geofence event forwarding to a placeholder relay endpoint (e.g., `https://webhook.site` for initial testing).
6. Pin the Traccar Docker image tag that passes all five verifications above.

---

## 11. Build-Time Decisions

Resolve during implementation. No architecture impact.

| Decision | Default |
|---|---|
| OsmAnd ingest port | 5055 (Traccar default) |
| Pending poll interval | 5 minutes |
| LIVE mode default duration | 30 minutes (admin-configurable) |
| Traccar Docker image tag | Pin at Phase 1 step 6 |
| PostgreSQL schema names | `traccar` and `relay` |
| WorkManager watchdog | Add only if Xiaomi / Huawei / Honor / OPPO devices are in the family |
| Command idempotency / ack | Add `commandId` + ack loop if FCM reliability proves insufficient in Phase 7 testing |
| `ANDROID_ID` re-registration warning | Surface in admin pending list when same `device_model` + `os_version` appears after an existing approved device |

---

## 12. Canonical Reference URLs

| Topic | URL |
|---|---|
| Oracle Always Free resources | [https://docs.oracle.com/en-us/iaas/Content/FreeTier/freetier_topic-Always_Free-Resources.htm](https://docs.oracle.com/en-us/iaas/Content/FreeTier/freetier_topic-Always_Free-Resources.htm) |
| Android: request location permissions at runtime | [https://developer.android.com/develop/sensors-and-location/location/permissions/runtime](https://developer.android.com/develop/sensors-and-location/location/permissions/runtime) |
| Android: notification runtime permission (API 33+) | [https://developer.android.com/develop/ui/views/notifications/notification-permission](https://developer.android.com/develop/ui/views/notifications/notification-permission) |
| Android: foreground service types (Android 14+) | [https://developer.android.com/develop/background-work/services/fg-service-types](https://developer.android.com/develop/background-work/services/fg-service-types) |
| Traccar API documentation | [https://www.traccar.org/traccar-api/](https://www.traccar.org/traccar-api/) |
| Traccar OsmAnd protocol | [https://www.traccar.org/osmand/](https://www.traccar.org/osmand/) |
| Traccar event forwarding | [https://www.traccar.org/event-forwarding/](https://www.traccar.org/event-forwarding/) |", I have installed Ubuntu 26.04 and ready to start building this project
