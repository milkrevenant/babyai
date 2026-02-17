package server

import (
	"errors"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

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
	normalizedSex := normalizeBabySex(payload.BabySex)
	if strings.TrimSpace(payload.BabySex) != "" && normalizedSex == "" {
		writeError(c, http.StatusBadRequest, "baby_sex must be one of: male, female, other, unknown")
		return
	}
	if normalizedSex == "" {
		normalizedSex = "unknown"
	}
	feedingMethod := normalizeFeedingMethod(payload.FeedingMethod)
	if strings.TrimSpace(payload.FeedingMethod) != "" && feedingMethod == "" {
		writeError(c, http.StatusBadRequest, "feeding_method must be one of: formula, breastmilk, mixed")
		return
	}
	if feedingMethod == "" {
		feedingMethod = "mixed"
	}
	formulaType := normalizeFormulaType(payload.FormulaType)
	if strings.TrimSpace(payload.FormulaType) != "" && formulaType == "" {
		writeError(c, http.StatusBadRequest, "formula_type is invalid")
		return
	}
	if formulaType == "" {
		formulaType = "standard"
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
	var sexValue any
	if normalizedSex == "unknown" {
		sexValue = nil
	} else {
		sexValue = normalizedSex
	}

	if _, err := tx.Exec(
		c.Request.Context(),
		`INSERT INTO "Baby" (id, "householdId", name, "birthDate", sex, "createdAt")
		 VALUES ($1, $2, $3, $4, $5, NOW())`,
		babyID,
		householdID,
		strings.TrimSpace(payload.BabyName),
		birthDate,
		sexValue,
	); err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to create baby profile")
		return
	}

	persona, err := loadPersonaSettingsWithQuerier(c.Request.Context(), tx, user.ID)
	if err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to load settings")
		return
	}
	babySettings := readBabySettings(persona, babyID)
	if payload.BabyWeightKg != nil {
		babySettings["weight_kg"] = roundToOneDecimal(clampWeightKg(*payload.BabyWeightKg))
	}
	babySettings["feeding_method"] = feedingMethod
	babySettings["formula_brand"] = strings.TrimSpace(payload.FormulaBrand)
	babySettings["formula_product"] = strings.TrimSpace(payload.FormulaProduct)
	babySettings["formula_type"] = formulaType
	if payload.FormulaContainsStarch != nil {
		babySettings["formula_contains_starch"] = *payload.FormulaContainsStarch
	}
	babySettings["updated_at"] = time.Now().UTC().Format(time.RFC3339)
	writeBabySettings(persona, babyID, babySettings)
	if err := upsertPersonaSettingsWithQuerier(c.Request.Context(), tx, user.ID, persona); err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to save settings")
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

	var householdID, babyID string
	err := a.db.QueryRow(
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

	tx, err := a.db.Begin(c.Request.Context())
	if err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to start transaction")
		return
	}
	defer tx.Rollback(c.Request.Context())

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
