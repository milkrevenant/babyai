package server

import (
	"encoding/json"
	"strings"
	"testing"
	"time"
)

func TestClaimHasAudience(t *testing.T) {
	if !claimHasAudience("expected", "expected") {
		t.Fatalf("expected string audience to match")
	}
	if claimHasAudience("other", "expected") {
		t.Fatalf("expected mismatched string audience to fail")
	}
	if !claimHasAudience([]any{"x", "expected", "y"}, "expected") {
		t.Fatalf("expected []any audience to match")
	}
	if !claimHasAudience([]string{"x", "expected", "y"}, "expected") {
		t.Fatalf("expected []string audience to match")
	}
	if claimHasAudience(nil, "expected") {
		t.Fatalf("expected nil audience to fail")
	}
}

func TestNormalizeEventType(t *testing.T) {
	normalized, ok := normalizeEventType("  poo  ")
	if !ok {
		t.Fatalf("expected POO to be valid")
	}
	if normalized != "POO" {
		t.Fatalf("expected normalized type POO, got %q", normalized)
	}

	if _, ok := normalizeEventType("not-real"); ok {
		t.Fatalf("expected invalid event type to fail")
	}
}

func TestParseDate(t *testing.T) {
	got, err := parseDate("2026-02-15")
	if err != nil {
		t.Fatalf("expected parseDate to succeed: %v", err)
	}
	if got.Format("2006-01-02T15:04:05Z07:00") != "2026-02-15T00:00:00Z" {
		t.Fatalf("unexpected parsed date: %s", got.Format(time.RFC3339))
	}

	if _, err := parseDate("02/15/2026"); err == nil {
		t.Fatalf("expected invalid date to fail")
	}
}

func TestStartOfUTCDay(t *testing.T) {
	local := time.Date(2026, 2, 15, 23, 45, 0, 0, time.FixedZone("KST", 9*60*60))
	start := startOfUTCDay(local)
	if start.Location() != time.UTC {
		t.Fatalf("expected UTC location, got %s", start.Location())
	}
	if start.Hour() != 0 || start.Minute() != 0 || start.Second() != 0 {
		t.Fatalf("expected midnight UTC, got %s", start.Format(time.RFC3339))
	}
}

func TestExtractNumberFromMap(t *testing.T) {
	value := extractNumberFromMap(
		map[string]any{
			"str": "42.5",
			"num": json.Number("12.3"),
		},
		"missing",
		"num",
		"str",
	)
	if value != 12.3 {
		t.Fatalf("expected json.Number to parse first, got %v", value)
	}

	value = extractNumberFromMap(map[string]any{"amount": "17.25"}, "amount")
	if value != 17.25 {
		t.Fatalf("expected string number parse, got %v", value)
	}

	value = extractNumberFromMap(nil, "any")
	if value != 0 {
		t.Fatalf("expected nil map to yield 0, got %v", value)
	}
}

