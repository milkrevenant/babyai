package server

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
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

func (a *App) onboardingParent(c *gin.Context) {
	user, ok := authUserFromContext(c)
	if !ok {
		writeError(c, http.StatusUnauthorized, "Unauthorized")
		return
	}

	var payload parentOnboardingRequest
	if !mustJSON(c, &payload) {
		return
	}
	provider := providerFromClaim(payload.Provider)
	if strings.TrimSpace(payload.BabyName) == "" {
		writeError(c, http.StatusBadRequest, "baby_name is required")
		return
	}
	birthDate, err := parseDate(payload.BabyBirthDate)
	if err != nil {
		writeError(c, http.StatusBadRequest, "baby_birth_date must be YYYY-MM-DD")
		return
	}

	consentMap := map[string]string{
		"terms":           "TERMS",
		"privacy":         "PRIVACY",
		"data_processing": "DATA_PROCESSING",
	}
	consents := make([]string, 0, len(payload.RequiredConsents))
	for _, item := range payload.RequiredConsents {
		enum, ok := consentMap[item]
		if !ok {
			writeError(c, http.StatusBadRequest, "Invalid consent value")
			return
		}
		consents = append(consents, enum)
	}

	tx, err := a.db.Begin(c.Request.Context())
	if err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to start transaction")
		return
	}
	defer tx.Rollback(c.Request.Context())

	if _, err := tx.Exec(
		c.Request.Context(),
		`UPDATE "User" SET provider = $2 WHERE id = $1`,
		user.ID,
		provider,
	); err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to update user")
		return
	}

	householdID := uuid.NewString()
	if _, err := tx.Exec(
		c.Request.Context(),
		`INSERT INTO "Household" (id, "ownerUserId", "createdAt") VALUES ($1, $2, NOW())`,
		householdID,
		user.ID,
	); err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to create household")
		return
	}

	babyID := uuid.NewString()
	if _, err := tx.Exec(
		c.Request.Context(),
		`INSERT INTO "Baby" (id, "householdId", name, "birthDate", "createdAt")
		 VALUES ($1, $2, $3, $4, NOW())`,
		babyID,
		householdID,
		strings.TrimSpace(payload.BabyName),
		birthDate,
	); err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to create baby profile")
		return
	}

	for _, consent := range consents {
		if _, err := tx.Exec(
			c.Request.Context(),
			`INSERT INTO "Consent" (id, "userId", type, granted, "grantedAt")
			 VALUES ($1, $2, $3, TRUE, NOW())`,
			uuid.NewString(),
			user.ID,
			consent,
		); err != nil {
			writeError(c, http.StatusInternalServerError, "Failed to save consent")
			return
		}
	}

	if err := recordAuditLog(
		c.Request.Context(),
		tx,
		householdID,
		user.ID,
		"ONBOARDING_PARENT_COMPLETED",
		"Household",
		&householdID,
		gin.H{"baby_id": babyID, "provider": provider},
	); err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to write audit log")
		return
	}

	if err := tx.Commit(c.Request.Context()); err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to commit transaction")
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"status":               "created",
		"household_id":         householdID,
		"baby_id":              babyID,
		"baby_profile_created": true,
		"provider":             provider,
	})
}

func (a *App) parseVoiceEvent(c *gin.Context) {
	user, ok := authUserFromContext(c)
	if !ok {
		writeError(c, http.StatusUnauthorized, "Unauthorized")
		return
	}

	var payload voiceUploadRequest
	if !mustJSON(c, &payload) {
		return
	}

	baby, statusCode, err := a.getBabyWithAccess(c.Request.Context(), user.ID, payload.BabyID, writeRoles)
	if err != nil {
		writeError(c, statusCode, err.Error())
		return
	}

	now := time.Now().UTC()
	event := eventItem{
		Type:      "POO",
		StartTime: now.Add(-10 * time.Minute),
		Value:     map[string]any{"count": 1},
		Metadata:  map[string]any{"baby_id": baby.ID},
		Confidence: map[string]float64{
			"type":       0.98,
			"start_time": 0.95,
			"count":      0.97,
		},
	}
	transcript := strings.TrimSpace(payload.TranscriptHint)
	if transcript == "" {
		transcript = "Logged one poo event 10 minutes ago."
	}
	clipID := uuid.NewString()
	audioURL := "uploads/voice/" + uuid.NewString() + ".m4a"

	tx, err := a.db.Begin(c.Request.Context())
	if err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to start transaction")
		return
	}
	defer tx.Rollback(c.Request.Context())

	if _, err := tx.Exec(
		c.Request.Context(),
		`INSERT INTO "VoiceClip" (
			id, "householdId", "babyId", "audioUrl", transcript, "parsedEventsJson", "confidenceJson", status, "createdAt"
		) VALUES ($1, $2, $3, $4, $5, $6, $7, 'PARSED', NOW())`,
		clipID,
		baby.HouseholdID,
		baby.ID,
		audioURL,
		transcript,
		mustMarshalJSON([]eventItem{event}),
		mustMarshalJSON(event.Confidence),
	); err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to save voice clip")
		return
	}

	if err := recordAuditLog(
		c.Request.Context(),
		tx,
		baby.HouseholdID,
		user.ID,
		"VOICE_CLIP_PARSED",
		"VoiceClip",
		&clipID,
		gin.H{"baby_id": baby.ID},
	); err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to write audit log")
		return
	}

	if err := tx.Commit(c.Request.Context()); err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to commit transaction")
		return
	}

	c.JSON(http.StatusOK, voiceParseResponse{
		ClipID:       clipID,
		Transcript:   transcript,
		ParsedEvents: []eventItem{event},
		Status:       "PARSED",
	})
}

