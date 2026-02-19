package server

import (
	"encoding/json"
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

func TestParseTZOffset(t *testing.T) {
	loc, normalized, err := parseTZOffset("+09:30")
	if err != nil {
		t.Fatalf("expected parseTZOffset to succeed: %v", err)
	}
	if normalized != "+09:30" {
		t.Fatalf("unexpected normalized offset: %q", normalized)
	}
	_, seconds := time.Now().In(loc).Zone()
	if seconds != 9*3600+30*60 {
		t.Fatalf("unexpected offset seconds: %d", seconds)
	}

	utcLoc, utcNormalized, err := parseTZOffset("")
	if err != nil {
		t.Fatalf("expected empty tz_offset to fallback to UTC: %v", err)
	}
	if utcNormalized != "+00:00" {
		t.Fatalf("unexpected UTC normalized offset: %q", utcNormalized)
	}
	if utcLoc != time.UTC {
		t.Fatalf("expected UTC location for empty offset")
	}

	if _, _, err := parseTZOffset("0900"); err == nil {
		t.Fatalf("expected invalid offset to fail")
	}
	if _, _, err := parseTZOffset("+14:30"); err == nil {
		t.Fatalf("expected out-of-range offset to fail")
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
