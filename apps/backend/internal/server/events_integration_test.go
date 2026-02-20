package server

import (
	"context"
	"net/http"
	"strings"
	"testing"
	"time"
)

func TestConfirmEventsRejectsEmptyEvents(t *testing.T) {
	resetDatabase(t)
	fixture := seedOwnerFixture(t)
	clipID := seedVoiceClip(t, "", fixture.HouseholdID, fixture.BabyID, "PARSED")

	rec := performRequest(
		t,
		newTestRouter(t),
		http.MethodPost,
		"/api/v1/events/confirm",
		signToken(t, fixture.UserID, nil),
		map[string]any{
			"clip_id": clipID,
			"events":  []any{},
		},
		nil,
	)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d body=%s", rec.Code, rec.Body.String())
	}
	if detail := responseDetail(t, rec); detail != "events is required" {
		t.Fatalf("unexpected detail: %q", detail)
	}
}

func TestConfirmEventsRejectsInvalidEventType(t *testing.T) {
	resetDatabase(t)
	fixture := seedOwnerFixture(t)
	clipID := seedVoiceClip(t, "", fixture.HouseholdID, fixture.BabyID, "PARSED")

	rec := performRequest(
		t,
		newTestRouter(t),
		http.MethodPost,
		"/api/v1/events/confirm",
		signToken(t, fixture.UserID, nil),
		map[string]any{
			"clip_id": clipID,
			"events": []map[string]any{
				{
					"type":       "NOT_REAL",
					"start_time": time.Now().UTC().Format(time.RFC3339),
				},
			},
		},
		nil,
	)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d body=%s", rec.Code, rec.Body.String())
	}
	if detail := responseDetail(t, rec); detail != "Invalid event type at index 0" {
		t.Fatalf("unexpected detail: %q", detail)
	}
}

func TestConfirmEventsRejectsMissingStartTime(t *testing.T) {
	resetDatabase(t)
	fixture := seedOwnerFixture(t)
	clipID := seedVoiceClip(t, "", fixture.HouseholdID, fixture.BabyID, "PARSED")

	rec := performRequest(
		t,
		newTestRouter(t),
		http.MethodPost,
		"/api/v1/events/confirm",
		signToken(t, fixture.UserID, nil),
		map[string]any{
			"clip_id": clipID,
			"events": []map[string]any{
				{
					"type": "POO",
				},
			},
		},
		nil,
	)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d body=%s", rec.Code, rec.Body.String())
	}
	if detail := responseDetail(t, rec); detail != "start_time is required at index 0" {
		t.Fatalf("unexpected detail: %q", detail)
	}
}

func TestConfirmEventsReturnsNotFoundForMissingClip(t *testing.T) {
	resetDatabase(t)
	fixture := seedOwnerFixture(t)

	rec := performRequest(
		t,
		newTestRouter(t),
		http.MethodPost,
		"/api/v1/events/confirm",
		signToken(t, fixture.UserID, nil),
		map[string]any{
			"clip_id": testID(),
			"events": []map[string]any{
				{
					"type":       "POO",
					"start_time": time.Now().UTC().Format(time.RFC3339),
				},
			},
		},
		nil,
	)
	if rec.Code != http.StatusNotFound {
		t.Fatalf("expected 404, got %d body=%s", rec.Code, rec.Body.String())
	}
	if detail := responseDetail(t, rec); detail != "Voice clip not found" {
		t.Fatalf("unexpected detail: %q", detail)
	}
}