func (a *App) confirmEvents(c *gin.Context) {
	user, ok := authUserFromContext(c)
	if !ok {
		writeError(c, http.StatusUnauthorized, "Unauthorized")
		return
	}

	var payload confirmEventsRequest
	if !mustJSON(c, &payload) {
		return
	}
	if strings.TrimSpace(payload.ClipID) == "" {
		writeError(c, http.StatusBadRequest, "clip_id is required")
		return
	}
	if len(payload.Events) == 0 {
		writeError(c, http.StatusBadRequest, "events is required")
		return
	}
	for idx, event := range payload.Events {
		eventType, ok := normalizeEventType(event.Type)
		if !ok {
			writeError(c, http.StatusBadRequest, "Invalid event type at index "+strconv.Itoa(idx))
			return
		}
		if event.StartTime.IsZero() {
			writeError(c, http.StatusBadRequest, "start_time is required at index "+strconv.Itoa(idx))
			return
		}
		payload.Events[idx].Type = eventType
	}

	tx, err := a.db.Begin(c.Request.Context())
	if err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to start transaction")
		return
	}
	defer tx.Rollback(c.Request.Context())

	var householdID, babyID string
	err = tx.QueryRow(
		c.Request.Context(),
		`SELECT "householdId", "babyId" FROM "VoiceClip" WHERE id = $1`,
		payload.ClipID,
	).Scan(&householdID, &babyID)
	if errors.Is(err, pgx.ErrNoRows) {
		writeError(c, http.StatusNotFound, "Voice clip not found")
		return
	}
	if err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to load voice clip")
		return
	}

	if _, statusCode, err := a.getBabyWithAccess(c.Request.Context(), user.ID, babyID, writeRoles); err != nil {
		writeError(c, statusCode, err.Error())
		return
	}

	for _, event := range payload.Events {
		if _, err := tx.Exec(
			c.Request.Context(),
			`INSERT INTO "Event" (
				id, "babyId", type, "startTime", "endTime", "valueJson", "metadataJson", source, "createdBy", "createdAt"
			) VALUES ($1, $2, $3, $4, $5, $6, $7, 'VOICE', $8, NOW())`,
			uuid.NewString(),
			babyID,
			event.Type,
			event.StartTime.UTC(),
			event.EndTime,
			mustMarshalJSON(event.Value),
			mustMarshalJSON(event.Metadata),
			user.ID,
		); err != nil {
			writeError(c, http.StatusInternalServerError, "Failed to save event")
			return
		}
	}

	if _, err := tx.Exec(
		c.Request.Context(),
		`UPDATE "VoiceClip" SET status = 'CONFIRMED', "parsedEventsJson" = $2 WHERE id = $1`,
		payload.ClipID,
		mustMarshalJSON(payload.Events),
	); err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to update voice clip")
		return
	}

	if err := recordAuditLog(
		c.Request.Context(),
		tx,
		householdID,
		user.ID,
		"VOICE_CLIP_CONFIRMED",
		"VoiceClip",
		&payload.ClipID,
		gin.H{"saved_event_count": len(payload.Events)},
	); err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to write audit log")
		return
	}

	if err := tx.Commit(c.Request.Context()); err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to commit transaction")
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"status":            "CONFIRMED",
		"clip_id":           payload.ClipID,
		"saved_event_count": len(payload.Events),
	})
}

func (a *App) quickLastPooTime(c *gin.Context) {
	user, ok := authUserFromContext(c)
	if !ok {
		writeError(c, http.StatusUnauthorized, "Unauthorized")
		return
	}
	babyID := c.Query("baby_id")
	tone := strings.TrimSpace(c.DefaultQuery("tone", "neutral"))

	baby, statusCode, err := a.getBabyWithAccess(c.Request.Context(), user.ID, babyID, readRoles)
	if err != nil {
		writeError(c, statusCode, err.Error())
		return
	}

	var lastPoo time.Time
	err = a.db.QueryRow(
		c.Request.Context(),
		`SELECT "startTime" FROM "Event"
		 WHERE "babyId" = $1 AND type = 'POO'
		 ORDER BY "startTime" DESC LIMIT 1`,
		baby.ID,
	).Scan(&lastPoo)
	if errors.Is(err, pgx.ErrNoRows) {
		c.JSON(http.StatusOK, gin.H{
			"last_poo_time":  nil,
			"reference_text": "No confirmed poo events are stored yet.",
			"message":        "No poo records yet. Add one and I can answer immediately.",
		})
		return
	}
	if err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to load poo events")
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"last_poo_time":  lastPoo.UTC(),
		"reference_text": "Based on confirmed event logs for this baby.",
		"message": toneWrap(
			tone,
			"Last poo was logged at "+lastPoo.UTC().Format("15:04")+" UTC.",
			"The latest recorded poo event time is "+lastPoo.UTC().Format("15:04")+" UTC.",
			"Last poo: "+lastPoo.UTC().Format("15:04")+" UTC.",
		),
	})
}