func TestCalculateNextFeedingETA(t *testing.T) {
	now := time.Date(2026, 2, 15, 11, 0, 0, 0, time.UTC)
	feedings := []time.Time{
		time.Date(2026, 2, 15, 8, 0, 0, 0, time.UTC),
		time.Date(2026, 2, 15, 10, 0, 0, 0, time.UTC),
	}

	result := calculateNextFeedingETA(feedings, now)
	if result.Unstable {
		t.Fatalf("expected stable ETA result")
	}
	if result.ETAMinutes == nil || result.AverageIntervalMinutes == nil {
		t.Fatalf("expected ETA and average to be present")
	}
	if *result.AverageIntervalMinutes != 120 {
		t.Fatalf("expected average interval 120, got %d", *result.AverageIntervalMinutes)
	}
	if *result.ETAMinutes != 60 {
		t.Fatalf("expected eta 60, got %d", *result.ETAMinutes)
	}

	lateNow := time.Date(2026, 2, 15, 14, 0, 0, 0, time.UTC)
	lateResult := calculateNextFeedingETA(feedings, lateNow)
	if lateResult.ETAMinutes == nil || *lateResult.ETAMinutes != 120 {
		t.Fatalf("expected ETA 120 for next cycle projection, got %+v", lateResult.ETAMinutes)
	}

	withFuture := append([]time.Time{}, feedings...)
	withFuture = append(withFuture, time.Date(2026, 2, 15, 16, 0, 0, 0, time.UTC))
	futureIgnored := calculateNextFeedingETA(withFuture, now)
	if futureIgnored.ETAMinutes == nil || *futureIgnored.ETAMinutes != 60 {
		t.Fatalf("expected future feeding to be ignored, got %+v", futureIgnored.ETAMinutes)
	}

	unstable := calculateNextFeedingETA([]time.Time{feedings[0]}, now)
	if !unstable.Unstable {
		t.Fatalf("expected unstable result when fewer than 2 feedings")
	}
	if unstable.ETAMinutes != nil || unstable.AverageIntervalMinutes != nil {
		t.Fatalf("expected nil metrics for unstable result")
	}
}

func TestNormalizeTone(t *testing.T) {
	if got := normalizeTone("  FRIENDLY "); got != "friendly" {
		t.Fatalf("expected friendly, got %q", got)
	}
	if got := normalizeTone("unsupported"); got != "neutral" {
		t.Fatalf("expected neutral fallback, got %q", got)
	}
}

func TestTrendString(t *testing.T) {
	if got := trendString(10, 0); got != "new" {
		t.Fatalf("expected new for zero previous, got %q", got)
	}
	if got := trendString(120, 100); got != "+20%" {
		t.Fatalf("expected +20%%, got %q", got)
	}
	if got := trendString(50, 100); got != "-49%" {
		t.Fatalf("expected -49%% based on current rounding behavior, got %q", got)
	}
}

func TestAgeMonthsFromBirthDate(t *testing.T) {
	birth := time.Date(2024, 1, 15, 10, 30, 0, 0, time.FixedZone("KST", 9*60*60))

	if got := ageMonthsFromBirthDate(birth, time.Date(2024, 2, 14, 23, 0, 0, 0, time.UTC)); got != 0 {
		t.Fatalf("expected 0 months before month boundary, got %d", got)
	}
	if got := ageMonthsFromBirthDate(birth, time.Date(2024, 2, 15, 0, 0, 0, 0, time.UTC)); got != 1 {
		t.Fatalf("expected 1 month on month boundary, got %d", got)
	}
	if got := ageMonthsFromBirthDate(birth, time.Date(2024, 3, 20, 0, 0, 0, 0, time.UTC)); got != 2 {
		t.Fatalf("expected 2 months, got %d", got)
	}
	if got := ageMonthsFromBirthDate(birth, time.Date(2023, 12, 31, 0, 0, 0, 0, time.UTC)); got != 0 {
		t.Fatalf("expected 0 months for pre-birth date, got %d", got)
	}
	if got := ageMonthsFromBirthDate(time.Time{}, time.Now().UTC()); got != 0 {
		t.Fatalf("expected 0 months for zero birth date, got %d", got)
	}
}

func TestChatModelForIntent(t *testing.T) {
	if got := chatModelForIntent(aiIntentSmalltalk); got != chatDailyModel {
		t.Fatalf("expected smalltalk to use %q, got %q", chatDailyModel, got)
	}
	if got := chatModelForIntent(aiIntentDataQuery); got != chatCoreModel {
		t.Fatalf("expected data_query to use %q, got %q", chatCoreModel, got)
	}
	if got := chatModelForIntent(aiIntentMedicalRelated); got != chatCoreModel {
		t.Fatalf("expected medical_related to use %q, got %q", chatCoreModel, got)
	}
}

