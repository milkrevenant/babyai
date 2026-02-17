package server

import (
	"net/http"
	"testing"
)

func TestGetMySettingsReturnsSystemByDefault(t *testing.T) {
	resetDatabase(t)
	fixture := seedOwnerFixture(t)

	rec := performRequest(
		t,
		newTestRouter(t),
		http.MethodGet,
		"/api/v1/settings/me",
		signToken(t, fixture.UserID, nil),
		nil,
		nil,
	)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d body=%s", rec.Code, rec.Body.String())
	}

	body := decodeJSONMap(t, rec)
	if body["theme_mode"] != "system" {
		t.Fatalf("expected default theme_mode=system, got %v", body["theme_mode"])
	}
}

func TestUpsertMySettingsPersistsThemeMode(t *testing.T) {
	resetDatabase(t)
	fixture := seedOwnerFixture(t)

	updateRec := performRequest(
		t,
		newTestRouter(t),
		http.MethodPatch,
		"/api/v1/settings/me",
		signToken(t, fixture.UserID, nil),
		map[string]any{
			"theme_mode": "dark",
		},
		nil,
	)
	if updateRec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d body=%s", updateRec.Code, updateRec.Body.String())
	}

	updateBody := decodeJSONMap(t, updateRec)
	if updateBody["theme_mode"] != "dark" {
		t.Fatalf("expected updated theme_mode=dark, got %v", updateBody["theme_mode"])
	}

	getRec := performRequest(
		t,
		newTestRouter(t),
		http.MethodGet,
		"/api/v1/settings/me",
		signToken(t, fixture.UserID, nil),
		nil,
		nil,
	)
	if getRec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d body=%s", getRec.Code, getRec.Body.String())
	}
	getBody := decodeJSONMap(t, getRec)
	if getBody["theme_mode"] != "dark" {
		t.Fatalf("expected persisted theme_mode=dark, got %v", getBody["theme_mode"])
	}
}

func TestUpsertMySettingsRejectsInvalidThemeMode(t *testing.T) {
	resetDatabase(t)
	fixture := seedOwnerFixture(t)

	rec := performRequest(
		t,
		newTestRouter(t),
		http.MethodPatch,
		"/api/v1/settings/me",
		signToken(t, fixture.UserID, nil),
		map[string]any{
			"theme_mode": "blue",
		},
		nil,
	)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d body=%s", rec.Code, rec.Body.String())
	}
	if detail := responseDetail(t, rec); detail != "theme_mode must be one of: system, dark, light" {
		t.Fatalf("unexpected detail: %q", detail)
	}
}
