package store

import (
	"context"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type ApprovalStatus string

const (
	StatusPending  ApprovalStatus = "pending"
	StatusApproved ApprovalStatus = "approved"
	StatusRemoved  ApprovalStatus = "removed"
)

type TrackingMode string

const (
	ModeIdle TrackingMode = "idle"
	ModeLive TrackingMode = "live"
)

type PendingDevice struct {
	ID          int64
	AndroidID   string
	DeviceModel string
	FCMToken    string
	AppVersion  *string
	OSVersion   *string
	Status      ApprovalStatus
	TraccarID   *int64
	CreatedAt   time.Time
}

type ReporterMeta struct {
	ID              int64
	TraccarDeviceID int64
	AndroidID       string
	FCMToken        string
	State           ApprovalStatus
	Mode            TrackingMode
	LiveExpiresAt   *time.Time
	IngestToken     *string
}

/// ApprovedDeviceRow is the join view returned by ListApprovedDevices.
type ApprovedDeviceRow struct {
	PendingID       int64
	TraccarDeviceID int64
	AndroidID       string
	DeviceModel     string
	Mode            TrackingMode
	LiveExpiresAt   *time.Time
}

type Store struct {
	pool *pgxpool.Pool
}

func New(pool *pgxpool.Pool) *Store {
	return &Store{pool: pool}
}

func (s *Store) Ping(ctx context.Context) error {
	return s.pool.Ping(ctx)
}

// ── Pending Devices ──

func (s *Store) InsertPendingDevice(ctx context.Context, d PendingDevice) (int64, error) {
	// Only bump status back to 'pending' when the existing row is not
	// approved or removed. Approved devices should not be re-registered
	// via /join; that path is only for new devices and re-attempts before
	// approval. Removed devices require an admin action to unblock.
	var id int64
	err := s.pool.QueryRow(ctx, `
		INSERT INTO pending_devices
			(android_id, device_model, fcm_token, app_version, os_version, status)
		VALUES ($1, $2, $3, $4, $5, 'pending')
		ON CONFLICT (android_id) DO UPDATE
			SET fcm_token    = EXCLUDED.fcm_token,
			    device_model = EXCLUDED.device_model,
			    app_version  = EXCLUDED.app_version,
			    os_version   = EXCLUDED.os_version,
			    updated_at   = now()
		RETURNING id`,
		d.AndroidID, d.DeviceModel, d.FCMToken, d.AppVersion, d.OSVersion,
	).Scan(&id)
	return id, err
}

func (s *Store) GetPendingDevice(ctx context.Context, id int64) (PendingDevice, error) {
	var d PendingDevice
	err := s.pool.QueryRow(ctx, `
		SELECT id, android_id, device_model, fcm_token, app_version,
		       os_version, status, traccar_device_id, created_at
		FROM pending_devices WHERE id = $1`, id,
	).Scan(&d.ID, &d.AndroidID, &d.DeviceModel, &d.FCMToken,
		&d.AppVersion, &d.OSVersion, &d.Status, &d.TraccarID, &d.CreatedAt)
	return d, err
}

func (s *Store) GetPendingDeviceByAndroidID(ctx context.Context, androidID string) (PendingDevice, error) {
	var d PendingDevice
	err := s.pool.QueryRow(ctx, `
		SELECT id, android_id, device_model, fcm_token, app_version,
		       os_version, status, traccar_device_id, created_at
		FROM pending_devices WHERE android_id = $1`, androidID,
	).Scan(&d.ID, &d.AndroidID, &d.DeviceModel, &d.FCMToken,
		&d.AppVersion, &d.OSVersion, &d.Status, &d.TraccarID, &d.CreatedAt)
	return d, err
}

func (s *Store) GetPendingDeviceByTraccarID(ctx context.Context, traccarID int64) (PendingDevice, error) {
	var d PendingDevice
	err := s.pool.QueryRow(ctx, `
		SELECT id, android_id, device_model, fcm_token, app_version,
		       os_version, status, traccar_device_id, created_at
		FROM pending_devices WHERE traccar_device_id = $1`, traccarID,
	).Scan(&d.ID, &d.AndroidID, &d.DeviceModel, &d.FCMToken,
		&d.AppVersion, &d.OSVersion, &d.Status, &d.TraccarID, &d.CreatedAt)
	return d, err
}

func (s *Store) ListPending(ctx context.Context) ([]PendingDevice, error) {
	rows, err := s.pool.Query(ctx, `
		SELECT id, android_id, device_model, fcm_token, app_version,
		       os_version, status, traccar_device_id, created_at
		FROM pending_devices WHERE status = 'pending'
		ORDER BY created_at ASC`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []PendingDevice
	for rows.Next() {
		var d PendingDevice
		if err := rows.Scan(&d.ID, &d.AndroidID, &d.DeviceModel, &d.FCMToken,
			&d.AppVersion, &d.OSVersion, &d.Status, &d.TraccarID, &d.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, d)
	}
	return out, rows.Err()
}

func (s *Store) ApprovePendingDevice(ctx context.Context, id, traccarID int64) error {
	_, err := s.pool.Exec(ctx, `
		UPDATE pending_devices
		SET status = 'approved', traccar_device_id = $2, updated_at = now()
		WHERE id = $1`, id, traccarID)
	return err
}

func (s *Store) SetPendingStatus(ctx context.Context, id int64, status ApprovalStatus) error {
	_, err := s.pool.Exec(ctx, `
		UPDATE pending_devices SET status = $2, updated_at = now()
		WHERE id = $1`, id, status)
	return err
}

// ── Approved-devices index ──

func (s *Store) ListApprovedDevices(ctx context.Context) ([]ApprovedDeviceRow, error) {
	rows, err := s.pool.Query(ctx, `
		SELECT pd.id, pd.traccar_device_id, pd.android_id, pd.device_model,
		       rdm.mode, rdm.live_expires_at
		FROM pending_devices pd
		JOIN reporter_device_meta rdm
		  ON rdm.traccar_device_id = pd.traccar_device_id
		WHERE pd.status = 'approved'
		  AND rdm.state = 'approved'
		ORDER BY pd.created_at ASC`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []ApprovedDeviceRow
	for rows.Next() {
		var r ApprovedDeviceRow
		var traccarID *int64
		if err := rows.Scan(&r.PendingID, &traccarID, &r.AndroidID,
			&r.DeviceModel, &r.Mode, &r.LiveExpiresAt); err != nil {
			return nil, err
		}
		if traccarID != nil {
			r.TraccarDeviceID = *traccarID
		}
		out = append(out, r)
	}
	return out, rows.Err()
}

// ── Reporter Meta ──

func (s *Store) InsertReporterMeta(ctx context.Context, m ReporterMeta) error {
	_, err := s.pool.Exec(ctx, `
		INSERT INTO reporter_device_meta
			(traccar_device_id, android_id, fcm_token, state, mode, ingest_token)
		VALUES ($1, $2, $3, 'approved', 'idle', $4)`,
		m.TraccarDeviceID, m.AndroidID, m.FCMToken, m.IngestToken)
	return err
}

func (s *Store) GetReporterMetaByTraccarID(ctx context.Context, traccarID int64) (ReporterMeta, error) {
	var m ReporterMeta
	err := s.pool.QueryRow(ctx, `
		SELECT id, traccar_device_id, android_id, fcm_token,
		       state, mode, live_expires_at, ingest_token
		FROM reporter_device_meta WHERE traccar_device_id = $1`, traccarID,
	).Scan(&m.ID, &m.TraccarDeviceID, &m.AndroidID, &m.FCMToken,
		&m.State, &m.Mode, &m.LiveExpiresAt, &m.IngestToken)
	return m, err
}

func (s *Store) GetReporterMetaByAndroidID(ctx context.Context, androidID string) (ReporterMeta, error) {
	var m ReporterMeta
	err := s.pool.QueryRow(ctx, `
		SELECT id, traccar_device_id, android_id, fcm_token,
		       state, mode, live_expires_at, ingest_token
		FROM reporter_device_meta WHERE android_id = $1`, androidID,
	).Scan(&m.ID, &m.TraccarDeviceID, &m.AndroidID, &m.FCMToken,
		&m.State, &m.Mode, &m.LiveExpiresAt, &m.IngestToken)
	return m, err
}

func (s *Store) SetReporterMode(ctx context.Context, traccarID int64, mode TrackingMode, expiresAt *time.Time) error {
	_, err := s.pool.Exec(ctx, `
		UPDATE reporter_device_meta
		SET mode = $2, live_expires_at = $3, updated_at = now()
		WHERE traccar_device_id = $1`, traccarID, mode, expiresAt)
	return err
}

func (s *Store) SetReporterRemoved(ctx context.Context, traccarID int64) error {
	_, err := s.pool.Exec(ctx, `
		UPDATE reporter_device_meta
		SET state = 'removed', updated_at = now()
		WHERE traccar_device_id = $1`, traccarID)
	return err
}

func (s *Store) RecordCommand(ctx context.Context, traccarID int64, cmd string) error {
	_, err := s.pool.Exec(ctx, `
		UPDATE reporter_device_meta
		SET last_command = $2, last_command_at = now(), updated_at = now()
		WHERE traccar_device_id = $1`, traccarID, cmd)
	return err
}

// ── Admin FCM Tokens ──

func (s *Store) UpsertAdminToken(ctx context.Context, userID int64, token string) error {
	_, err := s.pool.Exec(ctx, `
		INSERT INTO admin_push_tokens (user_id, fcm_token, platform)
		VALUES ($1, $2, 'android')
		ON CONFLICT (user_id, platform) DO UPDATE
			SET fcm_token = EXCLUDED.fcm_token, updated_at = now()`,
		userID, token)
	return err
}

func (s *Store) AllAdminTokens(ctx context.Context) ([]string, error) {
	rows, err := s.pool.Query(ctx, `SELECT fcm_token FROM admin_push_tokens`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []string
	for rows.Next() {
		var t string
		if err := rows.Scan(&t); err != nil {
			return nil, err
		}
		out = append(out, t)
	}
	return out, rows.Err()
}

func (s *Store) DeletePendingDevice(ctx context.Context, id int64) error {
	_, err := s.pool.Exec(ctx, `DELETE FROM pending_devices WHERE id = $1`, id)
	return err
}

func (s *Store) DeleteReporterMetaByTraccarID(ctx context.Context, traccarID int64) error {
	_, err := s.pool.Exec(ctx,
		`DELETE FROM reporter_device_meta WHERE traccar_device_id = $1`,
		traccarID,
	)
	return err
}

func (s *Store) UpdateReporterFCMToken(ctx context.Context, traccarID int64, fcmToken string) error {
	_, err := s.pool.Exec(ctx, `
		UPDATE reporter_device_meta
		SET fcm_token = $2, updated_at = now()
		WHERE traccar_device_id = $1`, traccarID, fcmToken)
	return err
}

var ErrNoRows = pgx.ErrNoRows