func (a *App) quickNextFeedingETA(c *gin.Context) {
	user, ok := authUserFromContext(c)
	if !ok {
		writeError(c, http.StatusUnauthorized, "Unauthorized")
		return
	}
	babyID := c.Query("baby_id")
	tone := strings.TrimSpace(c.DefaultQuery("tone", "neutral"))

	baby, statusCode, err := a.getBabyWithAccess(c.Request.Context(), user.ID, babyID, readRoles)
	if err != nil {
		writeError(c, statusCode, err.Error())
		return
	}

	rows, err := a.db.Query(
		c.Request.Context(),
		`SELECT "startTime" FROM "Event"
		 WHERE "babyId" = $1 AND type IN ('FORMULA', 'BREASTFEED')
		 ORDER BY "startTime" DESC LIMIT 10`,
		baby.ID,
	)
	if err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to load feeding events")
		return
	}
	defer rows.Close()

	var times []time.Time
	for rows.Next() {
		var startedAt time.Time
		if err := rows.Scan(&startedAt); err != nil {
			writeError(c, http.StatusInternalServerError, "Failed to parse feeding events")
			return
		}
		times = append(times, startedAt.UTC())
	}

	result := calculateNextFeedingETA(times, time.Now().UTC())
	if result.ETAMinutes == nil || result.AverageIntervalMinutes == nil {
		c.JSON(http.StatusOK, gin.H{
			"eta_minutes":    nil,
			"unstable":       true,
			"reference_text": "At least two feeding records are required.",
			"message":        "Not enough feeding history yet. Add one or two more feeding events.",
		})
		return
	}

	avgH := *result.AverageIntervalMinutes / 60
	avgM := *result.AverageIntervalMinutes % 60
	c.JSON(http.StatusOK, gin.H{
		"eta_minutes":    *result.ETAMinutes,
		"unstable":       false,
		"reference_text": "Computed from " + strconv.Itoa(len(times)) + " recent feeding events.",
		"message": toneWrap(
			tone,
			"Estimated next feeding in "+strconv.Itoa(*result.ETAMinutes)+" minutes based on a "+strconv.Itoa(avgH)+"h "+strconv.Itoa(avgM)+"m average interval.",
			"The recommended next feeding time is in "+strconv.Itoa(*result.ETAMinutes)+" minutes, based on an average interval of "+strconv.Itoa(avgH)+"h "+strconv.Itoa(avgM)+"m.",
			"ETA "+strconv.Itoa(*result.ETAMinutes)+"m (avg "+strconv.Itoa(avgH)+"h "+strconv.Itoa(avgM)+"m).",
		),
	})
}

func (a *App) quickTodaySummary(c *gin.Context) {
	user, ok := authUserFromContext(c)
	if !ok {
		writeError(c, http.StatusUnauthorized, "Unauthorized")
		return
	}
	babyID := c.Query("baby_id")

	baby, statusCode, err := a.getBabyWithAccess(c.Request.Context(), user.ID, babyID, readRoles)
	if err != nil {
		writeError(c, statusCode, err.Error())
		return
	}

	start := startOfUTCDay(time.Now().UTC())
	end := start.Add(24 * time.Hour)

	rows, err := a.db.Query(
		c.Request.Context(),
		`SELECT type, "startTime", "endTime", "valueJson"
		 FROM "Event"
		 WHERE "babyId" = $1 AND "startTime" >= $2 AND "startTime" < $3`,
		baby.ID,
		start,
		end,
	)
	if err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to load events")
		return
	}
	defer rows.Close()

	counts := map[string]int{}
	formulaTotal := 0.0
	sleepMinutes := 0
	for rows.Next() {
		var eventType string
		var startedAt time.Time
		var endedAt *time.Time
		var valueRaw []byte
		if err := rows.Scan(&eventType, &startedAt, &endedAt, &valueRaw); err != nil {
			writeError(c, http.StatusInternalServerError, "Failed to parse events")
			return
		}
		counts[eventType]++
		valueJSON := parseJSONStringMap(valueRaw)
		if eventType == "FORMULA" {
			formulaTotal += extractNumberFromMap(valueJSON, "ml", "amount_ml", "volume_ml")
		}
		if eventType == "SLEEP" && endedAt != nil {
			minutes := int(endedAt.UTC().Sub(startedAt.UTC()).Minutes())
			if minutes > 0 {
				sleepMinutes += minutes
			}
		}
	}

	lines := []string{
		"Feedings: " + strconv.Itoa(counts["FORMULA"]+counts["BREASTFEED"]),
		"Formula total: " + strconv.Itoa(int(formulaTotal)) + " ml",
		"Sleep logged: " + strconv.Itoa(sleepMinutes) + " minutes",
		"Diaper events: pee " + strconv.Itoa(counts["PEE"]) + ", poo " + strconv.Itoa(counts["POO"]),
	}
	c.JSON(http.StatusOK, gin.H{
		"summary_lines":  lines,
		"reference_text": "Derived from today's confirmed events.",
	})
}

