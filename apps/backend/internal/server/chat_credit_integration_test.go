package server

import (
	"context"
	"net/http"
	"strings"
	"testing"
	"time"
)

func TestChatQueryCreatesUsageLogAndChargesWallet(t *testing.T) {
	resetDatabase(t)
	fixture := seedOwnerFixture(t)
	seedSubscription(t, "", fixture.HouseholdID, "AI_ONLY", "ACTIVE")

	sessionID := createSessionForTest(t, fixture.UserID, fixture.BabyID)

	rec := performRequest(
		t,
		newTestRouter(t),
		http.MethodPost,
		"/api/v1/chat/query",
		signToken(t, fixture.UserID, nil),
		map[string]any{
			"session_id":        sessionID,
			"child_id":          fixture.BabyID,
			"query":             "How was sleep today?",
			"tone":              "neutral",
			"use_personal_data": true,
		},
		nil,
	)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d body=%s", rec.Code, rec.Body.String())
	}

	body := decodeJSONMap(t, rec)
	if body["usage"] == nil || body["credit"] == nil || body["model"] == nil {
		t.Fatalf("expected usage/credit/model fields in response, got %v", body)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	var usageLogCount int
	if err := testPool.QueryRow(ctx, `SELECT COUNT(*)::int FROM "AiUsageLog" WHERE "userId" = $1`, fixture.UserID).Scan(&usageLogCount); err != nil {
		t.Fatalf("query usage log count: %v", err)
	}
	if usageLogCount != 1 {
		t.Fatalf("expected 1 usage log row, got %d", usageLogCount)
	}

	var walletBalance int
	if err := testPool.QueryRow(ctx, `SELECT "balanceCredits" FROM "UserCreditWallet" WHERE "userId" = $1`, fixture.UserID).Scan(&walletBalance); err != nil {
		t.Fatalf("query wallet balance: %v", err)
	}
	if walletBalance >= 300 {
		t.Fatalf("expected wallet to be charged from monthly grant, got %d", walletBalance)
	}

	var messageCount int
	if err := testPool.QueryRow(ctx, `SELECT COUNT(*)::int FROM "ChatMessage" WHERE "sessionId" = $1`, sessionID).Scan(&messageCount); err != nil {
		t.Fatalf("query message count: %v", err)
	}
	if messageCount != 2 {
		t.Fatalf("expected 2 chat messages (user+assistant), got %d", messageCount)
	}
}

func TestChatQueryGraceThenPaymentRequired(t *testing.T) {
	resetDatabase(t)
	fixture := seedOwnerFixture(t)
	sessionID := createSessionForTest(t, fixture.UserID, fixture.BabyID)

	for i := 0; i < 3; i++ {
		rec := performRequest(
			t,
			newTestRouter(t),
			http.MethodPost,
			"/api/v1/chat/query",
			signToken(t, fixture.UserID, nil),
			map[string]any{
				"session_id":        sessionID,
				"child_id":          fixture.BabyID,
				"query":             "short question",
				"use_personal_data": true,
			},
			nil,
		)
		if rec.Code != http.StatusOK {
			t.Fatalf("expected grace call %d to succeed, got %d body=%s", i+1, rec.Code, rec.Body.String())
		}
		body := decodeJSONMap(t, rec)
		credit, ok := body["credit"].(map[string]any)
		if !ok {
			t.Fatalf("expected credit object, got %T", body["credit"])
		}
		if credit["billing_mode"] != "grace" {
			t.Fatalf("expected billing_mode=grace, got %v", credit["billing_mode"])
		}
	}

	rec := performRequest(
		t,
		newTestRouter(t),
		http.MethodPost,
		"/api/v1/chat/query",
		signToken(t, fixture.UserID, nil),
		map[string]any{
			"session_id":        sessionID,
			"child_id":          fixture.BabyID,
			"query":             "fourth call",
			"use_personal_data": true,
		},
		nil,
	)
	if rec.Code != http.StatusPaymentRequired {
		t.Fatalf("expected 402 on 4th grace overrun, got %d body=%s", rec.Code, rec.Body.String())
	}
	if detail := responseDetail(t, rec); detail != "Insufficient AI credits" {
		t.Fatalf("unexpected detail: %q", detail)
	}
}

