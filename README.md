# Family Tracker

Real-time location tracking for your family. Admin app monitors all devices on a live map with geofence alerts, trails, and live tracking. Reporter app runs silently on family members' phones and shares location only when requested.

## Apps

| App | Build | Download |
|---|---|---|
| **Admin** — Monitor family on a live map, manage geofences, trigger live tracking | Flutter / Dart | [Admin-v3.0.apk](https://github.com/gauravspam/family-tracker/releases/latest/download/Admin-v3.0.apk) |
| **Reporter** — Lightweight, no background GPS until admin requests it | Kotlin / Android | [Reporter-v3.0.apk](https://github.com/gauravspam/family-tracker/releases/latest/download/Reporter-v3.0.apk) |

## Features

- **Live map** — See all family members' locations in real time
- **Geofence alerts** — Get notified when someone enters/exits Home, Garage, or custom zones
- **Live tracking** — Request continuous high-frequency GPS for 30 minutes
- **One-shot locate** — Get a single position fix on demand
- **Offline resilience** — Shows last-known data with red banner when connection drops
- **Activity detection** — Speed-based inference (still/walking/running/vehicle)
- **Crash reporting** — Rotating crash logs viewable from About screen
- **Event history** — Complete geofence enter/exit log with device names

## Services

- **Traccar** — GPS tracking server (PostgreSQL, port 8082 API, 5055 ingest)
- **Relay** — Go middleware for approval, live mode, FCM, webhook forwarding

## Screenshots

| Map | Devices |
|:---:|:---:|
| ![Map](Screenshots/Map%20-%20Normal.png) | ![Devices](Screenshots/Devices%20Tab.png) |

| Details | Live Mode |
|:---:|:---:|
| ![Details](Screenshots/Details%20Tab.png) | ![Live](Screenshots/Live%20Mode%20-%20Details.png) |