func (a *App) aiQuery(c *gin.Context) {
	user, ok := authUserFromContext(c)
	if !ok {
		writeError(c, http.StatusUnauthorized, "Unauthorized")
		return
	}
	var payload aiQueryRequest
	if !mustJSON(c, &payload) {
		return
	}
	if payload.Tone == "" {
		payload.Tone = "neutral"
	}

	baby, statusCode, err := a.getBabyWithAccess(c.Request.Context(), user.ID, payload.BabyID, readRoles)
	if err != nil {
		writeError(c, statusCode, err.Error())
		return
	}

	question := strings.ToLower(strings.TrimSpace(payload.Question))
	labels := []string{"general_information"}
	if payload.UsePersonalData {
		labels = []string{"record_based"}
	}

	if payload.UsePersonalData && (strings.Contains(question, "poo") || strings.Contains(question, "diaper")) {
		var last time.Time
		err := a.db.QueryRow(
			c.Request.Context(),
			`SELECT "startTime" FROM "Event"
			 WHERE "babyId" = $1 AND type = 'POO'
			 ORDER BY "startTime" DESC LIMIT 1`,
			baby.ID,
		).Scan(&last)
		if errors.Is(err, pgx.ErrNoRows) {
			c.JSON(http.StatusOK, gin.H{
				"answer":            "No poo records found yet.",
				"labels":            labels,
				"tone":              payload.Tone,
				"use_personal_data": payload.UsePersonalData,
			})
			return
		}
		if err != nil {
			writeError(c, http.StatusInternalServerError, "Failed to load events")
			return
		}
		c.JSON(http.StatusOK, gin.H{
			"answer":            "Latest poo event is at " + last.UTC().Format(time.RFC3339) + ".",
			"labels":            labels,
			"tone":              payload.Tone,
			"use_personal_data": payload.UsePersonalData,
		})
		return
	}

	if payload.UsePersonalData && (strings.Contains(question, "feed") || strings.Contains(question, "eta")) {
		rows, err := a.db.Query(
			c.Request.Context(),
			`SELECT "startTime" FROM "Event"
			 WHERE "babyId" = $1 AND type IN ('FORMULA', 'BREASTFEED')
			 ORDER BY "startTime" DESC LIMIT 10`,
			baby.ID,
		)
		if err != nil {
			writeError(c, http.StatusInternalServerError, "Failed to load feeding events")
			return
		}
		defer rows.Close()
		var times []time.Time
		for rows.Next() {
			var startedAt time.Time
			if err := rows.Scan(&startedAt); err == nil {
				times = append(times, startedAt.UTC())
			}
		}
		result := calculateNextFeedingETA(times, time.Now().UTC())
		answer := "Need at least two feeding logs to estimate next feeding."
		if result.ETAMinutes != nil {
			answer = "Estimated next feeding in about " + strconv.Itoa(*result.ETAMinutes) + " minutes."
		}
		c.JSON(http.StatusOK, gin.H{
			"answer":            answer,
			"labels":            labels,
			"tone":              payload.Tone,
			"use_personal_data": payload.UsePersonalData,
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"answer":            "I can answer about feeding ETA, diaper timing, and daily summaries once logs are available.",
		"labels":            labels,
		"tone":              payload.Tone,
		"use_personal_data": payload.UsePersonalData,
	})
}

func (a *App) getDailyReport(c *gin.Context) {
	user, ok := authUserFromContext(c)
	if !ok {
		writeError(c, http.StatusUnauthorized, "Unauthorized")
		return
	}
	babyID := c.Query("baby_id")
	dateRaw := c.Query("date")
	targetDate, err := parseDate(dateRaw)
	if err != nil {
		writeError(c, http.StatusBadRequest, "date must be YYYY-MM-DD")
		return
	}

	baby, statusCode, err := a.getBabyWithAccess(c.Request.Context(), user.ID, babyID, readRoles)
	if err != nil {
		writeError(c, statusCode, err.Error())
		return
	}

	var summaryText string
	err = a.db.QueryRow(
		c.Request.Context(),
		`SELECT "summaryText" FROM "Report"
		 WHERE "babyId" = $1 AND "periodType" = 'DAILY' AND "periodStart" = $2
		 ORDER BY "createdAt" DESC LIMIT 1`,
		baby.ID,
		targetDate,
	).Scan(&summaryText)
	if err == nil {
		lines := splitNonEmptyLines(summaryText)
		c.JSON(http.StatusOK, gin.H{
			"baby_id": baby.ID,
			"date":    targetDate.Format("2006-01-02"),
			"summary": lines,
			"labels":  []string{"record_based"},
		})
		return
	}
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		writeError(c, http.StatusInternalServerError, "Failed to load reports")
		return
	}

	start := targetDate
	end := start.Add(24 * time.Hour)
	rows, err := a.db.Query(
		c.Request.Context(),
		`SELECT type, "startTime", "endTime", "valueJson"
		 FROM "Event"
		 WHERE "babyId" = $1 AND "startTime" >= $2 AND "startTime" < $3`,
		baby.ID,
		start,
		end,
	)
	if err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to load events")
		return
	}
	defer rows.Close()

	counts := map[string]int{}
	formulaTotal := 0.0
	sleepMinutes := 0
	for rows.Next() {
		var eventType string
		var startedAt time.Time
		var endedAt *time.Time
		var valueRaw []byte
		if err := rows.Scan(&eventType, &startedAt, &endedAt, &valueRaw); err != nil {
			writeError(c, http.StatusInternalServerError, "Failed to parse events")
			return
		}
		counts[eventType]++
		valueMap := parseJSONStringMap(valueRaw)
		if eventType == "FORMULA" {
			formulaTotal += extractNumberFromMap(valueMap, "ml", "amount_ml", "volume_ml")
		}
		if eventType == "SLEEP" && endedAt != nil {
			duration := int(endedAt.UTC().Sub(startedAt.UTC()).Minutes())
			if duration > 0 {
				sleepMinutes += duration
			}
		}
	}

	c.JSON(http.StatusOK, gin.H{
		"baby_id": baby.ID,
		"date":    targetDate.Format("2006-01-02"),
		"summary": []string{
			"Feeding events: " + strconv.Itoa(counts["FORMULA"]+counts["BREASTFEED"]),
			"Formula total: " + strconv.Itoa(int(formulaTotal)) + " ml",
			"Sleep total: " + strconv.Itoa(sleepMinutes) + " minutes",
			"Diaper events: pee " + strconv.Itoa(counts["PEE"]) + ", poo " + strconv.Itoa(counts["POO"]),
		},
		"labels": []string{"record_based"},
	})
}

