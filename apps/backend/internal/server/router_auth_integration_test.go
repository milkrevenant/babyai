package server

import (
	"net/http"
	"strings"
	"testing"
)

func TestHealthOK(t *testing.T) {
	router := newTestRouter(t)
	rec := performRequest(t, router, http.MethodGet, "/health", "", nil, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected status 200, got %d body=%s", rec.Code, rec.Body.String())
	}

	body := decodeJSONMap(t, rec)
	if body["status"] != "ok" {
		t.Fatalf("expected status=ok, got %v", body["status"])
	}
	if body["service"] != "babylog-api" {
		t.Fatalf("expected service=babylog-api, got %v", body["service"])
	}
}

func TestProtectedEndpointRejectsMissingBearerToken(t *testing.T) {
	router := newTestRouter(t)
	rec := performRequest(
		t,
		router,
		http.MethodGet,
		"/api/v1/quick/today-summary?baby_id="+testID(),
		"",
		nil,
		nil,
	)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d body=%s", rec.Code, rec.Body.String())
	}
	if detail := responseDetail(t, rec); detail != "Bearer token required" {
		t.Fatalf("expected Bearer token required, got %q", detail)
	}
}

func TestProtectedEndpointRejectsMalformedToken(t *testing.T) {
	router := newTestRouter(t)
	rec := performRequest(
		t,
		router,
		http.MethodGet,
		"/api/v1/quick/today-summary?baby_id="+testID(),
		"not-a-jwt",
		nil,
		nil,
	)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d body=%s", rec.Code, rec.Body.String())
	}
	if detail := responseDetail(t, rec); detail != "Invalid bearer token" {
		t.Fatalf("expected invalid bearer token detail, got %q", detail)
	}
}

func TestProtectedEndpointRejectsTokenWithoutSub(t *testing.T) {
	router := newTestRouter(t)
	token := signToken(t, "", nil)

	rec := performRequest(
		t,
		router,
		http.MethodGet,
		"/api/v1/quick/today-summary?baby_id="+testID(),
		token,
		nil,
		nil,
	)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d body=%s", rec.Code, rec.Body.String())
	}
	if detail := responseDetail(t, rec); detail != "Token subject missing" {
		t.Fatalf("expected token subject missing detail, got %q", detail)
	}
}

func TestProtectedEndpointRejectsAudienceMismatch(t *testing.T) {
	cfg := baseTestConfig
	cfg.JWTAudience = "expected-audience"
	router := newTestRouterWithConfig(t, cfg)
	token := signTokenWithConfig(
		t,
		cfg,
		testID(),
		map[string]any{"aud": "wrong-audience"},
	)

	rec := performRequest(
		t,
		router,
		http.MethodGet,
		"/api/v1/quick/today-summary?baby_id="+testID(),
		token,
		nil,
		nil,
	)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d body=%s", rec.Code, rec.Body.String())
	}
	if detail := responseDetail(t, rec); detail != "Invalid token audience" {
		t.Fatalf("expected invalid token audience detail, got %q", detail)
	}
}

func TestProtectedEndpointRejectsIssuerMismatch(t *testing.T) {
	cfg := baseTestConfig
	cfg.JWTIssuer = "expected-issuer"
	router := newTestRouterWithConfig(t, cfg)
	token := signTokenWithConfig(
		t,
		cfg,
		testID(),
		map[string]any{"iss": "wrong-issuer"},
	)

	rec := performRequest(
		t,
		router,
		http.MethodGet,
		"/api/v1/quick/today-summary?baby_id="+testID(),
		token,
		nil,
		nil,
	)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d body=%s", rec.Code, rec.Body.String())
	}
	if detail := responseDetail(t, rec); detail != "Invalid token issuer" {
		t.Fatalf("expected invalid token issuer detail, got %q", detail)
	}
}

func TestCORSPreflightAllowsConfiguredOrigin(t *testing.T) {
	router := newTestRouter(t)
	origin := "http://localhost:5173"
	rec := performRequest(
		t,
		router,
		http.MethodOptions,
		"/api/v1/events/confirm",
		"",
		nil,
		map[string]string{
			"Origin":                         origin,
			"Access-Control-Request-Method":  "POST",
			"Access-Control-Request-Headers": "Authorization,Content-Type",
		},
	)
	if rec.Code != http.StatusNoContent {
		t.Fatalf("expected 204, got %d body=%s", rec.Code, rec.Body.String())
	}
	if got := rec.Header().Get("Access-Control-Allow-Origin"); got != origin {
		t.Fatalf("expected allow origin %q, got %q", origin, got)
	}
}

func TestCORSPreflightRejectsDisallowedOrigin(t *testing.T) {
	router := newTestRouter(t)
	origin := "https://example.invalid"
	rec := performRequest(
		t,
		router,
		http.MethodOptions,
		"/api/v1/events/confirm",
		"",
		nil,
		map[string]string{
			"Origin":                        origin,
			"Access-Control-Request-Method": "POST",
		},
	)

	if rec.Code != http.StatusNoContent && rec.Code != http.StatusForbidden {
		t.Fatalf("expected 204 or 403 for disallowed origin, got %d body=%s", rec.Code, rec.Body.String())
	}
	if got := rec.Header().Get("Access-Control-Allow-Origin"); strings.TrimSpace(got) != "" {
		t.Fatalf("expected no allow-origin header for disallowed origin, got %q", got)
	}
}
