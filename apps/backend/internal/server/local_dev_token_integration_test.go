package server

import (
	"context"
	"net/http"
	"testing"
	"time"
)

func TestIssueLocalDevTokenRejectedOutsideLocalEnv(t *testing.T) {
	router := newTestRouter(t)

	rec := performRequest(
		t,
		router,
		http.MethodPost,
		"/dev/local-token",
		"",
		nil,
		nil,
	)
	if rec.Code != http.StatusNotFound {
		t.Fatalf("expected 404, got %d body=%s", rec.Code, rec.Body.String())
	}
	if detail := responseDetail(t, rec); detail != "Not found" {
		t.Fatalf("expected not found detail, got %q", detail)
	}
}

func TestIssueLocalDevTokenInvalidSub(t *testing.T) {
	cfg := baseTestConfig
	cfg.AppEnv = "local"
	router := newTestRouterWithConfig(t, cfg)

	rec := performRequest(
		t,
		router,
		http.MethodPost,
		"/dev/local-token?sub=bad-id",
		"",
		nil,
		nil,
	)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d body=%s", rec.Code, rec.Body.String())
	}
	if detail := responseDetail(t, rec); detail != "sub must be UUID format" {
		t.Fatalf("expected UUID validation detail, got %q", detail)
	}
}

func TestIssueLocalDevTokenProducesUsableBearer(t *testing.T) {
	resetDatabase(t)

	cfg := baseTestConfig
	cfg.AppEnv = "local"
	cfg.AuthAutoCreateUser = false
	router := newTestRouterWithConfig(t, cfg)

	rec := performRequest(
		t,
		router,
		http.MethodPost,
		"/dev/local-token",
		"",
		nil,
		nil,
	)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d body=%s", rec.Code, rec.Body.String())
	}

	body := decodeJSONMap(t, rec)
	token, _ := body["token"].(string)
	sub, _ := body["sub"].(string)
	if token == "" {
		t.Fatalf("expected token in response")
	}
	if sub == "" {
		t.Fatalf("expected sub in response")
	}

	probe := performRequest(
		t,
		router,
		http.MethodGet,
		"/api/v1/quick/today-summary?baby_id="+testID(),
		token,
		nil,
		nil,
	)
	if probe.Code == http.StatusUnauthorized {
		t.Fatalf("expected generated token to pass auth, got 401 body=%s", probe.Body.String())
	}

	var exists bool
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	if err := testPool.QueryRow(
		ctx,
		`SELECT EXISTS(SELECT 1 FROM "User" WHERE id = $1)`,
		sub,
	).Scan(&exists); err != nil {
		t.Fatalf("verify local user exists: %v", err)
	}
	if !exists {
		t.Fatalf("expected local user row for sub=%s", sub)
	}
}
