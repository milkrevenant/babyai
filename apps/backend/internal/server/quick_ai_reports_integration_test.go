package server

import (
	"context"
	"net/http"
	"strings"
	"testing"
	"time"
)

func TestQuickLastPooTimeReturnsNoDataMessageWhenNoEvents(t *testing.T) {
	resetDatabase(t)
	fixture := seedOwnerFixture(t)

	rec := performRequest(
		t,
		newTestRouter(t),
		http.MethodGet,
		"/api/v1/quick/last-poo-time?baby_id="+fixture.BabyID,
		signToken(t, fixture.UserID, nil),
		nil,
		nil,
	)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d body=%s", rec.Code, rec.Body.String())
	}

	body := decodeJSONMap(t, rec)
	if body["last_poo_time"] != nil {
		t.Fatalf("expected last_poo_time=nil, got %v", body["last_poo_time"])
	}
	if body["reference_text"] != "No confirmed poo events are stored yet." {
		t.Fatalf("unexpected reference_text: %v", body["reference_text"])
	}
}

func TestQuickLastPooTimeReturnsLatestEvent(t *testing.T) {
	resetDatabase(t)
	fixture := seedOwnerFixture(t)
	start := time.Now().UTC().Add(-33 * time.Minute).Truncate(time.Second)
	seedEvent(t, "", fixture.BabyID, "POO", start, nil, map[string]any{"count": 1}, fixture.UserID)

	rec := performRequest(
		t,
		newTestRouter(t),
		http.MethodGet,
		"/api/v1/quick/last-poo-time?baby_id="+fixture.BabyID+"&tone=brief",
		signToken(t, fixture.UserID, nil),
		nil,
		nil,
	)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d body=%s", rec.Code, rec.Body.String())
	}
	body := decodeJSONMap(t, rec)
	if body["reference_text"] != "Based on confirmed event logs for this baby." {
		t.Fatalf("unexpected reference_text: %v", body["reference_text"])
	}
	lastTime, ok := body["last_poo_time"].(string)
	if !ok || strings.TrimSpace(lastTime) == "" {
		t.Fatalf("expected non-empty last_poo_time string, got %v", body["last_poo_time"])
	}
}

func TestQuickNextFeedingETAWithInsufficientDataIsUnstable(t *testing.T) {
	resetDatabase(t)
	fixture := seedOwnerFixture(t)

	rec := performRequest(
		t,
		newTestRouter(t),
		http.MethodGet,
		"/api/v1/quick/next-feeding-eta?baby_id="+fixture.BabyID,
		signToken(t, fixture.UserID, nil),
		nil,
		nil,
	)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d body=%s", rec.Code, rec.Body.String())
	}
	body := decodeJSONMap(t, rec)
	if unstable, ok := body["unstable"].(bool); !ok || !unstable {
		t.Fatalf("expected unstable=true, got %v", body["unstable"])
	}
	if body["eta_minutes"] != nil {
		t.Fatalf("expected eta_minutes=nil, got %v", body["eta_minutes"])
	}
}

func TestQuickNextFeedingETAReturnsEstimateFromRecentFeedings(t *testing.T) {
	resetDatabase(t)
	fixture := seedOwnerFixture(t)
	now := time.Now().UTC()
	seedEvent(t, "", fixture.BabyID, "FORMULA", now.Add(-4*time.Hour), nil, map[string]any{"ml": 120}, fixture.UserID)
	seedEvent(t, "", fixture.BabyID, "BREASTFEED", now.Add(-2*time.Hour), nil, map[string]any{}, fixture.UserID)

	rec := performRequest(
		t,
		newTestRouter(t),
		http.MethodGet,
		"/api/v1/quick/next-feeding-eta?baby_id="+fixture.BabyID+"&tone=formal",
		signToken(t, fixture.UserID, nil),
		nil,
		nil,
	)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d body=%s", rec.Code, rec.Body.String())
	}
	body := decodeJSONMap(t, rec)
	if unstable, ok := body["unstable"].(bool); !ok || unstable {
		t.Fatalf("expected unstable=false, got %v", body["unstable"])
	}
	if _, ok := body["eta_minutes"].(float64); !ok {
		t.Fatalf("expected eta_minutes numeric, got %T", body["eta_minutes"])
	}
	if body["reference_text"] != "Computed from 2 recent feeding events." {
		t.Fatalf("unexpected reference_text: %v", body["reference_text"])
	}
}