func TestResolveRequestedChatScope(t *testing.T) {
	now := time.Date(2026, 2, 20, 9, 0, 0, 0, time.UTC)
	scope := resolveRequestedChatScope("weekly", "2026-02-11", "+00:00", now)
	if scope.Mode != "week" {
		t.Fatalf("expected week mode, got %q", scope.Mode)
	}
	if scope.AnchorDate == nil {
		t.Fatalf("expected anchor date")
	}
	if scope.AnchorDate.UTC().Format("2006-01-02") != "2026-02-11" {
		t.Fatalf("unexpected anchor date: %s", scope.AnchorDate.UTC().Format("2006-01-02"))
	}

	defaulted := resolveRequestedChatScope("month", "", "+00:00", now)
	if defaulted.Mode != "month" {
		t.Fatalf("expected month mode, got %q", defaulted.Mode)
	}
	if defaulted.AnchorDate == nil {
		t.Fatalf("expected default anchor date")
	}
	if defaulted.AnchorDate.UTC().Format("2006-01-02") != "2026-02-20" {
		t.Fatalf("expected fallback anchor date to be today, got %s", defaulted.AnchorDate.UTC().Format("2006-01-02"))
	}
}

func TestResolveChatContextSelectionWithRequestedScope(t *testing.T) {
	now := time.Date(2026, 2, 20, 9, 0, 0, 0, time.UTC)
	dayAnchor := time.Date(2026, 2, 19, 0, 0, 0, 0, time.UTC)
	daySelection := resolveChatContextSelection(
		"ignored question",
		aiIntentDataQuery,
		now,
		chatScopeOverride{
			Mode:       "day",
			AnchorDate: &dayAnchor,
		},
	)
	if daySelection.Mode != chatContextModeRequestedDateRaw {
		t.Fatalf("expected requested_date_raw for near-day anchor, got %q", daySelection.Mode)
	}
	if daySelection.RequestedDate == nil {
		t.Fatalf("expected requested date for day mode")
	}
	if got := daySelection.RequestedDate.UTC().Format("2006-01-02"); got != "2026-02-19" {
		t.Fatalf("unexpected requested day: %s", got)
	}

	monthAnchor := time.Date(2026, 2, 5, 0, 0, 0, 0, time.UTC)
	monthSelection := resolveChatContextSelection(
		"ignored question",
		aiIntentMedicalRelated,
		now,
		chatScopeOverride{
			Mode:       "month",
			AnchorDate: &monthAnchor,
		},
	)
	if monthSelection.Mode != chatContextModeMonthlyMedicalSummary {
		t.Fatalf("expected monthly medical summary mode, got %q", monthSelection.Mode)
	}
	if monthSelection.MonthStart.UTC().Format("2006-01-02") != "2026-02-01" {
		t.Fatalf("expected month start 2026-02-01, got %s", monthSelection.MonthStart.UTC().Format("2006-01-02"))
	}

	weekAnchor := time.Date(2026, 2, 20, 0, 0, 0, 0, time.UTC)
	weekSelection := resolveChatContextSelection(
		"ignored question",
		aiIntentCareRoutine,
		now,
		chatScopeOverride{
			Mode:       "week",
			AnchorDate: &weekAnchor,
		},
	)
	if weekSelection.Mode != chatContextModeWeeklySummary {
		t.Fatalf("expected weekly summary mode, got %q", weekSelection.Mode)
	}
	if weekSelection.WeekAnchor.UTC().Weekday() != time.Monday {
		t.Fatalf("expected week anchor monday, got %s", weekSelection.WeekAnchor.UTC().Weekday())
	}
}

