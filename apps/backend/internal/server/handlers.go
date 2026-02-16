package server

import (
	"encoding/json"
	"strconv"
	"strings"
	"time"
)

type parentOnboardingRequest struct {
	Provider         string   `json:"provider"`
	BabyName         string   `json:"baby_name"`
	BabyBirthDate    string   `json:"baby_birth_date"`
	RequiredConsents []string `json:"required_consents"`
}

type voiceUploadRequest struct {
	BabyID         string `json:"baby_id"`
	TranscriptHint string `json:"transcript_hint"`
}

type eventItem struct {
	Type       string             `json:"type"`
	StartTime  time.Time          `json:"start_time"`
	EndTime    *time.Time         `json:"end_time,omitempty"`
	Value      map[string]any     `json:"value"`
	Metadata   map[string]any     `json:"metadata,omitempty"`
	Confidence map[string]float64 `json:"confidence,omitempty"`
}

type voiceParseResponse struct {
	ClipID       string      `json:"clip_id"`
	Transcript   string      `json:"transcript"`
	ParsedEvents []eventItem `json:"parsed_events"`
	Status       string      `json:"status"`
}

type confirmEventsRequest struct {
	ClipID string      `json:"clip_id"`
	Events []eventItem `json:"events"`
}

type aiQueryRequest struct {
	BabyID          string `json:"baby_id"`
	Question        string `json:"question"`
	Tone            string `json:"tone"`
	UsePersonalData bool   `json:"use_personal_data"`
}

type photoUploadCompleteRequest struct {
	AlbumID      string `json:"album_id"`
	ObjectKey    string `json:"object_key"`
	Downloadable bool   `json:"downloadable"`
}

type checkoutRequest struct {
	HouseholdID string `json:"household_id"`
	Plan        string `json:"plan"`
}

type siriIntentRequest struct {
	BabyID string `json:"baby_id"`
	Tone   string `json:"tone"`
}

type bixbyQueryRequest struct {
	CapsuleAction string `json:"capsule_action"`
	BabyID        string `json:"baby_id"`
	Tone          string `json:"tone"`
}

type weeklyMetrics struct {
	FeedingML    float64
	SleepMinutes int
}

var validEventTypes = map[string]struct{}{
	"FORMULA":    {},
	"BREASTFEED": {},
	"SLEEP":      {},
	"PEE":        {},
	"POO":        {},
	"GROWTH":     {},
	"MEMO":       {},
	"SYMPTOM":    {},
	"MEDICATION": {},
}

func normalizeEventType(input string) (string, bool) {
	eventType := strings.ToUpper(strings.TrimSpace(input))
	if eventType == "" {
		return "", false
	}
	_, ok := validEventTypes[eventType]
	return eventType, ok
}

func mustMarshalJSON(input any) string {
	encoded, err := json.Marshal(input)
	if err != nil {
		return "{}"
	}
	return string(encoded)
}

func splitNonEmptyLines(text string) []string {
	parts := strings.Split(text, "\n")
	result := make([]string, 0, len(parts))
	for _, item := range parts {
		trimmed := strings.TrimSpace(item)
		if trimmed != "" {
			result = append(result, trimmed)
		}
	}
	return result
}

func trendString(current, previous float64) string {
	if previous <= 0 {
		return "new"
	}
	change := ((current - previous) / previous) * 100
	sign := ""
	if change >= 0 {
		sign = "+"
	}
	return sign + strconv.Itoa(int(change+0.5)) + "%"
}

func toString(value any) string {
	switch v := value.(type) {
	case string:
		return v
	case float64:
		return strconv.FormatFloat(v, 'f', -1, 64)
	case int:
		return strconv.Itoa(v)
	default:
		return ""
	}
}

func normalizeTone(input string) string {
	tone := strings.ToLower(strings.TrimSpace(input))
	switch tone {
	case "friendly", "neutral", "formal", "brief", "coach":
		return tone
	default:
		return "neutral"
	}
}