func TestQuickTodaySummaryBuildsExpectedLines(t *testing.T) {
	resetDatabase(t)
	fixture := seedOwnerFixture(t)
	start := startOfUTCDay(time.Now().UTC()).Add(2 * time.Hour)
	sleepEnd := start.Add(90 * time.Minute)

	seedEvent(t, "", fixture.BabyID, "FORMULA", start, nil, map[string]any{"ml": 150}, fixture.UserID)
	seedEvent(t, "", fixture.BabyID, "SLEEP", start.Add(15*time.Minute), &sleepEnd, map[string]any{}, fixture.UserID)
	seedEvent(t, "", fixture.BabyID, "PEE", start.Add(30*time.Minute), nil, map[string]any{}, fixture.UserID)
	seedEvent(t, "", fixture.BabyID, "POO", start.Add(45*time.Minute), nil, map[string]any{}, fixture.UserID)

	rec := performRequest(
		t,
		newTestRouter(t),
		http.MethodGet,
		"/api/v1/quick/today-summary?baby_id="+fixture.BabyID,
		signToken(t, fixture.UserID, nil),
		nil,
		nil,
	)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d body=%s", rec.Code, rec.Body.String())
	}
	body := decodeJSONMap(t, rec)
	lines := decodeStringList(t, body["summary_lines"])
	if !containsString(lines, "Feedings: 1") {
		t.Fatalf("expected feedings summary line, got %v", lines)
	}
	if !containsString(lines, "Formula total: 150 ml") {
		t.Fatalf("expected formula summary line, got %v", lines)
	}
	if !containsString(lines, "Diaper events: pee 1, poo 1") {
		t.Fatalf("expected diaper summary line, got %v", lines)
	}
}

func TestAIQueryReturnsRecordBasedPooAnswer(t *testing.T) {
	resetDatabase(t)
	fixture := seedOwnerFixture(t)
	latest := time.Now().UTC().Add(-1 * time.Hour).Truncate(time.Second)
	seedEvent(t, "", fixture.BabyID, "POO", latest, nil, map[string]any{"count": 1}, fixture.UserID)

	rec := performRequest(
		t,
		newTestRouter(t),
		http.MethodPost,
		"/api/v1/ai/query",
		signToken(t, fixture.UserID, nil),
		map[string]any{
			"baby_id":           fixture.BabyID,
			"question":          "When was the last poo?",
			"tone":              "neutral",
			"use_personal_data": true,
		},
		nil,
	)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d body=%s", rec.Code, rec.Body.String())
	}
	body := decodeJSONMap(t, rec)
	answer, _ := body["answer"].(string)
	if !strings.Contains(answer, "Latest poo event is at") {
		t.Fatalf("unexpected answer: %q", answer)
	}
}

func TestAIQueryReturnsGenericAnswerWhenPersonalDataDisabled(t *testing.T) {
	resetDatabase(t)
	fixture := seedOwnerFixture(t)

	rec := performRequest(
		t,
		newTestRouter(t),
		http.MethodPost,
		"/api/v1/ai/query",
		signToken(t, fixture.UserID, nil),
		map[string]any{
			"baby_id":           fixture.BabyID,
			"question":          "What can you do?",
			"use_personal_data": false,
		},
		nil,
	)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d body=%s", rec.Code, rec.Body.String())
	}
	body := decodeJSONMap(t, rec)
	if body["answer"] != "I can answer about feeding ETA, diaper timing, and daily summaries once logs are available." {
		t.Fatalf("unexpected generic answer: %v", body["answer"])
	}
}

func TestDailyReportRejectsInvalidDate(t *testing.T) {
	resetDatabase(t)
	fixture := seedOwnerFixture(t)

	rec := performRequest(
		t,
		newTestRouter(t),
		http.MethodGet,
		"/api/v1/reports/daily?baby_id="+fixture.BabyID+"&date=2026/02/15",
		signToken(t, fixture.UserID, nil),
		nil,
		nil,
	)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d body=%s", rec.Code, rec.Body.String())
	}
	if detail := responseDetail(t, rec); detail != "date must be YYYY-MM-DD" {
		t.Fatalf("unexpected detail: %q", detail)
	}
}

func TestDailyReportReturnsComputedSummaryWhenNoPrecomputedReport(t *testing.T) {
	resetDatabase(t)
	fixture := seedOwnerFixture(t)
	targetDate := startOfUTCDay(time.Now().UTC())
	sleepEnd := targetDate.Add(3 * time.Hour)
	seedEvent(t, "", fixture.BabyID, "FORMULA", targetDate.Add(30*time.Minute), nil, map[string]any{"ml": 90}, fixture.UserID)
	seedEvent(t, "", fixture.BabyID, "SLEEP", targetDate.Add(90*time.Minute), &sleepEnd, map[string]any{}, fixture.UserID)
	seedEvent(t, "", fixture.BabyID, "PEE", targetDate.Add(2*time.Hour), nil, map[string]any{}, fixture.UserID)
	seedEvent(t, "", fixture.BabyID, "POO", targetDate.Add(2*time.Hour+15*time.Minute), nil, map[string]any{}, fixture.UserID)

	rec := performRequest(
		t,
		newTestRouter(t),
		http.MethodGet,
		"/api/v1/reports/daily?baby_id="+fixture.BabyID+"&date="+targetDate.Format("2006-01-02"),
		signToken(t, fixture.UserID, nil),
		nil,
		nil,
	)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d body=%s", rec.Code, rec.Body.String())
	}
	body := decodeJSONMap(t, rec)
	summary := decodeStringList(t, body["summary"])
	if !containsString(summary, "Feeding events: 1") {
		t.Fatalf("expected feeding summary, got %v", summary)
	}
	if !containsString(summary, "Formula total: 90 ml") {
		t.Fatalf("expected formula summary, got %v", summary)
	}
}

