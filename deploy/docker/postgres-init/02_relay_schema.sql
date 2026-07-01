SET search_path TO relay;

CREATE TYPE approval_status AS ENUM ('pending', 'approved', 'rejected', 'removed');
CREATE TYPE tracking_mode   AS ENUM ('idle', 'live');

CREATE TABLE pending_devices (
    id              BIGSERIAL PRIMARY KEY,
    android_id      TEXT UNIQUE NOT NULL,
    device_model    TEXT NOT NULL,
    fcm_token       TEXT NOT NULL,
    app_version     TEXT,
    os_version      TEXT,
    status          approval_status NOT NULL DEFAULT 'pending',
    traccar_device_id BIGINT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE reporter_device_meta (
    id                BIGSERIAL PRIMARY KEY,
    traccar_device_id BIGINT UNIQUE NOT NULL,
    android_id        TEXT UNIQUE NOT NULL,
    fcm_token         TEXT NOT NULL,
    state             approval_status NOT NULL,
    mode              tracking_mode NOT NULL DEFAULT 'idle',
    live_expires_at   TIMESTAMPTZ,
    last_command      TEXT,
    last_command_at   TIMESTAMPTZ,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE admin_push_tokens (
    id          BIGSERIAL PRIMARY KEY,
    user_id     BIGINT NOT NULL,
    fcm_token   TEXT UNIQUE NOT NULL,
    platform    TEXT NOT NULL DEFAULT 'android',
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (user_id, platform)
);