func TestEnforceAnswerEvidenceGuideFallback(t *testing.T) {
	raw := strings.Join([]string{
		"오늘 하루만 덜 먹은 건 크게 걱정하지 않아도 됩니다.",
		"최근 3일 기록에서 분유량이 평소보다 20ml 정도 낮았습니다.",
		"오늘 밤까지 수유량과 기분 변화를 관찰해보세요.",
	}, "\n")

	got := enforceAnswerEvidenceGuide(raw)
	if !strings.Contains(got, "## 답변\n") {
		t.Fatalf("expected answer section, got: %s", got)
	}
	if !strings.Contains(got, "\n## 근거\n") {
		t.Fatalf("expected evidence section, got: %s", got)
	}
	if !strings.Contains(got, "\n## 가이드\n") {
		t.Fatalf("expected guide section, got: %s", got)
	}
}

func TestEnforceAnswerEvidenceGuideStructuredInput(t *testing.T) {
	raw := strings.Join([]string{
		"답변",
		"지금은 응급 상황으로 보이지 않습니다.",
		"",
		"근거",
		"최근 체온 기록은 37.6도 이하였습니다.",
		"",
		"가이드",
		"수분 섭취를 늘리고 체온을 4시간 간격으로 확인하세요.",
	}, "\n")

	got := enforceAnswerEvidenceGuide(raw)
	if !strings.Contains(got, "지금은 응급 상황으로 보이지 않습니다.") {
		t.Fatalf("expected answer content to remain, got: %s", got)
	}
	if !strings.Contains(got, "최근 체온 기록은 37.6도 이하였습니다.") {
		t.Fatalf("expected evidence content to remain, got: %s", got)
	}
	if !strings.Contains(got, "수분 섭취를 늘리고 체온을 4시간 간격으로 확인하세요.") {
		t.Fatalf("expected guide content to remain, got: %s", got)
	}
}

func TestEnforceAnswerEvidenceGuideInlineHeadingsAndTilde(t *testing.T) {
	raw := strings.Join([]string{
		"## 답변: 오늘은 크게 걱정하지 않아도 됩니다.",
		"## 근거: 최근 기록에서 수유 간격이 3~4시간으로 유지되었습니다.",
		"## 가이드: 다음 수유는 2~3시간 간격으로 관찰하세요.",
	}, "\n")

	got := enforceAnswerEvidenceGuide(raw)
	if strings.Count(got, "## 답변") != 1 {
		t.Fatalf("expected single answer heading, got: %s", got)
	}
	if strings.Count(got, "## 근거") != 1 {
		t.Fatalf("expected single evidence heading, got: %s", got)
	}
	if strings.Count(got, "## 가이드") != 1 {
		t.Fatalf("expected single guide heading, got: %s", got)
	}
	if strings.Contains(got, "~") {
		t.Fatalf("expected no tilde in markdown output, got: %s", got)
	}
}

func TestBuildOnboardingDummySeedEvents(t *testing.T) {
	now := time.Date(2026, 2, 19, 18, 0, 0, 0, time.UTC)
	events := buildOnboardingDummySeedEvents(now)
	if len(events) < 10 {
		t.Fatalf("expected enough seeded events, got %d", len(events))
	}

	hasFormula := false
	hasSleep := false
	has150mlFormula := false

	for _, item := range events {
		if item.Type == "" {
			t.Fatalf("event type must not be empty")
		}
		if item.StartTime.After(now) {
			t.Fatalf("seed event start must be <= now, got %s", item.StartTime.Format(time.RFC3339))
		}
		if item.EndTime != nil && !item.EndTime.After(item.StartTime) {
			t.Fatalf("seed event end must be after start type=%s", item.Type)
		}

		switch item.Type {
		case "FORMULA":
			hasFormula = true
			if int(extractNumberFromMap(item.Value, "ml")+0.5) == 150 {
				has150mlFormula = true
			}
		case "SLEEP":
			hasSleep = true
		}
	}

	if !hasFormula || !hasSleep || !has150mlFormula {
		t.Fatalf(
			"expected representative image seed data formula=%v sleep=%v has150mlFormula=%v",
			hasFormula,
			hasSleep,
			has150mlFormula,
		)
	}
}