func TestMonthlyCreditGrantIsIdempotent(t *testing.T) {
	resetDatabase(t)
	fixture := seedOwnerFixture(t)
	seedSubscription(t, "", fixture.HouseholdID, "AI_ONLY", "ACTIVE")
	sessionID := createSessionForTest(t, fixture.UserID, fixture.BabyID)

	for i := 0; i < 2; i++ {
		rec := performRequest(
			t,
			newTestRouter(t),
			http.MethodPost,
			"/api/v1/chat/query",
			signToken(t, fixture.UserID, nil),
			map[string]any{
				"session_id":        sessionID,
				"child_id":          fixture.BabyID,
				"query":             "hello",
				"use_personal_data": true,
			},
			nil,
		)
		if rec.Code != http.StatusOK {
			t.Fatalf("expected call %d to succeed, got %d body=%s", i+1, rec.Code, rec.Body.String())
		}
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	var grantCount int
	if err := testPool.QueryRow(
		ctx,
		`SELECT COUNT(*)::int
		 FROM "UserCreditGrantLedger"
		 WHERE "userId" = $1 AND "householdId" = $2 AND "grantType" = 'SUBSCRIPTION_MONTHLY'`,
		fixture.UserID,
		fixture.HouseholdID,
	).Scan(&grantCount); err != nil {
		t.Fatalf("query monthly grant count: %v", err)
	}
	if grantCount != 1 {
		t.Fatalf("expected one monthly grant row, got %d", grantCount)
	}
}

func TestQuickSnapshotDoesNotCreateUsageLogs(t *testing.T) {
	resetDatabase(t)
	fixture := seedOwnerFixture(t)

	rec := performRequest(
		t,
		newTestRouter(t),
		http.MethodGet,
		"/api/v1/quick/landing-snapshot?baby_id="+fixture.BabyID,
		signToken(t, fixture.UserID, nil),
		nil,
		nil,
	)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d body=%s", rec.Code, rec.Body.String())
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	var usageLogCount int
	if err := testPool.QueryRow(ctx, `SELECT COUNT(*)::int FROM "AiUsageLog"`).Scan(&usageLogCount); err != nil {
		t.Fatalf("query usage log count: %v", err)
	}
	if usageLogCount != 0 {
		t.Fatalf("expected quick snapshot to skip AI usage logs, got %d", usageLogCount)
	}
}

func TestChatQueryUsesOnboardingChildWhenChildIDMissing(t *testing.T) {
	resetDatabase(t)
	fixture := seedOwnerFixture(t)

	sessionRec := performRequest(
		t,
		newTestRouter(t),
		http.MethodPost,
		"/api/v1/chat/sessions",
		signToken(t, fixture.UserID, nil),
		map[string]any{},
		nil,
	)
	if sessionRec.Code != http.StatusOK {
		t.Fatalf("create chat session failed: %d body=%s", sessionRec.Code, sessionRec.Body.String())
	}
	sessionBody := decodeJSONMap(t, sessionRec)
	sessionID, _ := sessionBody["session_id"].(string)
	if strings.TrimSpace(sessionID) == "" {
		t.Fatalf("missing session_id in response: %v", sessionBody)
	}
	sessionChildID, _ := sessionBody["child_id"].(string)
	if strings.TrimSpace(sessionChildID) != fixture.BabyID {
		t.Fatalf("expected default child_id=%s from onboarding, got %v", fixture.BabyID, sessionBody["child_id"])
	}

	rec := performRequest(
		t,
		newTestRouter(t),
		http.MethodPost,
		"/api/v1/chat/query",
		signToken(t, fixture.UserID, nil),
		map[string]any{
			"session_id":        sessionID,
			"query":             "how is baby today?",
			"use_personal_data": true,
		},
		nil,
	)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d body=%s", rec.Code, rec.Body.String())
	}
	body := decodeJSONMap(t, rec)
	contextMap, ok := body["context"].(map[string]any)
	if !ok {
		t.Fatalf("expected context map in response, got %T (%v)", body["context"], body["context"])
	}
	contextChildID, _ := contextMap["child_id"].(string)
	if strings.TrimSpace(contextChildID) != fixture.BabyID {
		t.Fatalf("expected context child_id=%s, got %v", fixture.BabyID, contextMap["child_id"])
	}
	birthDate, _ := contextMap["profile_birth_date_utc"].(string)
	if strings.TrimSpace(birthDate) == "" {
		t.Fatalf("expected profile_birth_date_utc in context, got %v", contextMap["profile_birth_date_utc"])
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	var storedChildID string
	if err := testPool.QueryRow(ctx, `SELECT "childId" FROM "ChatSession" WHERE id = $1`, sessionID).Scan(&storedChildID); err != nil {
		t.Fatalf("query chat session childId: %v", err)
	}
	if strings.TrimSpace(storedChildID) != fixture.BabyID {
		t.Fatalf("expected persisted session childId=%s, got %s", fixture.BabyID, storedChildID)
	}
}

func TestChatQueryDayModeUsesAllEventsInRequestedDate(t *testing.T) {
	resetDatabase(t)
	fixture := seedOwnerFixture(t)
	sessionID := createSessionForTest(t, fixture.UserID, fixture.BabyID)

	anchorDate := time.Date(2026, 2, 19, 0, 0, 0, 0, time.UTC)
	overnightEnd := anchorDate.Add(30 * time.Minute)
	overnightSleepID := seedEvent(
		t,
		"",
		fixture.BabyID,
		"SLEEP",
		anchorDate.Add(-30*time.Minute),
		&overnightEnd,
		map[string]any{"duration_min": 60},
		fixture.UserID,
	)
	formulaID := seedEvent(t, "", fixture.BabyID, "FORMULA", anchorDate.Add(1*time.Hour), nil, map[string]any{"ml": 120}, fixture.UserID)
	sleepEnd := anchorDate.Add(5 * time.Hour)
	sleepID := seedEvent(t, "", fixture.BabyID, "SLEEP", anchorDate.Add(3*time.Hour), &sleepEnd, map[string]any{"duration_min": 120}, fixture.UserID)
	pooID := seedEvent(t, "", fixture.BabyID, "POO", anchorDate.Add(7*time.Hour), nil, map[string]any{}, fixture.UserID)

	rec := performRequest(
		t,
		newTestRouter(t),
		http.MethodPost,
		"/api/v1/chat/query",
		signToken(t, fixture.UserID, nil),
		map[string]any{
			"session_id":        sessionID,
			"child_id":          fixture.BabyID,
			"query":             "수유 기록 알려줘",
			"use_personal_data": true,
			"date_mode":         "day",
			"anchor_date":       "2026-02-19",
			"tz_offset":         "+00:00",
		},
		nil,
	)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d body=%s", rec.Code, rec.Body.String())
	}
	body := decodeJSONMap(t, rec)
	contextMap, ok := body["context"].(map[string]any)
	if !ok {
		t.Fatalf("expected context map in response, got %T (%v)", body["context"], body["context"])
	}
	if got := strings.TrimSpace(toString(contextMap["time_range"])); got != chatContextModeRequestedDateRaw {
		t.Fatalf("expected time_range=%s, got %q", chatContextModeRequestedDateRaw, got)
	}
	rawIDs, ok := contextMap["evidence_event_ids"].([]any)
	if !ok {
		t.Fatalf("expected evidence_event_ids array, got %T (%v)", contextMap["evidence_event_ids"], contextMap["evidence_event_ids"])
	}
	if len(rawIDs) != 4 {
		t.Fatalf("expected 4 evidence_event_ids from requested day, got %d (%v)", len(rawIDs), rawIDs)
	}
	found := map[string]bool{}
	for _, item := range rawIDs {
		id := strings.TrimSpace(toString(item))
		if id != "" {
			found[id] = true
		}
	}
	for _, expected := range []string{overnightSleepID, formulaID, sleepID, pooID} {
		if !found[expected] {
			t.Fatalf("expected evidence_event_ids to include %s, got %v", expected, rawIDs)
		}
	}
	if got := int(extractNumber(contextMap["returned_event_count"])); got != 4 {
		t.Fatalf("expected returned_event_count=4, got %v", contextMap["returned_event_count"])
	}
	if truncated, _ := contextMap["truncated"].(bool); truncated {
		t.Fatalf("expected truncated=false for day mode, got true")
	}
}

func createSessionForTest(t *testing.T, userID, babyID string) string {
	t.Helper()
	rec := performRequest(
		t,
		newTestRouter(t),
		http.MethodPost,
		"/api/v1/chat/sessions",
		signToken(t, userID, nil),
		map[string]any{
			"child_id": babyID,
		},
		nil,
	)
	if rec.Code != http.StatusOK {
		t.Fatalf("create chat session failed: %d body=%s", rec.Code, rec.Body.String())
	}
	body := decodeJSONMap(t, rec)
	sessionID, _ := body["session_id"].(string)
	if sessionID == "" {
		t.Fatalf("missing session_id in response: %v", body)
	}
	return sessionID
}
