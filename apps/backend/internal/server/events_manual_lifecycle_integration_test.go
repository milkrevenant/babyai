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
	var metadataRaw []byte
	var endTime *time.Time
	if err := testPool.QueryRow(
		ctx,
		`SELECT "metadataJson", "endTime" FROM "Event" WHERE id = $1`,
		eventID,
	).Scan(&metadataRaw, &endTime); err != nil {
		t.Fatalf("query event: %v", err)
	}
	metadata := map[string]any{}
	if err := json.Unmarshal(metadataRaw, &metadata); err != nil {
		t.Fatalf("unmarshal metadata json: %v", err)
	}
	if metadata["event_state"] != "OPEN" {
		t.Fatalf("expected event_state OPEN, got %v", metadata["event_state"])
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

func TestStartManualEventAllowsDifferentTypeOverlap(t *testing.T) {
	resetDatabase(t)
	fixture := seedOwnerFixture(t)
	start := time.Now().UTC().Add(-25 * time.Minute).Truncate(time.Second)

	sleepRec := performRequest(
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
	if sleepRec.Code != http.StatusOK {
		t.Fatalf("sleep start failed: %d body=%s", sleepRec.Code, sleepRec.Body.String())
	}

	formulaRec := performRequest(
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
	if formulaRec.Code != http.StatusOK {
		t.Fatalf("formula start failed: %d body=%s", formulaRec.Code, formulaRec.Body.String())
	}
	body := decodeJSONMap(t, formulaRec)
	if body["status"] != "STARTED" {
		t.Fatalf("expected STARTED, got %v", body["status"])
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
	var endTime *time.Time
	var valueRaw []byte
	var metadataRaw []byte
	if err := testPool.QueryRow(
		ctx,
		`SELECT "endTime", "valueJson", "metadataJson" FROM "Event" WHERE id = $1`,
		eventID,
	).Scan(&endTime, &valueRaw, &metadataRaw); err != nil {
		t.Fatalf("query completed event: %v", err)
	}
	if endTime == nil {
		t.Fatalf("expected endTime after completion")
	}
	metadata := map[string]any{}
	if err := json.Unmarshal(metadataRaw, &metadata); err != nil {
		t.Fatalf("unmarshal metadata json: %v", err)
	}
	if metadata["event_state"] != "CLOSED" {
		t.Fatalf("expected event_state CLOSED, got %v", metadata["event_state"])
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

func TestUpdateManualEventUpdatesClosedEvent(t *testing.T) {
	resetDatabase(t)
	fixture := seedOwnerFixture(t)
	start := time.Now().UTC().Add(-45 * time.Minute).Truncate(time.Second)
	end := start.Add(20 * time.Minute)
	eventID := seedEvent(
		t,
		"",
		fixture.BabyID,
		"FORMULA",
		start,
		&end,
		map[string]any{"ml": 90, "memo": "old memo"},
		fixture.UserID,
	)

	updatedStart := start.Add(3 * time.Minute)
	updatedEnd := end.Add(4 * time.Minute)
	rec := performRequest(
		t,
		newTestRouter(t),
		http.MethodPatch,
		"/api/v1/events/"+eventID,
		signToken(t, fixture.UserID, nil),
		map[string]any{
			"type":       "FORMULA",
			"start_time": updatedStart.Format(time.RFC3339),
			"end_time":   updatedEnd.Format(time.RFC3339),
			"value": map[string]any{
				"ml": 120,
			},
			"metadata": map[string]any{
				"editor": "integration-test",
			},
		},
		nil,
	)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d body=%s", rec.Code, rec.Body.String())
	}
	body := decodeJSONMap(t, rec)
	if body["status"] != "UPDATED" {
		t.Fatalf("expected UPDATED, got %v", body["status"])
	}
	if body["event_state"] != "CLOSED" {
		t.Fatalf("expected CLOSED event_state, got %v", body["event_state"])
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	var dbStart time.Time
	var dbEnd *time.Time
	var valueRaw []byte
	var metadataRaw []byte
	if err := testPool.QueryRow(
		ctx,
		`SELECT "startTime", "endTime", "valueJson", "metadataJson"
		 FROM "Event"
		 WHERE id = $1`,
		eventID,
	).Scan(&dbStart, &dbEnd, &valueRaw, &metadataRaw); err != nil {
		t.Fatalf("query updated event: %v", err)
	}
	if !dbStart.UTC().Equal(updatedStart.UTC()) {
		t.Fatalf("expected updated start %s, got %s", updatedStart.UTC(), dbStart.UTC())
	}
	if dbEnd == nil || !dbEnd.UTC().Equal(updatedEnd.UTC()) {
		t.Fatalf("expected updated end %s, got %v", updatedEnd.UTC(), dbEnd)
	}

	value := map[string]any{}
	if err := json.Unmarshal(valueRaw, &value); err != nil {
		t.Fatalf("unmarshal value json: %v", err)
	}
	if got, ok := value["ml"].(float64); !ok || int(got) != 120 {
		t.Fatalf("expected ml=120 in valueJson, got %v", value["ml"])
	}
	if value["memo"] != "old memo" {
		t.Fatalf("expected existing memo to remain, got %v", value["memo"])
	}

	metadata := map[string]any{}
	if err := json.Unmarshal(metadataRaw, &metadata); err != nil {
		t.Fatalf("unmarshal metadata json: %v", err)
	}
	if metadata["editor"] != "integration-test" {
		t.Fatalf("expected editor metadata, got %v", metadata["editor"])
	}
	if metadata["entry_mode"] != "manual_edit" {
		t.Fatalf("expected entry_mode=manual_edit, got %v", metadata["entry_mode"])
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
	var metadataRaw []byte
	if err := testPool.QueryRow(
		ctx,
		`SELECT "metadataJson" FROM "Event" WHERE id = $1`,
		eventID,
	).Scan(&metadataRaw); err != nil {
		t.Fatalf("query canceled event: %v", err)
	}
	metadata := map[string]any{}
	if err := json.Unmarshal(metadataRaw, &metadata); err != nil {
		t.Fatalf("unmarshal metadata json: %v", err)
	}
	if metadata["event_state"] != "CANCELED" {
		t.Fatalf("expected event_state CANCELED, got %v", metadata["event_state"])
	}
}

func TestCancelManualEventMarksClosedEventCanceled(t *testing.T) {
	resetDatabase(t)
	fixture := seedOwnerFixture(t)
	start := time.Now().UTC().Add(-42 * time.Minute).Truncate(time.Second)
	end := start.Add(22 * time.Minute)

	eventID := seedEvent(
		t,
		"",
		fixture.BabyID,
		"SLEEP",
		start,
		&end,
		map[string]any{"sleep_type": "nap"},
		fixture.UserID,
	)

	cancelRec := performRequest(
		t,
		newTestRouter(t),
		http.MethodPatch,
		"/api/v1/events/"+eventID+"/cancel",
		signToken(t, fixture.UserID, nil),
		map[string]any{"reason": "delete from daily activity"},
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
	var dbEnd *time.Time
	var metadataRaw []byte
	if err := testPool.QueryRow(
		ctx,
		`SELECT "endTime", "metadataJson" FROM "Event" WHERE id = $1`,
		eventID,
	).Scan(&dbEnd, &metadataRaw); err != nil {
		t.Fatalf("query canceled closed event: %v", err)
	}
	if dbEnd == nil || !dbEnd.UTC().Equal(end.UTC()) {
		t.Fatalf("expected endTime to remain %s, got %v", end.UTC(), dbEnd)
	}
	metadata := map[string]any{}
	if err := json.Unmarshal(metadataRaw, &metadata); err != nil {
		t.Fatalf("unmarshal metadata json: %v", err)
	}
	if metadata["event_state"] != "CANCELED" {
		t.Fatalf("expected event_state CANCELED, got %v", metadata["event_state"])
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
