package server

import (
	"context"
	"encoding/json"
	"net/http"
	"testing"
	"time"
)

func TestStartManualEventCreatesOpenEvent(t *testing.T) {
	resetDatabase(t)
	fixture := seedOwnerFixture(t)
	start := time.Now().UTC().Add(-10 * time.Minute).Truncate(time.Second)

	rec := performRequest(
		t,
		newTestRouter(t),
		http.MethodPost,
		"/api/v1/events/start",
		signToken(t, fixture.UserID, nil),
		map[string]any{
			"baby_id":    fixture.BabyID,
			"type":       "FORMULA",
			"start_time": start.Format(time.RFC3339),
			"value":      map[string]any{"memo": "started"},
		},
		nil,
	)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d body=%s", rec.Code, rec.Body.String())
	}

	body := decodeJSONMap(t, rec)
	eventID, _ := body["event_id"].(string)
	if eventID == "" {
		t.Fatalf("expected event_id, got %v", body["event_id"])
	}
	if body["status"] != "STARTED" {
		t.Fatalf("expected STARTED status, got %v", body["status"])
	}
	if body["event_state"] != "OPEN" {
		t.Fatalf("expected OPEN event_state, got %v", body["event_state"])
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	var status string
	var endTime *time.Time
	if err := testPool.QueryRow(
		ctx,
		`SELECT status, "endTime" FROM "Event" WHERE id = $1`,
		eventID,
	).Scan(&status, &endTime); err != nil {
		t.Fatalf("query event: %v", err)
	}
	if status != "OPEN" {
		t.Fatalf("expected OPEN status, got %q", status)
	}
	if endTime != nil {
		t.Fatalf("expected nil endTime for OPEN event, got %v", endTime)
	}
}

func TestStartManualEventRejectsDuplicateOpenEvent(t *testing.T) {
	resetDatabase(t)
	fixture := seedOwnerFixture(t)
	start := time.Now().UTC().Add(-20 * time.Minute).Truncate(time.Second)
	firstRec := performRequest(
		t,
		newTestRouter(t),
		http.MethodPost,
		"/api/v1/events/start",
		signToken(t, fixture.UserID, nil),
		map[string]any{
			"baby_id":    fixture.BabyID,
			"type":       "FORMULA",
			"start_time": start.Format(time.RFC3339),
		},
		nil,
	)
	if firstRec.Code != http.StatusOK {
		t.Fatalf("expected first request 200, got %d body=%s", firstRec.Code, firstRec.Body.String())
	}
	secondRec := performRequest(
		t,
		newTestRouter(t),
		http.MethodPost,
		"/api/v1/events/start",
		signToken(t, fixture.UserID, nil),
		map[string]any{
			"baby_id":    fixture.BabyID,
			"type":       "FORMULA",
			"start_time": start.Add(2 * time.Minute).Format(time.RFC3339),
		},
		nil,
	)
	if secondRec.Code != http.StatusConflict {
		t.Fatalf("expected 409, got %d body=%s", secondRec.Code, secondRec.Body.String())
	}
	body := decodeJSONMap(t, secondRec)
	if body["detail"] != "open event already exists for this type" {
		t.Fatalf("unexpected conflict detail: %v", body["detail"])
	}
}