func TestConfirmEventsPersistsNormalizedEventAndUpdatesClipStatus(t *testing.T) {
	resetDatabase(t)
	fixture := seedOwnerFixture(t)
	clipID := seedVoiceClip(t, "", fixture.HouseholdID, fixture.BabyID, "PARSED")
	startTime := time.Now().UTC().Add(-15 * time.Minute).Truncate(time.Second)

	rec := performRequest(
		t,
		newTestRouter(t),
		http.MethodPost,
		"/api/v1/events/confirm",
		signToken(t, fixture.UserID, nil),
		map[string]any{
			"clip_id": clipID,
			"events": []map[string]any{
				{
					"type":       "poo",
					"start_time": startTime.Format(time.RFC3339),
					"value":      map[string]any{"count": 1},
					"metadata":   map[string]any{"source": "test"},
				},
			},
		},
		nil,
	)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d body=%s", rec.Code, rec.Body.String())
	}

	body := decodeJSONMap(t, rec)
	if body["status"] != "CONFIRMED" {
		t.Fatalf("expected status CONFIRMED, got %v", body["status"])
	}
	if got, ok := body["saved_event_count"].(float64); !ok || int(got) != 1 {
		t.Fatalf("expected saved_event_count=1, got %v", body["saved_event_count"])
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	var eventCount int
	if err := testPool.QueryRow(ctx, `SELECT COUNT(*) FROM "Event" WHERE "babyId" = $1`, fixture.BabyID).Scan(&eventCount); err != nil {
		t.Fatalf("query event count: %v", err)
	}
	if eventCount != 1 {
		t.Fatalf("expected 1 saved event, got %d", eventCount)
	}

	var savedType string
	if err := testPool.QueryRow(ctx, `SELECT type FROM "Event" WHERE "babyId" = $1 LIMIT 1`, fixture.BabyID).Scan(&savedType); err != nil {
		t.Fatalf("query saved event type: %v", err)
	}
	if savedType != "POO" {
		t.Fatalf("expected normalized type POO, got %q", savedType)
	}

	var clipStatus string
	if err := testPool.QueryRow(ctx, `SELECT status FROM "VoiceClip" WHERE id = $1`, clipID).Scan(&clipStatus); err != nil {
		t.Fatalf("query clip status: %v", err)
	}
	if clipStatus != "CONFIRMED" {
		t.Fatalf("expected clip status CONFIRMED, got %q", clipStatus)
	}

	var auditCount int
	if err := testPool.QueryRow(
		ctx,
		`SELECT COUNT(*) FROM "AuditLog" WHERE action = 'VOICE_CLIP_CONFIRMED' AND "targetId" = $1`,
		clipID,
	).Scan(&auditCount); err != nil {
		t.Fatalf("query audit log count: %v", err)
	}
	if auditCount != 1 {
		t.Fatalf("expected 1 audit log row, got %d", auditCount)
	}
}

func TestParseVoiceEventCreatesParsedClip(t *testing.T) {
	resetDatabase(t)
	fixture := seedOwnerFixture(t)

	rec := performRequest(
		t,
		newTestRouter(t),
		http.MethodPost,
		"/api/v1/events/voice",
		signToken(t, fixture.UserID, nil),
		map[string]any{
			"baby_id":         fixture.BabyID,
			"transcript_hint": "one poo event",
		},
		nil,
	)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d body=%s", rec.Code, rec.Body.String())
	}

	body := decodeJSONMap(t, rec)
	if body["status"] != "PARSED" {
		t.Fatalf("expected status PARSED, got %v", body["status"])
	}
	clipID, ok := body["clip_id"].(string)
	if !ok || strings.TrimSpace(clipID) == "" {
		t.Fatalf("expected non-empty clip_id, got %v", body["clip_id"])
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	var status string
	if err := testPool.QueryRow(ctx, `SELECT status FROM "VoiceClip" WHERE id = $1`, clipID).Scan(&status); err != nil {
		t.Fatalf("query created clip: %v", err)
	}
	if status != "PARSED" {
		t.Fatalf("expected persisted clip status PARSED, got %q", status)
	}
}

func TestParseVoiceEventRejectsUserWithoutHouseholdAccess(t *testing.T) {
	resetDatabase(t)
	fixture := seedOwnerFixture(t)
	outsiderUserID := seedUser(t, "")

	rec := performRequest(
		t,
		newTestRouter(t),
		http.MethodPost,
		"/api/v1/events/voice",
		signToken(t, outsiderUserID, nil),
		map[string]any{"baby_id": fixture.BabyID},
		nil,
	)
	if rec.Code != http.StatusForbidden {
		t.Fatalf("expected 403, got %d body=%s", rec.Code, rec.Body.String())
	}
	if detail := responseDetail(t, rec); detail != "Household access denied" {
		t.Fatalf("unexpected detail: %q", detail)
	}
}
