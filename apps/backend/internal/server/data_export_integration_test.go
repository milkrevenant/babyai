package server

import (
	"net/http"
	"strings"
	"testing"
	"time"
)

func TestExportBabyDataCSV(t *testing.T) {
	resetDatabase(t)
	fixture := seedOwnerFixture(t)
	seedEvent(
		t,
		"",
		fixture.BabyID,
		"FORMULA",
		time.Now().UTC().Add(-2*time.Hour),
		nil,
		map[string]any{"ml": 140, "memo": "after nap"},
		fixture.UserID,
	)

	rec := performRequest(
		t,
		newTestRouter(t),
		http.MethodGet,
		"/api/v1/data/export.csv?baby_id="+fixture.BabyID,
		signToken(t, fixture.UserID, nil),
		nil,
		nil,
	)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d body=%s", rec.Code, rec.Body.String())
	}

	contentType := rec.Header().Get("Content-Type")
	if !strings.Contains(contentType, "text/csv") {
		t.Fatalf("expected text/csv content type, got %q", contentType)
	}
	if err := ensureCSVContainsHeader(rec.Body.String()); err != nil {
		t.Fatalf("expected csv header, got err=%v body=%s", err, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), "FORMULA") {
		t.Fatalf("expected FORMULA row in csv, body=%s", rec.Body.String())
	}
}

func TestExportBabyDataCSVRequiresBabyID(t *testing.T) {
	resetDatabase(t)
	fixture := seedOwnerFixture(t)

	rec := performRequest(
		t,
		newTestRouter(t),
		http.MethodGet,
		"/api/v1/data/export.csv",
		signToken(t, fixture.UserID, nil),
		nil,
		nil,
	)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d body=%s", rec.Code, rec.Body.String())
	}
	if detail := responseDetail(t, rec); detail != "baby_id is required" {
		t.Fatalf("unexpected detail: %q", detail)
	}
}