func (a *App) getWeeklyReport(c *gin.Context) {
	user, ok := authUserFromContext(c)
	if !ok {
		writeError(c, http.StatusUnauthorized, "Unauthorized")
		return
	}
	babyID := c.Query("baby_id")
	weekStartRaw := c.Query("week_start")
	start, err := parseDate(weekStartRaw)
	if err != nil {
		writeError(c, http.StatusBadRequest, "week_start must be YYYY-MM-DD")
		return
	}

	baby, statusCode, err := a.getBabyWithAccess(c.Request.Context(), user.ID, babyID, readRoles)
	if err != nil {
		writeError(c, statusCode, err.Error())
		return
	}

	var metricsRaw []byte
	err = a.db.QueryRow(
		c.Request.Context(),
		`SELECT "metricsJson" FROM "Report"
		 WHERE "babyId" = $1 AND "periodType" = 'WEEKLY' AND "periodStart" = $2
		 ORDER BY "createdAt" DESC LIMIT 1`,
		baby.ID,
		start,
	).Scan(&metricsRaw)
	if err == nil {
		metrics := parseJSONStringMap(metricsRaw)
		trend, _ := metrics["trend"].(map[string]any)
		suggestionsAny, _ := metrics["suggestions"].([]any)
		suggestions := make([]string, 0, len(suggestionsAny))
		for _, item := range suggestionsAny {
			suggestions = append(suggestions, strings.TrimSpace(toString(item)))
		}
		c.JSON(http.StatusOK, gin.H{
			"baby_id":     baby.ID,
			"week_start":  start.Format("2006-01-02"),
			"trend":       trend,
			"suggestions": suggestions,
			"labels":      []string{"record_based"},
		})
		return
	}
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		writeError(c, http.StatusInternalServerError, "Failed to load reports")
		return
	}

	currentMetrics, err := a.computeWeeklyMetrics(c, baby.ID, start, start.Add(7*24*time.Hour))
	if err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to compute weekly metrics")
		return
	}
	previousStart := start.Add(-7 * 24 * time.Hour)
	previousMetrics, err := a.computeWeeklyMetrics(c, baby.ID, previousStart, start)
	if err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to compute weekly metrics")
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"baby_id":    baby.ID,
		"week_start": start.Format("2006-01-02"),
		"trend": gin.H{
			"feeding_total_ml": trendString(currentMetrics.FeedingML, previousMetrics.FeedingML),
			"sleep_total_min":  trendString(float64(currentMetrics.SleepMinutes), float64(previousMetrics.SleepMinutes)),
		},
		"suggestions": []string{
			"Keep logging feeding and sleep consistently to improve ETA quality.",
			"If diaper events spike, review feeding intervals and hydration patterns.",
		},
		"labels": []string{"record_based"},
	})
}

