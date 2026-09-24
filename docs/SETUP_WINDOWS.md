# Family Tracker — Fresh Setup on Windows (from zero)

Rebuilds the whole stack on a new Windows laptop: Postgres → Traccar →
relay → reporter APK → admin APK. Tested on Ryzen 5 5500U / 8 GB RAM.

> **Secrets policy:** this repo tracks `secrets/` and `.env.relay*` by
> deliberate convention (see SESSION.md 2026-07-12 entries). Keep the GitHub
> repo **private** — it contains a live FCM private key, DB passwords and the
> release keystore.

---

## 1. Tools (install once)

| Tool | Path used in this guide |
|---|---|
| JDK 17 (Temurin) | `C:\tools\jdk17` |
| Go (≥1.22) | `C:\tools\go` (+ on `PATH`) |
| Portable Postgres 16 | `C:\tools\pgsql` (bin + `data\`) |
| Android SDK (cmdline-tools, platform-tools, build-tools 34, NDK 28.2.13676358) | `C:\tools\android-sdk` |
| Flutter stable (admin app only) | `C:\tools\flutter` |
| Traccar 6.x | `C:\tools\traccar` (`tracker-server.jar` + `conf\`) |
| Git | any |

Environment (per PowerShell session):

```powershell
$env:JAVA_HOME="C:\tools\jdk17"
$env:PATH="C:\tools\jdk17\bin;C:\tools\flutter\bin;$env:PATH"
$env:ANDROID_HOME="C:\tools\android-sdk"
$env:ANDROID_SDK_ROOT="C:\tools\android-sdk"
$env:ANDROID_ADB_SERVER_PORT="5038"   # 5037 is blocked on this machine
```

---

## 2. Clone + Postgres schema

```powershell
git clone https://github.com/gauravspam/family-tracker.git
cd family-tracker
```

Start portable Postgres, then apply the init scripts **as the superuser**
(`postgres`, trust auth locally):

```powershell
C:\tools\pgsql\bin\pg_ctl.exe -D C:\tools\pgsql\data -l C:\tools\pgsql\logfile start
C:\tools\pgsql\bin\psql.exe -h localhost -U postgres -d postgres -f deploy\docker\postgres-init\01_schemas.sql
C:\tools\pgsql\bin\psql.exe -h localhost -U postgres -d postgres -f deploy\docker\postgres-init\02_relay_schema.sql
```

`01` creates `relay_user`/`traccar_user` + schemas.
`02` creates all relay tables **plus the GRANTs** (missing grants = every
`/join` returns HTTP 500) and the `ingest_token` column (missing column =
every approve returns HTTP 500). Both bugs are fixed in the repo — do not
hand-create tables.

Optional full reset: `deploy\windows\init-db.ps1`.

---

## 3. Secrets + env files

| File | How to obtain |
|---|---|
| `secrets/fcm-service-account.json` | Firebase console → family-tracker-df860 → Project settings → Service accounts → **Generate new private key**. Save/rename over this file. Never commit a *new* key without removing the old one from the console. After replacing, delete the `Downloads\family-tracker-df860-*.json` copy. |
| `apps/reporter/app/google-services.json` | Firebase console → Project settings → Your apps → `com.familytracker.reporter` → download. (Both packages are already registered.) |
| `apps/admin_app/android/app/google-services.json` | Same, for `com.familytracker.admin_app`. |
| `secrets/reporter-release.jks` | Restore from backup (passwords in `apps/reporter/app/build.gradle.kts`). Only needed for release builds. |

`google-services.json` is gitignored (`**/google-services.json`) — it must be
placed manually on every fresh clone.

Env files:

```powershell
Copy-Item .env.relay.example .env.relay.windows
```

Edit `.env.relay.windows`: set DB password (must match `01_schemas.sql`),
Traccar user/password, random `RELAY_WEBHOOK_SECRET` / `RELAY_ADMIN_TOKEN`,
and the **current LAN IPs** (see §4):

```powershell
INGEST_URL='http://192.168.1.36:5055'
FCM_SERVICE_ACCOUNT_JSON='C:\Users\Admin\Projects\family-tracker\secrets\fcm-service-account.json'
```

---

## 4. Pin the laptop IP (do once, saves endless pain)

DHCP moves the laptop between `.35/.36/.37` and every move breaks the
reporter URL + ingest URL. Reserve it on the Syrotech router:

1. Router admin → **Network → LAN → IPv4** (LAN Settings).
2. **Edit Reserved IP Address** → add laptop Wi-Fi MAC → `192.168.1.36` →
   Apply Changes. (Do NOT touch the WAN/PPPoE page.)
3. Laptop: `ipconfig /release` then `ipconfig /renew` → confirm `.36`.

Safety net if it ever drifts again: the reporter has a runtime **Server
address** screen (no rebuild needed), and the relay's `INGEST_URL` just needs
a restart after editing.

---

## 5. Traccar

```powershell
Copy-Item deploy\traccar\traccar.windows.xml C:\tools\traccar\conf\traccar.xml
# edit DB/user settings inside if they differ
C:\tools\traccar\start-traccar.ps1   # or: java -jar C:\tools\traccar\tracker-server.jar C:\tools\traccar\conf\traccar.xml
```

Web UI: `http://localhost:8082`. Log in and make sure the user matching
`TRACCAR_ADMIN_USER` / `TRACCAR_ADMIN_PASSWORD` exists (default Traccar admin
is `admin`/`admin` — create `admin@family-tracker.local` or change the env).

---

## 6. Relay

```powershell
C:\Users\Admin\Projects\family-tracker\deploy\windows\start.ps1
```

Expected output:

```
server started
db connected
FCM initialized
relay on :8080
```

(`FCM initialized` followed by `invalid_grant` = the service-account key is
dead → generate a new one per §3 and restart.)

Sanity: `Invoke-RestMethod http://127.0.0.1:8080/healthz` → `{"ok":true}`.

---

## 7. Reporter app (family phones)

Build (JDK 17, ~1 min):

```powershell
cd apps\reporter
.\gradlew assembleDebug
# → app\build\outputs\apk\debug\app-arm64-v8a-debug.apk  (arm64 only)
```

Install — USB (`adb devices`) or wireless debugging:

```powershell
adb pair 192.168.1.35:<pairing-port> <6-digit-code>   # from phone: Wireless debugging → Pair with code
adb connect 192.168.1.35:<debug-port>                 # "IP address & Port" on the phone screen
adb -s 192.168.1.35:<debug-port> install -r <apk>
```

On-phone setup (you do it once per family member): grant all permissions →
**Server address** screen (prefilled from `Config.RELAY_BASE_URL`; type just
the IP if DHCP moved) → Connect & Continue → waiting-for-approval →
approve in the admin app's Pending tab → black screen = tracking.

Re-join with the same Android ID auto-approves against the existing Traccar
device — no duplicate devices.

---

## 8. Admin app (your phone only)

Needs Flutter + Android SDK licenses (`flutter doctor --android-licenses`):

```powershell
cd apps\admin_app
flutter pub get
flutter analyze        # must be clean
flutter build apk --debug
```

⚠️ **RAM warning:** the 8 GB laptop cannot reliably link the Flutter APK
(Gradle daemon OOMs). `android/gradle.properties` is already tuned down
(`-Xmx2G`, `workers.max=1`). If it still OOMs, build on a bigger machine or
CI and copy the APK back for `adb install`.

First launch: server-setup screen → relay URL `http://192.168.1.36:8080`,
Traccar URL `http://192.168.1.36:8082`, relay admin token → sign in.

⋮ menu → **Glass blur** toggle kills all `BackdropFilter`s (header, pill
nav, sheets, pin card, toasts) for weak GPUs; persisted per device.

---

## 9. End-to-end check

1. Reporter: registration → Pending in admin app → Approve → Traccar device
   created, reporter goes black.
2. Admin Devices tab: coordinates + battery + "just now".
3. Map tab: marker + accuracy circle; detail sheet actions (Track Live,
   Route, Ring, Remove) all hit the relay.
4. Ring: reporter phone rings = FCM path proven.

## 10. Troubleshooting (all hit before, all fixed)

| Symptom | Cause → fix |
|---|---|
| `/join` → HTTP 500 | `relay_user` lacks grants → re-run `02_relay_schema.sql` (has GRANTs) |
| Approve → HTTP 500 `internal error` | Old DB missing `reporter_device_meta.ingest_token` → `ALTER TABLE relay.reporter_device_meta ADD COLUMN ingest_token TEXT` |
| `FCM … invalid_grant: Invalid JWT Signature` | Service-account key deleted server-side → new key per §3, restart relay |
| Ring/locate 500 `fcm send failed` | Same FCM cause as above |
| Geofence save → `TraccarUnauthorized` | Stale JSESSIONID (Traccar restarted) → sign out/in in admin app |
| Admin shows offline / reporter can't reach server | Laptop IP drifted → reservation per §4, or reporter Server screen |
| Flutter admin build OOM | See §8 RAM warning |
| Flutter build: `google-services.json is missing` | Place per §3 (admin copy is separate from reporter copy) |
