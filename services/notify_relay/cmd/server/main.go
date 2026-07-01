package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"time"

	"family-tracker/relay/internal/fcm"
	relayhttp "family-tracker/relay/internal/http"
	"family-tracker/relay/internal/store"
	"family-tracker/relay/internal/traccar"

	"github.com/jackc/pgx/v5/pgxpool"
)

func main() {
	ctx := context.Background()

	dbURL         := mustEnv("DATABASE_URL")
	traccarURL    := mustEnv("TRACCAR_BASE_URL")
	traccarUser   := mustEnv("TRACCAR_ADMIN_USER")
	traccarPass   := mustEnv("TRACCAR_ADMIN_PASSWORD")
	fcmKeyPath    := os.Getenv("FCM_SERVICE_ACCOUNT_JSON")
	adminToken    := mustEnv("RELAY_ADMIN_TOKEN")
	webhookSecret := mustEnv("RELAY_WEBHOOK_SECRET")
	ingestURL     := envOr("INGEST_URL", "http://localhost:5055")
	port          := envOr("RELAY_PORT", "8080")

	pool, err := pgxpool.New(ctx, dbURL)
	if err != nil {
		log.Fatalf("pgxpool: %v", err)
	}
	defer pool.Close()
	if err := pool.Ping(ctx); err != nil {
		log.Fatalf("db ping: %v", err)
	}
	log.Println("db connected")

	tc := traccar.New(traccarURL, traccarUser, traccarPass)

	var fc *fcm.Client
	if fcmKeyPath != "" {
		if _, err := os.Stat(fcmKeyPath); err == nil {
			fc, err = fcm.New(ctx, fcmKeyPath)
			if err != nil {
				log.Printf("FCM init failed (non-fatal): %v", err)
			} else {
				log.Println("FCM initialized")
			}
		} else {
			log.Printf("FCM key file not found at %s — FCM disabled", fcmKeyPath)
		}
	} else {
		log.Println("FCM_SERVICE_ACCOUNT_JSON not set — FCM disabled")
	}

	st := store.New(pool)
	h := relayhttp.NewHandler(st, tc, fc, relayhttp.Config{
		AdminToken:    adminToken,
		WebhookSecret: webhookSecret,
		IngestURL:     ingestURL,
	})

	srv := &http.Server{
		Addr:         ":" + port,
		Handler:      h.Routes(),
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 15 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	log.Printf("relay on :%s", port)
	log.Fatal(srv.ListenAndServe())
}

func mustEnv(key string) string {
	v := os.Getenv(key)
	if v == "" {
		log.Fatalf("missing env: %s", key)
	}
	return v
}

func envOr(key, fb string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fb
}