func (a *App) computeWeeklyMetrics(c *gin.Context, babyID string, start, end time.Time) (weeklyMetrics, error) {
	rows, err := a.db.Query(
		c.Request.Context(),
		`SELECT type, "startTime", "endTime", "valueJson"
		 FROM "Event"
		 WHERE "babyId" = $1 AND "startTime" >= $2 AND "startTime" < $3`,
		babyID,
		start,
		end,
	)
	if err != nil {
		return weeklyMetrics{}, err
	}
	defer rows.Close()

	metrics := weeklyMetrics{}
	for rows.Next() {
		var eventType string
		var startedAt time.Time
		var endedAt *time.Time
		var valueRaw []byte
		if err := rows.Scan(&eventType, &startedAt, &endedAt, &valueRaw); err != nil {
			return weeklyMetrics{}, err
		}
		valueMap := parseJSONStringMap(valueRaw)
		if eventType == "FORMULA" {
			metrics.FeedingML += extractNumberFromMap(valueMap, "ml", "amount_ml", "volume_ml")
		}
		if eventType == "SLEEP" && endedAt != nil {
			duration := int(endedAt.UTC().Sub(startedAt.UTC()).Minutes())
			if duration > 0 {
				metrics.SleepMinutes += duration
			}
		}
	}
	return metrics, nil
}
func mustMarshalJSON(input any) []byte {
	encoded, err := json.Marshal(input)
	if err != nil {
		return []byte("{}")
	}
	return encoded
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

func (a *App) createPhotoUploadURL(c *gin.Context) {
	user, ok := authUserFromContext(c)
	if !ok {
		writeError(c, http.StatusUnauthorized, "Unauthorized")
		return
	}

	albumID := strings.TrimSpace(c.Query("album_id"))
	if albumID == "" {
		writeError(c, http.StatusBadRequest, "album_id is required")
		return
	}

	var householdID string
	err := a.db.QueryRow(
		c.Request.Context(),
		`SELECT "householdId" FROM "Album" WHERE id = $1`,
		albumID,
	).Scan(&householdID)
	if errors.Is(err, pgx.ErrNoRows) {
		writeError(c, http.StatusNotFound, "Album not found")
		return
	}
	if err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to load album")
		return
	}

	if _, statusCode, err := a.assertHouseholdAccess(c.Request.Context(), user.ID, householdID, writeRoles); err != nil {
		writeError(c, statusCode, err.Error())
		return
	}

	now := time.Now().UTC()
	objectKey := fmt.Sprintf("photos/%04d/%02d/%s.jpg", now.Year(), int(now.Month()), uuid.NewString())

	if err := recordAuditLog(
		c.Request.Context(),
		a.db,
		householdID,
		user.ID,
		"PHOTO_UPLOAD_URL_CREATED",
		"Album",
		&albumID,
		gin.H{"object_key": objectKey},
	); err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to write audit log")
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"album_id":   albumID,
		"upload_url": "https://storage.example.com/upload/" + objectKey,
		"object_key": objectKey,
	})
}

func (a *App) completePhotoUpload(c *gin.Context) {
	user, ok := authUserFromContext(c)
	if !ok {
		writeError(c, http.StatusUnauthorized, "Unauthorized")
		return
	}

	var payload photoUploadCompleteRequest
	if !mustJSON(c, &payload) {
		return
	}
	payload.AlbumID = strings.TrimSpace(payload.AlbumID)
	payload.ObjectKey = strings.TrimSpace(payload.ObjectKey)
	if payload.AlbumID == "" || payload.ObjectKey == "" {
		writeError(c, http.StatusBadRequest, "album_id and object_key are required")
		return
	}

	var householdID string
	err := a.db.QueryRow(
		c.Request.Context(),
		`SELECT "householdId" FROM "Album" WHERE id = $1`,
		payload.AlbumID,
	).Scan(&householdID)
	if errors.Is(err, pgx.ErrNoRows) {
		writeError(c, http.StatusNotFound, "Album not found")
		return
	}
	if err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to load album")
		return
	}

	if _, statusCode, err := a.assertHouseholdAccess(c.Request.Context(), user.ID, householdID, writeRoles); err != nil {
		writeError(c, statusCode, err.Error())
		return
	}

	variants := map[string]string{
		"thumb":   payload.ObjectKey + "?w=320",
		"preview": payload.ObjectKey + "?w=1080",
		"origin":  payload.ObjectKey,
	}

	tx, err := a.db.Begin(c.Request.Context())
	if err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to start transaction")
		return
	}
	defer tx.Rollback(c.Request.Context())

	photoID := uuid.NewString()
	if _, err := tx.Exec(
		c.Request.Context(),
		`INSERT INTO "PhotoAsset" (
			id, "albumId", "uploaderUserId", "variantsJson", visibility, downloadable, "createdAt"
		) VALUES ($1, $2, $3, $4, 'HOUSEHOLD', $5, NOW())`,
		photoID,
		payload.AlbumID,
		user.ID,
		mustMarshalJSON(variants),
		payload.Downloadable,
	); err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to create photo")
		return
	}

	if err := recordAuditLog(
		c.Request.Context(),
		tx,
		householdID,
		user.ID,
		"PHOTO_UPLOAD_COMPLETED",
		"PhotoAsset",
		&photoID,
		gin.H{"album_id": payload.AlbumID, "downloadable": payload.Downloadable},
	); err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to write audit log")
		return
	}

	if err := tx.Commit(c.Request.Context()); err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to commit transaction")
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"status":       "uploaded",
		"photo_id":     photoID,
		"album_id":     payload.AlbumID,
		"downloadable": payload.Downloadable,
		"variants":     variants,
	})
}

