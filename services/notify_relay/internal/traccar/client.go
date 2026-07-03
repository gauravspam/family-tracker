package traccar

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"
)

type Device struct {
	ID       int64  `json:"id"`
	Name     string `json:"name"`
	UniqueID string `json:"uniqueId"`
}

type Client struct {
	base     string
	email    string
	password string
	hc       *http.Client
	cookie   string
}

func New(base, email, password string) *Client {
	return &Client{
		base:     base,
		email:    email,
		password: password,
		hc:       &http.Client{Timeout: 15 * time.Second},
	}
}

func (c *Client) auth(ctx context.Context) error {
	body := fmt.Sprintf("email=%s&password=%s", c.email, c.password)
	req, _ := http.NewRequestWithContext(ctx, "POST", c.base+"/api/session", bytes.NewBufferString(body))
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	resp, err := c.hc.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		b, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("traccar auth %d: %s", resp.StatusCode, b)
	}
	for _, ck := range resp.Cookies() {
		if ck.Name == "JSESSIONID" {
			c.cookie = ck.Value
			return nil
		}
	}
	return fmt.Errorf("no JSESSIONID")
}

func (c *Client) do(ctx context.Context, method, path string, payload any) (*http.Response, error) {
	if c.cookie == "" {
		if err := c.auth(ctx); err != nil {
			return nil, err
		}
	}
	var buf io.Reader
	if payload != nil {
		b, _ := json.Marshal(payload)
		buf = bytes.NewReader(b)
	}
	req, _ := http.NewRequestWithContext(ctx, method, c.base+path, buf)
	req.Header.Set("Cookie", "JSESSIONID="+c.cookie)
	if payload != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	resp, err := c.hc.Do(req)
	if err != nil {
		return nil, err
	}
	if resp.StatusCode == 401 {
		resp.Body.Close()
		c.cookie = ""
		if err := c.auth(ctx); err != nil {
			return nil, err
		}
		if payload != nil {
			b, _ := json.Marshal(payload)
			buf = bytes.NewReader(b)
		}
		req2, _ := http.NewRequestWithContext(ctx, method, c.base+path, buf)
		req2.Header.Set("Cookie", "JSESSIONID="+c.cookie)
		if payload != nil {
			req2.Header.Set("Content-Type", "application/json")
		}
		return c.hc.Do(req2)
	}
	return resp, nil
}

func (c *Client) CreateDevice(ctx context.Context, name, uniqueID string) (Device, error) {
	resp, err := c.do(ctx, "POST", "/api/devices", map[string]string{
		"name": name, "uniqueId": uniqueID,
	})
	if err != nil {
		return Device{}, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		b, _ := io.ReadAll(resp.Body)
		return Device{}, fmt.Errorf("create device %d: %s", resp.StatusCode, b)
	}
	var d Device
	return d, json.NewDecoder(resp.Body).Decode(&d)
}

func (c *Client) DeleteDevice(ctx context.Context, id int64) error {
	resp, err := c.do(ctx, "DELETE", fmt.Sprintf("/api/devices/%d", id), nil)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != 204 && resp.StatusCode != 200 {
		b, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("delete device %d: %s", resp.StatusCode, b)
	}
	return nil
}

// RenameDevice fetches the current device, mutates the name, and PUTs it back.
// Traccar requires the full object on PUT.
func (c *Client) RenameDevice(ctx context.Context, id int64, newName string) error {
	getResp, err := c.do(ctx, "GET", fmt.Sprintf("/api/devices?id=%d", id), nil)
	if err != nil {
		return err
	}
	defer getResp.Body.Close()

	if getResp.StatusCode != 200 {
		b, _ := io.ReadAll(getResp.Body)
		return fmt.Errorf("fetch device %d: %s", getResp.StatusCode, b)
	}

	var list []map[string]any
	if err := json.NewDecoder(getResp.Body).Decode(&list); err != nil {
		return fmt.Errorf("decode device list: %w", err)
	}
	if len(list) == 0 {
		return fmt.Errorf("device %d not found", id)
	}

	obj := list[0]
	obj["name"] = newName

	putResp, err := c.do(ctx, "PUT", fmt.Sprintf("/api/devices/%d", id), obj)
	if err != nil {
		return err
	}
	defer putResp.Body.Close()
	if putResp.StatusCode != 200 {
		b, _ := io.ReadAll(putResp.Body)
		return fmt.Errorf("rename device %d: %s", putResp.StatusCode, b)
	}
	return nil
}

// SetDeviceAttributes merges the given key/value map into the device's
// attributes JSON and writes it back to Traccar via PUT.
func (c *Client) SetDeviceAttributes(ctx context.Context, id int64, attrs map[string]string) error {
	getResp, err := c.do(ctx, "GET", fmt.Sprintf("/api/devices?id=%d", id), nil)
	if err != nil {
		return err
	}
	defer getResp.Body.Close()

	if getResp.StatusCode != 200 {
		b, _ := io.ReadAll(getResp.Body)
		return fmt.Errorf("fetch device %d: %s", getResp.StatusCode, b)
	}

	var list []map[string]any
	if err := json.NewDecoder(getResp.Body).Decode(&list); err != nil {
		return fmt.Errorf("decode device list: %w", err)
	}
	if len(list) == 0 {
		return fmt.Errorf("device %d not found", id)
	}

	obj := list[0]
	existing, _ := obj["attributes"].(map[string]any)
	if existing == nil {
		existing = map[string]any{}
	}
	for k, v := range attrs {
		existing[k] = v
	}
	obj["attributes"] = existing

	putResp, err := c.do(ctx, "PUT", fmt.Sprintf("/api/devices/%d", id), obj)
	if err != nil {
		return err
	}
	defer putResp.Body.Close()
	if putResp.StatusCode != 200 {
		b, _ := io.ReadAll(putResp.Body)
		return fmt.Errorf("set attributes %d: %s", putResp.StatusCode, b)
	}
	return nil
}
