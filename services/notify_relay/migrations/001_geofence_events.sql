CREATE TABLE IF NOT EXISTS geofence_events (
    id BIGSERIAL PRIMARY KEY,
    traccar_device_id BIGINT NOT NULL,
    geofence_id BIGINT NOT NULL,
    geofence_name TEXT NOT NULL DEFAULT '',
    event_type TEXT NOT NULL,
    device_name TEXT NOT NULL DEFAULT '',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_geofence_events_device ON geofence_events(traccar_device_id);
CREATE INDEX IF NOT EXISTS idx_geofence_events_geofence ON geofence_events(geofence_id);
CREATE INDEX IF NOT EXISTS idx_geofence_events_created ON geofence_events(created_at DESC);