func (a *App) getMySubscription(c *gin.Context) {
	user, ok := authUserFromContext(c)
	if !ok {
		writeError(c, http.StatusUnauthorized, "Unauthorized")
		return
	}

	householdID := strings.TrimSpace(c.Query("household_id"))
	if householdID == "" {
		writeError(c, http.StatusBadRequest, "household_id is required")
		return
	}
	if _, statusCode, err := a.assertHouseholdAccess(c.Request.Context(), user.ID, householdID, readRoles); err != nil {
		writeError(c, statusCode, err.Error())
		return
	}

	var plan, statusValue string
	err := a.db.QueryRow(
		c.Request.Context(),
		`SELECT plan, status FROM "Subscription" WHERE "householdId" = $1 LIMIT 1`,
		householdID,
	).Scan(&plan, &statusValue)
	if errors.Is(err, pgx.ErrNoRows) {
		c.JSON(http.StatusOK, gin.H{
			"household_id": householdID,
			"plan":         nil,
			"status":       "none",
		})
		return
	}
	if err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to load subscription")
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"household_id": householdID,
		"plan":         plan,
		"status":       strings.ToLower(statusValue),
	})
}

func (a *App) checkoutSubscription(c *gin.Context) {
	user, ok := authUserFromContext(c)
	if !ok {
		writeError(c, http.StatusUnauthorized, "Unauthorized")
		return
	}

	var payload checkoutRequest
	if !mustJSON(c, &payload) {
		return
	}
	payload.HouseholdID = strings.TrimSpace(payload.HouseholdID)
	payload.Plan = strings.ToUpper(strings.TrimSpace(payload.Plan))
	if payload.HouseholdID == "" || payload.Plan == "" {
		writeError(c, http.StatusBadRequest, "household_id and plan are required")
		return
	}
	validPlans := map[string]struct{}{
		"PHOTO_SHARE": {},
		"AI_ONLY":     {},
		"AI_PHOTO":    {},
	}
	if _, ok := validPlans[payload.Plan]; !ok {
		writeError(c, http.StatusBadRequest, "Invalid subscription plan")
		return
	}
	if _, statusCode, err := a.assertHouseholdAccess(c.Request.Context(), user.ID, payload.HouseholdID, billingRoles); err != nil {
		writeError(c, statusCode, err.Error())
		return
	}

	tx, err := a.db.Begin(c.Request.Context())
	if err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to start transaction")
		return
	}
	defer tx.Rollback(c.Request.Context())

	var subscriptionID string
	err = tx.QueryRow(
		c.Request.Context(),
		`SELECT id FROM "Subscription" WHERE "householdId" = $1 LIMIT 1`,
		payload.HouseholdID,
	).Scan(&subscriptionID)
	if errors.Is(err, pgx.ErrNoRows) {
		subscriptionID = uuid.NewString()
		if _, err := tx.Exec(
			c.Request.Context(),
			`INSERT INTO "Subscription" (id, "householdId", plan, status, "createdAt")
			 VALUES ($1, $2, $3, 'TRIALING', NOW())`,
			subscriptionID,
			payload.HouseholdID,
			payload.Plan,
		); err != nil {
			writeError(c, http.StatusInternalServerError, "Failed to create subscription")
			return
		}
	} else if err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to load subscription")
		return
	} else {
		if _, err := tx.Exec(
			c.Request.Context(),
			`UPDATE "Subscription" SET plan = $2, status = 'TRIALING' WHERE id = $1`,
			subscriptionID,
			payload.Plan,
		); err != nil {
			writeError(c, http.StatusInternalServerError, "Failed to update subscription")
			return
		}
	}

	if err := recordAuditLog(
		c.Request.Context(),
		tx,
		payload.HouseholdID,
		user.ID,
		"SUBSCRIPTION_CHECKOUT_STARTED",
		"Subscription",
		&subscriptionID,
		gin.H{"plan": payload.Plan},
	); err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to write audit log")
		return
	}

	if err := tx.Commit(c.Request.Context()); err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to commit transaction")
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"status":       "pending_payment",
		"plan":         payload.Plan,
		"household_id": payload.HouseholdID,
	})
}

