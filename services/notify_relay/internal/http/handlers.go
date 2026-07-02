package relayhttp

import (
	"context"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/http"
	"strconv"
	"strings"
	"time"

	"family-tracker/relay/internal/fcm"
	"family-tracker/relay/internal/store"
	"family-tracker/relay/internal/traccar"

	"github.com/go-chi/chi/v5"
)

type Config struct {
	AdminToken    string
	WebhookSecret string
	IngestURL     string
}

type Handler struct {
	st  *store.Store
	tc  *traccar.Client
	fc  *fcm.Client
	cfg Config
}

func NewHandler(st *store.Store, tc *traccar.Client, fc *fcm.Client, cfg Config) *Handler {
	return &Handler{st: st, tc: tc, fc: fc, cfg: cfg}
}

func (h *Handler) Routes() http.Handler {
	r := chi.NewRouter()

	r.Get("/healthz", h.healthz)
	r.Post("/join", h.join)
	r.Get("/api/device/status", h.deviceStatus)

	r.Group(func(r chi.Router) {
		r.Use(h.adminAuth)
		r.Get("/admin/pending", h.listPending)
		r.Get("/admin/devices", h.listApprovedDevices)
		r.Post("/admin/approve/{pendingId}", h.approve)
		r.Post("/admin/reject/{pendingId}", h.reject)
		r.Post("/admin/remove/{id}", h.remove)
		r.Delete("/admin/device-by-traccar/{traccarId}", h.removeByTraccarId)
		r.Put("/admin/rename/{traccarId}", h.renameByTraccarId)
		r.Post("/admin/live/{deviceId}", h.live)
		r.Post("/admin/fcm-token", h.registerAdminFCM)
	})

	r.Post("/webhook/traccar/event", h.traccarWebhook)

	return r
}

func (h *Handler) adminAuth(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		auth := r.Header.Get("Authorization")
		token := strings.TrimPrefix(auth, "Bearer ")
		if token == "" || token == auth || token != h.cfg.AdminToken {
			jsonErr(w, 401, "unauthorized")
			return
		}
		next.ServeHTTP(w, r)
	})
}

// ── /healthz ──

func (h *Handler) healthz(w http.ResponseWriter, r *http.Request) {
	if err := h.st.Ping(r.Context()); err != nil {
		http.Error(w, "db down", 503)
		return
	}
	jsonOK(w, map[string]bool{"ok": true})
}

// ── POST /join ──