func TestWeeklyReportReturnsPrecomputedMetrics(t *testing.T) {
	resetDatabase(t)
	fixture := seedOwnerFixture(t)
	weekStart := time.Date(2026, 2, 9, 0, 0, 0, 0, time.UTC)
	seedReport(
		t,
		"",
		fixture.HouseholdID,
		fixture.BabyID,
		"WEEKLY",
		weekStart,
		weekStart.Add(7*24*time.Hour),
		map[string]any{
			"trend": map[string]any{
				"feeding_total_ml": "+20%",
				"sleep_total_min":  "new",
			},
			"suggestions": []string{"Keep logs consistent", "Review hydration"},
		},
		"weekly summary",
	)

	rec := performRequest(
		t,
		newTestRouter(t),
		http.MethodGet,
		"/api/v1/reports/weekly?baby_id="+fixture.BabyID+"&week_start="+weekStart.Format("2006-01-02"),
		signToken(t, fixture.UserID, nil),
		nil,
		nil,
	)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d body=%s", rec.Code, rec.Body.String())
	}
	body := decodeJSONMap(t, rec)

	trend, ok := body["trend"].(map[string]any)
	if !ok {
		t.Fatalf("expected trend object, got %T", body["trend"])
	}
	if trend["feeding_total_ml"] != "+20%" {
		t.Fatalf("unexpected trend feeding_total_ml: %v", trend["feeding_total_ml"])
	}

	suggestions := decodeStringList(t, body["suggestions"])
	if !containsString(suggestions, "Keep logs consistent") {
		t.Fatalf("unexpected suggestions: %v", suggestions)
	}
}

func TestWeeklyReportRejectsInvalidWeekStart(t *testing.T) {
	resetDatabase(t)
	fixture := seedOwnerFixture(t)

	rec := performRequest(
		t,
		newTestRouter(t),
		http.MethodGet,
		"/api/v1/reports/weekly?baby_id="+fixture.BabyID+"&week_start=bad",
		signToken(t, fixture.UserID, nil),
		nil,
		nil,
	)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d body=%s", rec.Code, rec.Body.String())
	}
	if detail := responseDetail(t, rec); detail != "week_start must be YYYY-MM-DD" {
		t.Fatalf("unexpected detail: %q", detail)
	}
}

func TestWeeklyReportReturnsComputedTrendWhenNoPrecomputedMetrics(t *testing.T) {
	resetDatabase(t)
	fixture := seedOwnerFixture(t)
	weekStart := time.Date(2026, 2, 9, 0, 0, 0, 0, time.UTC)
	previousWeekStart := weekStart.Add(-7 * 24 * time.Hour)

	seedEvent(t, "", fixture.BabyID, "FORMULA", previousWeekStart.Add(24*time.Hour), nil, map[string]any{"ml": 50}, fixture.UserID)
	seedEvent(t, "", fixture.BabyID, "FORMULA", weekStart.Add(24*time.Hour), nil, map[string]any{"ml": 150}, fixture.UserID)

	rec := performRequest(
		t,
		newTestRouter(t),
		http.MethodGet,
		"/api/v1/reports/weekly?baby_id="+fixture.BabyID+"&week_start="+weekStart.Format("2006-01-02"),
		signToken(t, fixture.UserID, nil),
		nil,
		nil,
	)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d body=%s", rec.Code, rec.Body.String())
	}

	body := decodeJSONMap(t, rec)
	trend, ok := body["trend"].(map[string]any)
	if !ok {
		t.Fatalf("expected trend object, got %T", body["trend"])
	}
	if strings.TrimSpace(trend["feeding_total_ml"].(string)) == "" {
		t.Fatalf("expected non-empty computed feeding trend, got %v", trend["feeding_total_ml"])
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	var reportCount int
	if err := testPool.QueryRow(ctx, `SELECT COUNT(*) FROM "Report"`).Scan(&reportCount); err != nil {
		t.Fatalf("query report count: %v", err)
	}
	if reportCount != 0 {
		t.Fatalf("expected no stored report rows for computed fallback test, got %d", reportCount)
	}
}

func containsString(items []string, target string) bool {
	for _, item := range items {
		if item == target {
			return true
		}
	}
	return false
}
