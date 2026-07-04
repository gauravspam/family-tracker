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

### 2. Admin App — Flutter
**APK size:** 19.3 MB release

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
- **Device detail sheet** — full info (coords, address, accuracy, speed, fix time, battery)
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
- **WebSocket** real-time position updates with connection state banner
- **About screen** — app info, server URLs, live connection status, change-server-URLs button
- **Dark mode** (system-driven, iOS-inspired colors)
- **Floating pill bottom nav** with swipe between tabs
- **Transparent floating header** with blur
- **Offline resilience** — cached state preserved on network failure, friendly error messages
- **Orphan device detection** + ORPHAN chip + cleanup via Remove
- **Sign-out confirmation dialog**

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

### 4. Infrastructure
- Traccar 6.6 (pinned Docker image) as tracking engine
- PostgreSQL 15 with `traccar` + `relay` schema separation
- Firebase Cloud Messaging for push commands
- Docker Compose orchestration

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

---

## What's Not Done Yet

### Phase 6: Cloud Deployment
**Status:** Not started
**Plan:**
1. Set up Cloudflare Tunnel on your laptop (`cloudflared` daemon)
2. Map `tracker.yourdomain.com` → `localhost:8080` (relay) and `ingest.yourdomain.com` → `localhost:5055` (OsmAnd)
3. Cloudflare handles TLS automatically (free)
4. Update admin app server URLs to the new HTTPS endpoints
5. Update reporter's `Config.kt` with the public URLs → rebuild APK
6. Test from mobile data (not wifi) — full end-to-end

**Alternative:** Deploy to Oracle Cloud Always Free (ARM instance, 2 OCPU / 12 GB RAM). Docker Compose the whole stack. Point DNS at the OCI public IP.

**Effort:** 1-2 hours for Cloudflare Tunnel. 3-4 hours for full OCI deployment.

### Phase 7: Hardening
**Status:** Not started
**Plan:**
1. **OEM battery optimization prompts** — Xiaomi/Realme/Samsung have their own battery killers. The reporter should detect the OEM and show device-specific instructions (e.g., "Go to Settings → Battery → App launch management → Recorder → Allow background activity")
2. **WorkManager watchdog** — periodic check that the foreground service is still alive. If killed by OEM, restart it.
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

---

## GitHub Releases

- **v1.0.0** — First release with all core features
- **v1.1.0** — UI polish (richer cards, live glow, transparent header, iOS-inspired theme)

Repository: `https://github.com/gauravspam/family-tracker`

---

## Next Session Priority

When you're ready to continue:

1. **Deploy** (Cloudflare Tunnel or OCI) — makes the app actually usable outside your home wifi
2. **Geofences** — draw zones on the map, get push notifications when family enters/exits
3. **Hardening** — OEM battery workarounds, watchdog, data retention

The app is feature-complete for daily family use. The only blocker is deployment.