func (h *Handler) join(w http.ResponseWriter, r *http.Request) {
	var req struct {
		AndroidID   string  `json:"androidId"`
		DeviceModel string  `json:"deviceModel"`
		FCMToken    string  `json:"fcmToken"`
		AppVersion  *string `json:"appVersion"`
		OSVersion   *string `json:"osVersion"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		jsonErr(w, 400, "invalid json")
		return
	}
	if req.AndroidID == "" || req.DeviceModel == "" || req.FCMToken == "" {
		jsonErr(w, 400, "androidId, deviceModel, fcmToken required")
		return
	}
	_, err := h.st.InsertPendingDevice(r.Context(), store.PendingDevice{
		AndroidID:   req.AndroidID,
		DeviceModel: req.DeviceModel,
		FCMToken:    req.FCMToken,
		AppVersion:  req.AppVersion,
		OSVersion:   req.OSVersion,
	})
	if err != nil {
		log.Printf("InsertPendingDevice: %v", err)
		jsonErr(w, 500, "internal error")
		return
	}
	w.WriteHeader(202)
	jsonOK(w, map[string]string{"status": "pending"})
}

// ── GET /api/device/status ──

func (h *Handler) deviceStatus(w http.ResponseWriter, r *http.Request) {
	aid := r.URL.Query().Get("androidId")
	if aid == "" {
		jsonErr(w, 400, "androidId required")
		return
	}

	meta, err := h.st.GetReporterMetaByAndroidID(r.Context(), aid)
	if err == nil {
		resp := map[string]any{"status": string(meta.State)}
		if meta.State == store.StatusApproved && meta.IngestToken != nil {
			resp["ingestToken"] = *meta.IngestToken
			resp["ingestUrl"] = h.cfg.IngestURL
		}
		jsonOK(w, resp)
		return
	}
	if !errors.Is(err, store.ErrNoRows) {
		jsonErr(w, 500, "internal error")
		return
	}

	d, err := h.st.GetPendingDeviceByAndroidID(r.Context(), aid)
	if err != nil {
		if errors.Is(err, store.ErrNoRows) {
			jsonOK(w, map[string]string{"status": "unknown"})
			return
		}
		jsonErr(w, 500, "internal error")
		return
	}
	jsonOK(w, map[string]string{"status": string(d.Status)})
}

// ── GET /admin/pending ──

func (h *Handler) listPending(w http.ResponseWriter, r *http.Request) {
	list, err := h.st.ListPending(r.Context())
	if err != nil {
		log.Printf("ListPending: %v", err)
		jsonErr(w, 500, "internal error")
		return
	}
	type item struct {
		ID          int64   `json:"id"`
		AndroidID   string  `json:"androidId"`
		DeviceModel string  `json:"deviceModel"`
		AppVersion  *string `json:"appVersion"`
		OSVersion   *string `json:"osVersion"`
		CreatedAt   string  `json:"createdAt"`
	}
	out := make([]item, 0, len(list))
	for _, d := range list {
		out = append(out, item{
			ID:          d.ID,
			AndroidID:   d.AndroidID,
			DeviceModel: d.DeviceModel,
			AppVersion:  d.AppVersion,
			OSVersion:   d.OSVersion,
			CreatedAt:   d.CreatedAt.Format(time.RFC3339),
		})
	}
	jsonOK(w, out)
}

// ── GET /admin/devices ──
// Approved-device index with the identifiers the admin app needs to call
// remove/live without maintaining its own mapping between Traccar IDs and
// relay pending IDs.

func (h *Handler) listApprovedDevices(w http.ResponseWriter, r *http.Request) {
	list, err := h.st.ListApprovedDevices(r.Context())
	if err != nil {
		log.Printf("ListApprovedDevices: %v", err)
		jsonErr(w, 500, "internal error")
		return
	}
	type item struct {
		PendingID       int64   `json:"pendingId"`
		TraccarDeviceID int64   `json:"traccarDeviceId"`
		AndroidID       string  `json:"androidId"`
		DeviceModel     string  `json:"deviceModel"`
		Mode            string  `json:"mode"`
		LiveExpiresAt   *string `json:"liveExpiresAt,omitempty"`
	}
	out := make([]item, 0, len(list))
	for _, d := range list {
		var exp *string
		if d.LiveExpiresAt != nil {
			s := d.LiveExpiresAt.Format(time.RFC3339)
			exp = &s
		}
		out = append(out, item{
			PendingID:       d.PendingID,
			TraccarDeviceID: d.TraccarDeviceID,
			AndroidID:       d.AndroidID,
			DeviceModel:     d.DeviceModel,
			Mode:            string(d.Mode),
			LiveExpiresAt:   exp,
		})
	}
	jsonOK(w, out)
}

// ── POST /admin/approve/{pendingId} ──

func (h *Handler) approve(w http.ResponseWriter, r *http.Request) {
	pid, err := strconv.ParseInt(chi.URLParam(r, "pendingId"), 10, 64)
	if err != nil {
		jsonErr(w, 400, "invalid pendingId")
		return
	}

	// Optional body: {"name": "Dads Phone"}. Falls back to the reported
	// device model when omitted.
	var body struct {
		Name string `json:"name"`
	}
	if r.ContentLength > 0 {
		_ = json.NewDecoder(r.Body).Decode(&body)
	}

	ctx := r.Context()

	pending, err := h.st.GetPendingDevice(ctx, pid)
	if err != nil {
		if errors.Is(err, store.ErrNoRows) {
			jsonErr(w, 404, "not found")
			return
		}
		jsonErr(w, 500, "internal error")
		return
	}
	if pending.Status != store.StatusPending {
		jsonErr(w, 409, fmt.Sprintf("status is %s", pending.Status))
		return
	}

	deviceName := strings.TrimSpace(body.Name)
	if deviceName == "" {
		deviceName = pending.DeviceModel
	}

	raw := make([]byte, 16)
	if _, err := rand.Read(raw); err != nil {
		jsonErr(w, 500, "token generation failed")
		return
	}
	ingestToken := base64.RawURLEncoding.EncodeToString(raw)

	dev, err := h.tc.CreateDevice(ctx, deviceName, ingestToken)
	if err != nil {
		log.Printf("traccar.CreateDevice: %v", err)
		jsonErr(w, 500, "traccar error")
		return
	}

	if err := h.st.ApprovePendingDevice(ctx, pid, dev.ID); err != nil {
		log.Printf("ApprovePendingDevice: %v", err)
		_ = h.tc.DeleteDevice(ctx, dev.ID)
		jsonErr(w, 500, "internal error")
		return
	}

	tokenStr := ingestToken
	if err := h.st.InsertReporterMeta(ctx, store.ReporterMeta{
		TraccarDeviceID: dev.ID,
		AndroidID:       pending.AndroidID,
		FCMToken:        pending.FCMToken,
		IngestToken:     &tokenStr,
	}); err != nil {
		log.Printf("InsertReporterMeta: %v", err)
	}

	if err := h.fc.SendData(ctx, pending.FCMToken, map[string]string{
		"command":     "approved",
		"ingestToken": ingestToken,
		"ingestUrl":   h.cfg.IngestURL,
	}); err != nil {
		log.Printf("FCM approved: %v (non-fatal)", err)
	}
	_ = h.st.RecordCommand(ctx, dev.ID, "approved")

	jsonOK(w, map[string]any{
		"traccarDeviceId": dev.ID,
		"androidId":       pending.AndroidID,
		"name":            deviceName,
	})
}

// ── POST /admin/reject/{pendingId} ──

func (h *Handler) reject(w http.ResponseWriter, r *http.Request) {
	pid, err := strconv.ParseInt(chi.URLParam(r, "pendingId"), 10, 64)
	if err != nil {
		jsonErr(w, 400, "invalid pendingId")
		return
	}
	ctx := r.Context()

	pending, err := h.st.GetPendingDevice(ctx, pid)
	if err != nil {
		if errors.Is(err, store.ErrNoRows) {
			jsonErr(w, 404, "not found")
			return
		}
		jsonErr(w, 500, "internal error")
		return
	}
	if pending.Status != store.StatusPending {
		jsonErr(w, 409, fmt.Sprintf("status is %s", pending.Status))
		return
	}

	if err := h.st.SetPendingStatus(ctx, pid, store.StatusRemoved); err != nil {
		jsonErr(w, 500, "internal error")
		return
	}
	w.WriteHeader(204)
}

// ── POST /admin/remove/{id} ──

func (h *Handler) remove(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil {
		jsonErr(w, 400, "invalid id")
		return
	}
	ctx := r.Context()

	pending, err := h.st.GetPendingDevice(ctx, id)
	if err != nil {
		if errors.Is(err, store.ErrNoRows) {
			jsonErr(w, 404, "not found")
			return
		}
		jsonErr(w, 500, "internal error")
		return
	}
	h.performRemoval(ctx, w, pending)
}

// ── DELETE /admin/device-by-traccar/{traccarId} ──

func (h *Handler) removeByTraccarId(w http.ResponseWriter, r *http.Request) {
	tid, err := strconv.ParseInt(chi.URLParam(r, "traccarId"), 10, 64)
	if err != nil {
		jsonErr(w, 400, "invalid traccarId")
		return
	}
	ctx := r.Context()

	pending, err := h.st.GetPendingDeviceByTraccarID(ctx, tid)
	if err != nil {
		if errors.Is(err, store.ErrNoRows) {
			jsonErr(w, 404, "not found")
			return
		}
		jsonErr(w, 500, "internal error")
		return
	}
	h.performRemoval(ctx, w, pending)
}

func (h *Handler) performRemoval(ctx context.Context, w http.ResponseWriter, pending store.PendingDevice) {
	// Best-effort: tell the reporter to stop (FCM is stubbed until Phase 5E,
	// so this is currently a no-op but the reporter's next poll will see
	// the device gone and go idle on its own).
	if err := h.fc.SendData(ctx, pending.FCMToken, map[string]string{
		"command": "removed",
	}); err != nil {
		log.Printf("FCM removed: %v (non-fatal)", err)
	}

	// Authoritative: delete from Traccar.
	if pending.TraccarID != nil {
		if err := h.tc.DeleteDevice(ctx, *pending.TraccarID); err != nil {
			log.Printf("traccar.DeleteDevice: %v", err)
			jsonErr(w, 500, "traccar delete failed")
			return
		}
	}

	// Permissive removal: wipe all rows for this device so the same physical
	// phone can re-register cleanly by reinstalling / clearing app data.
	if pending.TraccarID != nil {
		if err := h.st.DeleteReporterMetaByTraccarID(ctx, *pending.TraccarID); err != nil {
			log.Printf("DeleteReporterMeta: %v", err)
		}
	}
	if err := h.st.DeletePendingDevice(ctx, pending.ID); err != nil {
		log.Printf("DeletePendingDevice: %v", err)
	}

	w.WriteHeader(204)
}

// ── POST /admin/live/{deviceId} ──

func (h *Handler) live(w http.ResponseWriter, r *http.Request) {
	tid, err := strconv.ParseInt(chi.URLParam(r, "deviceId"), 10, 64)
	if err != nil {
		jsonErr(w, 400, "invalid deviceId")
		return
	}
	var req struct {
		ExpiresAt string `json:"expiresAt"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		jsonErr(w, 400, "invalid json")
		return
	}
	exp, err := time.Parse(time.RFC3339, req.ExpiresAt)
	if err != nil {
		jsonErr(w, 400, "expiresAt must be RFC3339")
		return
	}
	ctx := r.Context()

	meta, err := h.st.GetReporterMetaByTraccarID(ctx, tid)
	if err != nil {
		if errors.Is(err, store.ErrNoRows) {
			jsonErr(w, 404, "device not found")
			return
		}
		jsonErr(w, 500, "internal error")
		return
	}

	if err := h.st.SetReporterMode(ctx, tid, store.ModeLive, &exp); err != nil {
		jsonErr(w, 500, "internal error")
		return
	}

	if err := h.fc.SendData(ctx, meta.FCMToken, map[string]string{
		"command":   "live_mode",
		"expiresAt": req.ExpiresAt,
	}); err != nil {
		log.Printf("FCM live_mode: %v (non-fatal)", err)
	}
	_ = h.st.RecordCommand(ctx, tid, "live_mode")
	w.WriteHeader(204)
}

