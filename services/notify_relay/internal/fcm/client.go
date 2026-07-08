package fcm

import (
	"context"
	"fmt"
	"log"

	firebase "firebase.google.com/go/v4"
	"firebase.google.com/go/v4/messaging"
	"google.golang.org/api/option"
)

type Client struct {
	mc *messaging.Client
}

func New(ctx context.Context, serviceAccountPath string) (*Client, error) {
	app, err := firebase.NewApp(ctx, nil, option.WithCredentialsFile(serviceAccountPath))
	if err != nil {
		return nil, fmt.Errorf("firebase init: %w", err)
	}
	mc, err := app.Messaging(ctx)
	if err != nil {
		return nil, fmt.Errorf("firebase messaging: %w", err)
	}
	return &Client{mc: mc}, nil
}

func (c *Client) SendData(ctx context.Context, token string, data map[string]string) error {
	if c == nil || c.mc == nil {
		log.Printf("FCM not initialized, skipping send to %s", token[:8])
		return nil
	}
	_, err := c.mc.Send(ctx, &messaging.Message{
		Token: token,
		Data:  data,
		Android: &messaging.AndroidConfig{Priority: "high"},
	})
	return err
}

func (c *Client) SendToMany(ctx context.Context, tokens []string, data map[string]string) error {
	if c == nil || c.mc == nil || len(tokens) == 0 {
		return nil
	}
	br, err := c.mc.SendEachForMulticast(ctx, &messaging.MulticastMessage{
		Tokens:  tokens,
		Data:    data,
		Android: &messaging.AndroidConfig{Priority: "high"},
	})
	if err != nil {
		return err
	}
	for i, r := range br.Responses {
		if !r.Success {
			log.Printf("FCM token %d failed: %v", i, r.Error)
		}
	}
	return nil
}