func TestCompleteManualEventClosesOpenEvent(t *testing.T) {
	resetDatabase(t)
	fixture := seedOwnerFixture(t)
	start := time.Now().UTC().Add(-15 * time.Minute).Truncate(time.Second)

	startRec := performRequest(
		t,
		newTestRouter(t),
		http.MethodPost,
		"/api/v1/events/start",
		signToken(t, fixture.UserID, nil),
		map[string]any{
			"baby_id":    fixture.BabyID,
			"type":       "FORMULA",
			"start_time": start.Format(time.RFC3339),
			"value":      map[string]any{"memo": "start note"},
		},
		nil,
	)
	if startRec.Code != http.StatusOK {
		t.Fatalf("start request failed: %d body=%s", startRec.Code, startRec.Body.String())
	}
	startBody := decodeJSONMap(t, startRec)
	eventID, _ := startBody["event_id"].(string)
	if eventID == "" {
		t.Fatalf("missing event_id from start response")
	}

	end := time.Now().UTC().Truncate(time.Second)
	completeRec := performRequest(
		t,
		newTestRouter(t),
		http.MethodPatch,
		"/api/v1/events/"+eventID+"/complete",
		signToken(t, fixture.UserID, nil),
		map[string]any{
			"end_time": end.Format(time.RFC3339),
			"value": map[string]any{
				"ml": 130,
			},
			"metadata": map[string]any{
				"completed_by": "test",
			},
		},
		nil,
	)
	if completeRec.Code != http.StatusOK {
		t.Fatalf("complete request failed: %d body=%s", completeRec.Code, completeRec.Body.String())
	}
	completeBody := decodeJSONMap(t, completeRec)
	if completeBody["status"] != "COMPLETED" {
		t.Fatalf("expected COMPLETED, got %v", completeBody["status"])
	}
	if completeBody["event_state"] != "CLOSED" {
		t.Fatalf("expected CLOSED event_state, got %v", completeBody["event_state"])
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	var status string
	var endTime *time.Time
	var valueRaw []byte
	if err := testPool.QueryRow(
		ctx,
		`SELECT status, "endTime", "valueJson" FROM "Event" WHERE id = $1`,
		eventID,
	).Scan(&status, &endTime, &valueRaw); err != nil {
		t.Fatalf("query completed event: %v", err)
	}
	if status != "CLOSED" {
		t.Fatalf("expected CLOSED, got %q", status)
	}
	if endTime == nil {
		t.Fatalf("expected endTime after completion")
	}

	value := map[string]any{}
	if err := json.Unmarshal(valueRaw, &value); err != nil {
		t.Fatalf("unmarshal value json: %v", err)
	}
	if got, ok := value["ml"].(float64); !ok || int(got) != 130 {
		t.Fatalf("expected ml=130 in valueJson, got %v", value["ml"])
	}
	if value["memo"] != "start note" {
		t.Fatalf("expected original memo to remain, got %v", value["memo"])
	}
}

func TestCancelManualEventMarksCanceled(t *testing.T) {
	resetDatabase(t)
	fixture := seedOwnerFixture(t)
	start := time.Now().UTC().Add(-5 * time.Minute).Truncate(time.Second)

	startRec := performRequest(
		t,
		newTestRouter(t),
		http.MethodPost,
		"/api/v1/events/start",
		signToken(t, fixture.UserID, nil),
		map[string]any{
			"baby_id":    fixture.BabyID,
			"type":       "SLEEP",
			"start_time": start.Format(time.RFC3339),
		},
		nil,
	)
	if startRec.Code != http.StatusOK {
		t.Fatalf("start request failed: %d body=%s", startRec.Code, startRec.Body.String())
	}
	startBody := decodeJSONMap(t, startRec)
	eventID, _ := startBody["event_id"].(string)
	if eventID == "" {
		t.Fatalf("missing event_id")
	}

	cancelRec := performRequest(
		t,
		newTestRouter(t),
		http.MethodPatch,
		"/api/v1/events/"+eventID+"/cancel",
		signToken(t, fixture.UserID, nil),
		map[string]any{"reason": "entered by mistake"},
		nil,
	)
	if cancelRec.Code != http.StatusOK {
		t.Fatalf("cancel request failed: %d body=%s", cancelRec.Code, cancelRec.Body.String())
	}
	cancelBody := decodeJSONMap(t, cancelRec)
	if cancelBody["status"] != "CANCELED" {
		t.Fatalf("expected CANCELED response, got %v", cancelBody["status"])
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	var status string
	if err := testPool.QueryRow(
		ctx,
		`SELECT status FROM "Event" WHERE id = $1`,
		eventID,
	).Scan(&status); err != nil {
		t.Fatalf("query canceled event: %v", err)
	}
	if status != "CANCELED" {
		t.Fatalf("expected CANCELED status, got %q", status)
	}
}

func TestListOpenEventsReturnsOpenItemsOnly(t *testing.T) {
	resetDatabase(t)
	fixture := seedOwnerFixture(t)
	start := time.Now().UTC().Add(-30 * time.Minute).Truncate(time.Second)

	firstStart := performRequest(
		t,
		newTestRouter(t),
		http.MethodPost,
		"/api/v1/events/start",
		signToken(t, fixture.UserID, nil),
		map[string]any{
			"baby_id":    fixture.BabyID,
			"type":       "FORMULA",
			"start_time": start.Format(time.RFC3339),
		},
		nil,
	)
	if firstStart.Code != http.StatusOK {
		t.Fatalf("first start failed: %d body=%s", firstStart.Code, firstStart.Body.String())
	}
	secondStart := performRequest(
		t,
		newTestRouter(t),
		http.MethodPost,
		"/api/v1/events/start",
		signToken(t, fixture.UserID, nil),
		map[string]any{
			"baby_id":    fixture.BabyID,
			"type":       "SLEEP",
			"start_time": start.Add(5 * time.Minute).Format(time.RFC3339),
		},
		nil,
	)
	if secondStart.Code != http.StatusOK {
		t.Fatalf("second start failed: %d body=%s", secondStart.Code, secondStart.Body.String())
	}

	seedEvent(
		t,
		"",
		fixture.BabyID,
		"PEE",
		start.Add(10*time.Minute),
		nil,
		map[string]any{"count": 1},
		fixture.UserID,
	)

	listRec := performRequest(
		t,
		newTestRouter(t),
		http.MethodGet,
		"/api/v1/events/open?baby_id="+fixture.BabyID,
		signToken(t, fixture.UserID, nil),
		nil,
		nil,
	)
	if listRec.Code != http.StatusOK {
		t.Fatalf("list open failed: %d body=%s", listRec.Code, listRec.Body.String())
	}
	body := decodeJSONMap(t, listRec)
	if count, ok := body["open_count"].(float64); !ok || int(count) != 2 {
		t.Fatalf("expected open_count=2, got %v", body["open_count"])
	}
	items, ok := body["open_events"].([]any)
	if !ok {
		t.Fatalf("expected open_events list, got %T", body["open_events"])
	}
	if len(items) != 2 {
		t.Fatalf("expected two open items, got %d", len(items))
	}
}

func TestStartManualEventSupportsExpandedStartableTypes(t *testing.T) {
	testCases := []struct {
		name     string
		typeName string
		value    map[string]any
		metadata map[string]any
	}{
		{name: "breastfeed", typeName: "BREASTFEED", value: map[string]any{"memo": "start"}},
		{name: "pee", typeName: "PEE", value: map[string]any{"count": 1}},
		{name: "poo", typeName: "POO", value: map[string]any{"count": 1}},
		{name: "medication", typeName: "MEDICATION", value: map[string]any{"name": "vitamin-d"}},
		{
			name:     "weaning memo",
			typeName: "MEMO",
			value: map[string]any{
				"memo":     "banana puree",
				"category": "WEANING",
			},
			metadata: map[string]any{
				"entry_kind": "WEANING",
			},
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			resetDatabase(t)
			fixture := seedOwnerFixture(t)
			start := time.Now().UTC().Add(-8 * time.Minute).Truncate(time.Second)

			payload := map[string]any{
				"baby_id":    fixture.BabyID,
				"type":       tc.typeName,
				"start_time": start.Format(time.RFC3339),
				"value":      tc.value,
			}
			if tc.metadata != nil {
				payload["metadata"] = tc.metadata
			}

			rec := performRequest(
				t,
				newTestRouter(t),
				http.MethodPost,
				"/api/v1/events/start",
				signToken(t, fixture.UserID, nil),
				payload,
				nil,
			)
			if rec.Code != http.StatusOK {
				t.Fatalf("expected 200, got %d body=%s", rec.Code, rec.Body.String())
			}
			body := decodeJSONMap(t, rec)
			if body["status"] != "STARTED" {
				t.Fatalf("expected STARTED, got %v", body["status"])
			}
		})
	}
}