func (a *App) assistantDialog(ctx context.Context, babyID, tone, intent string) (string, string, error) {
	switch intent {
	case "GetLastPooTime":
		var lastPoo time.Time
		err := a.db.QueryRow(
			ctx,
			`SELECT "startTime" FROM "Event"
			 WHERE "babyId" = $1 AND type = 'POO'
			 ORDER BY "startTime" DESC LIMIT 1`,
			babyID,
		).Scan(&lastPoo)
		if errors.Is(err, pgx.ErrNoRows) {
			return "No poo logs yet.", "No confirmed poo events are available.", nil
		}
		if err != nil {
			return "", "", err
		}
		dialog := toneWrap(
			tone,
			"Last poo was at "+lastPoo.UTC().Format("15:04")+" UTC.",
			"The latest recorded poo event time is "+lastPoo.UTC().Format("15:04")+" UTC.",
			"Last poo: "+lastPoo.UTC().Format("15:04")+" UTC.",
		)
		return dialog, "Based on confirmed event logs.", nil

	case "GetNextFeedingEta":
		rows, err := a.db.Query(
			ctx,
			`SELECT "startTime" FROM "Event"
			 WHERE "babyId" = $1 AND type IN ('FORMULA', 'BREASTFEED')
			 ORDER BY "startTime" DESC LIMIT 10`,
			babyID,
		)
		if err != nil {
			return "", "", err
		}
		defer rows.Close()

		var feedingTimes []time.Time
		for rows.Next() {
			var startedAt time.Time
			if err := rows.Scan(&startedAt); err != nil {
				return "", "", err
			}
			feedingTimes = append(feedingTimes, startedAt.UTC())
		}

		result := calculateNextFeedingETA(feedingTimes, time.Now().UTC())
		if result.ETAMinutes == nil || result.AverageIntervalMinutes == nil {
			return "Need more feeding logs to calculate ETA.", "At least two feeding records are required.", nil
		}

		avgH := *result.AverageIntervalMinutes / 60
		avgM := *result.AverageIntervalMinutes % 60
		dialog := toneWrap(
			tone,
			"Next feeding is in about "+strconv.Itoa(*result.ETAMinutes)+" minutes.",
			"The recommended next feeding time is in "+strconv.Itoa(*result.ETAMinutes)+" minutes.",
			"ETA "+strconv.Itoa(*result.ETAMinutes)+"m.",
		)
		reference := fmt.Sprintf(
			"Computed from %d recent feeding events (avg %dh %dm).",
			len(feedingTimes),
			avgH,
			avgM,
		)
		return dialog, reference, nil

	case "GetTodaySummary":
		start := startOfUTCDay(time.Now().UTC())
		end := start.Add(24 * time.Hour)
		rows, err := a.db.Query(
			ctx,
			`SELECT type FROM "Event"
			 WHERE "babyId" = $1 AND "startTime" >= $2 AND "startTime" < $3`,
			babyID,
			start,
			end,
		)
		if err != nil {
			return "", "", err
		}
		defer rows.Close()

		counts := map[string]int{}
		total := 0
		for rows.Next() {
			var eventType string
			if err := rows.Scan(&eventType); err != nil {
				return "", "", err
			}
			counts[eventType]++
			total++
		}

		dialog := toneWrap(
			tone,
			"Today: "+strconv.Itoa(total)+" events, poo "+strconv.Itoa(counts["POO"])+", pee "+strconv.Itoa(counts["PEE"])+".",
			"Today's summary includes "+strconv.Itoa(total)+" events, with poo "+strconv.Itoa(counts["POO"])+" and pee "+strconv.Itoa(counts["PEE"])+".",
			"Today: "+strconv.Itoa(total)+" events.",
		)
		return dialog, "Derived from today's confirmed events.", nil

	default:
		return "Unsupported intent.", "intent_name", nil
	}
}

func (a *App) handleSiriIntent(c *gin.Context, intent string) {
	user, ok := authUserFromContext(c)
	if !ok {
		writeError(c, http.StatusUnauthorized, "Unauthorized")
		return
	}

	var payload siriIntentRequest
	if !mustJSON(c, &payload) {
		return
	}
	payload.BabyID = strings.TrimSpace(payload.BabyID)
	if payload.BabyID == "" {
		writeError(c, http.StatusBadRequest, "baby_id is required")
		return
	}
	payload.Tone = normalizeTone(payload.Tone)

	baby, statusCode, err := a.getBabyWithAccess(c.Request.Context(), user.ID, payload.BabyID, readRoles)
	if err != nil {
		writeError(c, statusCode, err.Error())
		return
	}

	dialog, reference, err := a.assistantDialog(c.Request.Context(), baby.ID, payload.Tone, intent)
	if err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to build assistant response")
		return
	}
	c.JSON(http.StatusOK, gin.H{"dialog": dialog, "reference": reference})
}

func (a *App) siriLastPoo(c *gin.Context) {
	a.handleSiriIntent(c, "GetLastPooTime")
}

func (a *App) siriNextFeeding(c *gin.Context) {
	a.handleSiriIntent(c, "GetNextFeedingEta")
}

func (a *App) siriTodaySummary(c *gin.Context) {
	a.handleSiriIntent(c, "GetTodaySummary")
}

func (a *App) siriDynamic(c *gin.Context) {
	intentName := strings.TrimSpace(c.Param("intent_name"))
	a.handleSiriIntent(c, intentName)
}

func (a *App) bixbyQuery(c *gin.Context) {
	user, ok := authUserFromContext(c)
	if !ok {
		writeError(c, http.StatusUnauthorized, "Unauthorized")
		return
	}

	var payload bixbyQueryRequest
	if !mustJSON(c, &payload) {
		return
	}
	payload.BabyID = strings.TrimSpace(payload.BabyID)
	payload.CapsuleAction = strings.TrimSpace(payload.CapsuleAction)
	payload.Tone = normalizeTone(payload.Tone)
	if payload.BabyID == "" || payload.CapsuleAction == "" {
		writeError(c, http.StatusBadRequest, "capsule_action and baby_id are required")
		return
	}

	baby, statusCode, err := a.getBabyWithAccess(c.Request.Context(), user.ID, payload.BabyID, readRoles)
	if err != nil {
		writeError(c, statusCode, err.Error())
		return
	}

	intent := payload.CapsuleAction
	switch intent {
	case "GetLastPooTime", "GetNextFeedingEta", "GetTodaySummary":
	default:
		intent = "GetTodaySummary"
	}

	dialog, _, err := a.assistantDialog(c.Request.Context(), baby.ID, payload.Tone, intent)
	if err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to build assistant response")
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"answer":       dialog,
		"resultMoment": true,
	})
}
