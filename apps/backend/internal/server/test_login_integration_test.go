package server

import (
	"net/http"
	"testing"
)

func TestTestLoginSuccessAndAuthUse(t *testing.T) {
	resetDatabase(t)

	cfg := baseTestConfig
	cfg.TestLoginEnabled = true
	cfg.TestLoginEmail = "qa@example.com"
	cfg.TestLoginPassword = "qa-password-123"
	cfg.TestLoginName = "QA Tester"

	router := newTestRouterWithConfig(t, cfg)

	unauthorized := performRequest(
		t,
		router,
		http.MethodPost,
		"/auth/test-login",
		"",
		map[string]any{
			"email":    "qa@example.com",
			"password": "wrong-password",
		},
		nil,
	)
	if unauthorized.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401 for wrong password, got %d body=%s", unauthorized.Code, unauthorized.Body.String())
	}

	login := performRequest(
		t,
		router,
		http.MethodPost,
		"/auth/test-login",
		"",
		map[string]any{
			"email":    "qa@example.com",
			"password": "qa-password-123",
		},
		nil,
	)
	if login.Code != http.StatusOK {
		t.Fatalf("expected 200 from test login, got %d body=%s", login.Code, login.Body.String())
	}
	loginBody := decodeJSONMap(t, login)
	token, _ := loginBody["token"].(string)
	if token == "" {
		t.Fatalf("expected token in response, got body=%v", loginBody)
	}

	settings := performRequest(
		t,
		router,
		http.MethodGet,
		"/api/v1/settings/me",
		token,
		nil,
		nil,
	)
	if settings.Code != http.StatusOK {
		t.Fatalf("expected 200 from authenticated settings call, got %d body=%s", settings.Code, settings.Body.String())
	}
}

func TestTestLoginDisabled(t *testing.T) {
	resetDatabase(t)

	cfg := baseTestConfig
	cfg.TestLoginEnabled = false

	router := newTestRouterWithConfig(t, cfg)
	resp := performRequest(
		t,
		router,
		http.MethodPost,
		"/auth/test-login",
		"",
		map[string]any{
			"email":    "qa@example.com",
			"password": "qa-password-123",
		},
		nil,
	)
	if resp.Code != http.StatusNotFound {
		t.Fatalf("expected 404 when test login disabled, got %d body=%s", resp.Code, resp.Body.String())
	}
}