// ── POST /admin/fcm-token ──

func (h *Handler) registerAdminFCM(w http.ResponseWriter, r *http.Request) {
	var req struct {
		FCMToken string `json:"fcmToken"`
		UserID   int64  `json:"userId"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		jsonErr(w, 400, "invalid json")
		return
	}
	if req.FCMToken == "" || req.UserID == 0 {
		jsonErr(w, 400, "fcmToken and userId required")
		return
	}
	if err := h.st.UpsertAdminToken(r.Context(), req.UserID, req.FCMToken); err != nil {
		jsonErr(w, 500, "internal error")
		return
	}
	w.WriteHeader(204)
}

// ── POST /webhook/traccar/event ──

func (h *Handler) traccarWebhook(w http.ResponseWriter, r *http.Request) {
	if r.Header.Get("X-Relay-Secret") != h.cfg.WebhookSecret {
		jsonErr(w, 401, "invalid secret")
		return
	}
	var ev struct {
		DeviceID   int64  `json:"deviceId"`
		Type       string `json:"type"`
		GeofenceID *int64 `json:"geofenceId"`
	}
	if err := json.NewDecoder(r.Body).Decode(&ev); err != nil {
		jsonErr(w, 400, "invalid json")
		return
	}
	ctx := r.Context()

	tokens, err := h.st.AllAdminTokens(ctx)
	if err != nil {
		log.Printf("AllAdminTokens: %v", err)
		w.WriteHeader(200)
		return
	}

	data := map[string]string{
		"deviceId":  strconv.FormatInt(ev.DeviceID, 10),
		"eventType": ev.Type,
	}
	if ev.GeofenceID != nil {
		data["geofenceId"] = strconv.FormatInt(*ev.GeofenceID, 10)
	}

	title := "Geofence Alert"
	body := fmt.Sprintf("Device %d: %s", ev.DeviceID, ev.Type)
	if err := h.fc.SendToMany(ctx, tokens, title, body, data); err != nil {
		log.Printf("SendToMany: %v", err)
	}
	w.WriteHeader(200)
}


// ── PUT /admin/rename/{traccarId} ──

func (h *Handler) renameByTraccarId(w http.ResponseWriter, r *http.Request) {
	tid, err := strconv.ParseInt(chi.URLParam(r, "traccarId"), 10, 64)
	if err != nil {
		jsonErr(w, 400, "invalid traccarId")
		return
	}

	var body struct {
		Name string `json:"name"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		jsonErr(w, 400, "invalid json")
		return
	}
	name := strings.TrimSpace(body.Name)
	if name == "" {
		jsonErr(w, 400, "name required")
		return
	}

	if err := h.tc.RenameDevice(r.Context(), tid, name); err != nil {
		log.Printf("traccar.RenameDevice: %v", err)
		jsonErr(w, 500, "rename failed")
		return
	}
	w.WriteHeader(204)
}

// ── helpers ──

func jsonOK(w http.ResponseWriter, v any) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(v)
}

func jsonErr(w http.ResponseWriter, code int, msg string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	json.NewEncoder(w).Encode(map[string]string{"error": msg})
}
