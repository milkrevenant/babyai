package server

import (
	"errors"
	"log"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

var startableManualEventTypes = map[string]struct{}{
	"FORMULA":    {},
	"BREASTFEED": {},
	"SLEEP":      {},
	"PEE":        {},
	"POO":        {},
	"MEDICATION": {},
	"MEMO":       {},
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
					id, "babyId", type, "startTime", "endTime", "valueJson", "metadataJson", status, source, "createdBy", "createdAt"
				) VALUES ($1, $2, $3, $4, $5, $6, $7, 'CLOSED', 'VOICE', $8, NOW())`,
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
		if err := a.projectEventToPRDTables(
			c.Request.Context(),
			tx,
			babyID,
			event.Type,
			event.StartTime.UTC(),
			event.EndTime,
			event.Value,
		); err != nil {
			log.Printf("projectEventToPRDTables failed clip_id=%s baby_id=%s event_type=%s err=%v", payload.ClipID, babyID, event.Type, err)
			writeError(c, http.StatusInternalServerError, "Failed to project PRD event")
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

func (a *App) createManualEvent(c *gin.Context) {
	user, ok := authUserFromContext(c)
	if !ok {
		writeError(c, http.StatusUnauthorized, "Unauthorized")
		return
	}

	var payload manualEventCreateRequest
	if !mustJSON(c, &payload) {
		return
	}

	babyID := strings.TrimSpace(payload.BabyID)
	if babyID == "" {
		writeError(c, http.StatusBadRequest, "baby_id is required")
		return
	}

	eventType, valid := normalizeEventType(payload.Type)
	if !valid {
		writeError(c, http.StatusBadRequest, "type is invalid")
		return
	}
	if payload.StartTime.IsZero() {
		writeError(c, http.StatusBadRequest, "start_time is required")
		return
	}

	startTime := payload.StartTime.UTC()
	var endTime any
	if payload.EndTime != nil {
		if payload.EndTime.UTC().Before(startTime) {
			writeError(c, http.StatusBadRequest, "end_time must be after start_time")
			return
		}
		parsed := payload.EndTime.UTC()
		endTime = parsed
	} else {
		endTime = nil
	}

	baby, statusCode, err := a.getBabyWithAccess(c.Request.Context(), user.ID, babyID, writeRoles)
	if err != nil {
		writeError(c, statusCode, err.Error())
		return
	}

	value := payload.Value
	if value == nil {
		value = map[string]any{}
	}
	metadata := payload.Metadata
	if metadata == nil {
		metadata = map[string]any{}
	}
	metadata["entry_mode"] = "manual_form"

	eventID := uuid.NewString()
	tx, err := a.db.Begin(c.Request.Context())
	if err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to start transaction")
		return
	}
	defer tx.Rollback(c.Request.Context())

	if _, err := tx.Exec(
		c.Request.Context(),
		`INSERT INTO "Event" (
			id, "babyId", type, "startTime", "endTime", "valueJson", "metadataJson", status, source, "createdBy", "createdAt"
		) VALUES ($1, $2, $3, $4, $5, $6, $7, 'CLOSED', 'MANUAL', $8, NOW())`,
		eventID,
		baby.ID,
		eventType,
		startTime,
		endTime,
		mustMarshalJSON(value),
		mustMarshalJSON(metadata),
		user.ID,
	); err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to save event")
		return
	}
	if err := a.projectEventToPRDTables(
		c.Request.Context(),
		tx,
		baby.ID,
		eventType,
		startTime,
		payload.EndTime,
		value,
	); err != nil {
		log.Printf("projectEventToPRDTables failed event_id=%s baby_id=%s event_type=%s err=%v", eventID, baby.ID, eventType, err)
		writeError(c, http.StatusInternalServerError, "Failed to project PRD event")
		return
	}

	if err := recordAuditLog(
		c.Request.Context(),
		tx,
		baby.HouseholdID,
		user.ID,
		"EVENT_MANUAL_CREATED",
		"Event",
		&eventID,
		gin.H{
			"baby_id": baby.ID,
			"type":    eventType,
		},
	); err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to write audit log")
		return
	}

	if err := tx.Commit(c.Request.Context()); err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to commit transaction")
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"status":   "CREATED",
		"event_id": eventID,
		"type":     eventType,
	})
}

func mergeJSONMap(base map[string]any, patch map[string]any) map[string]any {
	merged := make(map[string]any, len(base)+len(patch))
	for key, value := range base {
		merged[key] = value
	}
	for key, value := range patch {
		merged[key] = value
	}
	return merged
}

func (a *App) startManualEvent(c *gin.Context) {
	user, ok := authUserFromContext(c)
	if !ok {
		writeError(c, http.StatusUnauthorized, "Unauthorized")
		return
	}

	var payload manualEventStartRequest
	if !mustJSON(c, &payload) {
		return
	}

	babyID := strings.TrimSpace(payload.BabyID)
	if babyID == "" {
		writeError(c, http.StatusBadRequest, "baby_id is required")
		return
	}
	eventType, valid := normalizeEventType(payload.Type)
	if !valid {
		writeError(c, http.StatusBadRequest, "type is invalid")
		return
	}
	if _, startable := startableManualEventTypes[eventType]; !startable {
		writeError(c, http.StatusBadRequest, "type does not support start/complete flow")
		return
	}
	if payload.StartTime.IsZero() {
		writeError(c, http.StatusBadRequest, "start_time is required")
		return
	}
	startTime := payload.StartTime.UTC()

	baby, statusCode, err := a.getBabyWithAccess(c.Request.Context(), user.ID, babyID, writeRoles)
	if err != nil {
		writeError(c, statusCode, err.Error())
		return
	}

	value := payload.Value
	if value == nil {
		value = map[string]any{}
	}
	metadata := payload.Metadata
	if metadata == nil {
		metadata = map[string]any{}
	}
	metadata["entry_mode"] = "manual_start"

	tx, err := a.db.Begin(c.Request.Context())
	if err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to start transaction")
		return
	}
	defer tx.Rollback(c.Request.Context())

	var lockedBabyID string
	if err := tx.QueryRow(
		c.Request.Context(),
		`SELECT id FROM "Baby" WHERE id = $1 FOR UPDATE`,
		baby.ID,
	).Scan(&lockedBabyID); err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to lock baby record")
		return
	}

	var existingEventID string
	err = tx.QueryRow(
		c.Request.Context(),
		`SELECT id FROM "Event"
		 WHERE "babyId" = $1 AND type = $2 AND status = 'OPEN'
		 ORDER BY "startTime" DESC
		 LIMIT 1`,
		baby.ID,
		eventType,
	).Scan(&existingEventID)
	if err == nil {
		c.AbortWithStatusJSON(http.StatusConflict, gin.H{
			"detail":            "open event already exists for this type",
			"existing_event_id": existingEventID,
		})
		return
	}
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		writeError(c, http.StatusInternalServerError, "Failed to validate open event")
		return
	}

	eventID := uuid.NewString()
	if _, err := tx.Exec(
		c.Request.Context(),
		`INSERT INTO "Event" (
			id, "babyId", type, "startTime", "endTime", "valueJson", "metadataJson", status, source, "createdBy", "createdAt"
		) VALUES ($1, $2, $3, $4, NULL, $5, $6, 'OPEN', 'MANUAL', $7, NOW())`,
		eventID,
		baby.ID,
		eventType,
		startTime,
		mustMarshalJSON(value),
		mustMarshalJSON(metadata),
		user.ID,
	); err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to save start event")
		return
	}

	if err := recordAuditLog(
		c.Request.Context(),
		tx,
		baby.HouseholdID,
		user.ID,
		"EVENT_MANUAL_STARTED",
		"Event",
		&eventID,
		gin.H{
			"baby_id": baby.ID,
			"type":    eventType,
		},
	); err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to write audit log")
		return
	}

	if err := tx.Commit(c.Request.Context()); err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to commit transaction")
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"status":      "STARTED",
		"event_id":    eventID,
		"type":        eventType,
		"start_time":  startTime.Format(time.RFC3339),
		"event_state": "OPEN",
	})
}

func (a *App) updateManualEvent(c *gin.Context) {
	user, ok := authUserFromContext(c)
	if !ok {
		writeError(c, http.StatusUnauthorized, "Unauthorized")
		return
	}

	eventID := strings.TrimSpace(c.Param("event_id"))
	if eventID == "" {
		writeError(c, http.StatusBadRequest, "event_id is required")
		return
	}

	var payload manualEventUpdateRequest
	if !mustJSON(c, &payload) {
		return
	}

	hasType := payload.Type != nil && strings.TrimSpace(*payload.Type) != ""
	hasStart := payload.StartTime != nil && !payload.StartTime.IsZero()
	hasEnd := payload.EndTime != nil && !payload.EndTime.IsZero()
	if !hasType && !hasStart && !hasEnd && payload.Value == nil && payload.Metadata == nil {
		writeError(c, http.StatusBadRequest, "at least one field must be provided for update")
		return
	}

	var eventBabyID string
	err := a.db.QueryRow(
		c.Request.Context(),
		`SELECT "babyId" FROM "Event" WHERE id = $1`,
		eventID,
	).Scan(&eventBabyID)
	if errors.Is(err, pgx.ErrNoRows) {
		writeError(c, http.StatusNotFound, "Event not found")
		return
	}
	if err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to load event")
		return
	}

	baby, statusCode, err := a.getBabyWithAccess(c.Request.Context(), user.ID, eventBabyID, writeRoles)
	if err != nil {
		writeError(c, statusCode, err.Error())
		return
	}

	tx, err := a.db.Begin(c.Request.Context())
	if err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to start transaction")
		return
	}
	defer tx.Rollback(c.Request.Context())

	var existingType string
	var existingStatus string
	var existingStart time.Time
	var existingEnd *time.Time
	var existingValueRaw []byte
	var existingMetadataRaw []byte
	err = tx.QueryRow(
		c.Request.Context(),
		`SELECT type, status, "startTime", "endTime", "valueJson", "metadataJson"
		 FROM "Event"
		 WHERE id = $1 AND "babyId" = $2
		 FOR UPDATE`,
		eventID,
		baby.ID,
	).Scan(
		&existingType,
		&existingStatus,
		&existingStart,
		&existingEnd,
		&existingValueRaw,
		&existingMetadataRaw,
	)
	if errors.Is(err, pgx.ErrNoRows) {
		writeError(c, http.StatusNotFound, "Event not found")
		return
	}
	if err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to lock event")
		return
	}
	if existingStatus != "CLOSED" {
		c.AbortWithStatusJSON(http.StatusConflict, gin.H{
			"detail":       "only closed events can be updated",
			"event_id":     eventID,
			"event_status": existingStatus,
		})
		return
	}

	resolvedType := existingType
	if hasType {
		nextType, valid := normalizeEventType(*payload.Type)
		if !valid {
			writeError(c, http.StatusBadRequest, "type is invalid")
			return
		}
		resolvedType = nextType
	}

	resolvedStart := existingStart.UTC()
	if hasStart {
		resolvedStart = payload.StartTime.UTC()
	}

	resolvedEnd := existingEnd
	if hasEnd {
		parsed := payload.EndTime.UTC()
		resolvedEnd = &parsed
	}
	if resolvedEnd == nil {
		writeError(c, http.StatusBadRequest, "end_time is required for closed events")
		return
	}
	if resolvedEnd.UTC().Before(resolvedStart) {
		writeError(c, http.StatusBadRequest, "end_time must be after start_time")
		return
	}

	value := mergeJSONMap(parseJSONStringMap(existingValueRaw), payload.Value)
	metadata := mergeJSONMap(parseJSONStringMap(existingMetadataRaw), payload.Metadata)
	metadata["entry_mode"] = "manual_edit"

	if _, err := tx.Exec(
		c.Request.Context(),
		`UPDATE "Event"
		 SET type = $2,
		     "startTime" = $3,
		     "endTime" = $4,
		     "valueJson" = $5,
		     "metadataJson" = $6,
		     "updatedAt" = NOW()
		 WHERE id = $1`,
		eventID,
		resolvedType,
		resolvedStart,
		resolvedEnd.UTC(),
		mustMarshalJSON(value),
		mustMarshalJSON(metadata),
	); err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to update event")
		return
	}

	if err := recordAuditLog(
		c.Request.Context(),
		tx,
		baby.HouseholdID,
		user.ID,
		"EVENT_MANUAL_UPDATED",
		"Event",
		&eventID,
		gin.H{
			"baby_id": baby.ID,
			"type":    resolvedType,
		},
	); err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to write audit log")
		return
	}

	if err := tx.Commit(c.Request.Context()); err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to commit transaction")
		return
	}

	durationMin := int(resolvedEnd.UTC().Sub(resolvedStart).Minutes())
	if durationMin < 0 {
		durationMin = 0
	}

	c.JSON(http.StatusOK, gin.H{
		"status":       "UPDATED",
		"event_id":     eventID,
		"type":         resolvedType,
		"start_time":   resolvedStart.Format(time.RFC3339),
		"end_time":     resolvedEnd.UTC().Format(time.RFC3339),
		"duration_min": durationMin,
		"event_state":  "CLOSED",
	})
}

func (a *App) completeManualEvent(c *gin.Context) {
	user, ok := authUserFromContext(c)
	if !ok {
		writeError(c, http.StatusUnauthorized, "Unauthorized")
		return
	}

	eventID := strings.TrimSpace(c.Param("event_id"))
	if eventID == "" {
		writeError(c, http.StatusBadRequest, "event_id is required")
		return
	}

	var payload manualEventCompleteRequest
	if !mustJSON(c, &payload) {
		return
	}

	var eventBabyID string
	err := a.db.QueryRow(
		c.Request.Context(),
		`SELECT "babyId" FROM "Event" WHERE id = $1`,
		eventID,
	).Scan(&eventBabyID)
	if errors.Is(err, pgx.ErrNoRows) {
		writeError(c, http.StatusNotFound, "Event not found")
		return
	}
	if err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to load event")
		return
	}

	baby, statusCode, err := a.getBabyWithAccess(c.Request.Context(), user.ID, eventBabyID, writeRoles)
	if err != nil {
		writeError(c, statusCode, err.Error())
		return
	}

	tx, err := a.db.Begin(c.Request.Context())
	if err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to start transaction")
		return
	}
	defer tx.Rollback(c.Request.Context())

	var eventType string
	var eventStatus string
	var startTime time.Time
	var valueRaw []byte
	var metadataRaw []byte
	err = tx.QueryRow(
		c.Request.Context(),
		`SELECT type, status, "startTime", "valueJson", "metadataJson"
		 FROM "Event"
		 WHERE id = $1 AND "babyId" = $2
		 FOR UPDATE`,
		eventID,
		baby.ID,
	).Scan(&eventType, &eventStatus, &startTime, &valueRaw, &metadataRaw)
	if errors.Is(err, pgx.ErrNoRows) {
		writeError(c, http.StatusNotFound, "Event not found")
		return
	}
	if err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to lock event")
		return
	}
	if eventStatus != "OPEN" {
		c.AbortWithStatusJSON(http.StatusConflict, gin.H{
			"detail":       "event is not open",
			"event_id":     eventID,
			"event_status": eventStatus,
		})
		return
	}

	resolvedEnd := time.Now().UTC()
	if payload.EndTime != nil {
		resolvedEnd = payload.EndTime.UTC()
	}
	if resolvedEnd.Before(startTime.UTC()) {
		writeError(c, http.StatusBadRequest, "end_time must be after start_time")
		return
	}

	value := mergeJSONMap(parseJSONStringMap(valueRaw), payload.Value)
	metadata := mergeJSONMap(parseJSONStringMap(metadataRaw), payload.Metadata)
	metadata["entry_mode"] = "manual_complete"

	commandTag, err := tx.Exec(
		c.Request.Context(),
		`UPDATE "Event"
		 SET "endTime" = $2,
		     "valueJson" = $3,
		     "metadataJson" = $4,
		     status = 'CLOSED',
		     "updatedAt" = NOW()
		 WHERE id = $1 AND status = 'OPEN'`,
		eventID,
		resolvedEnd,
		mustMarshalJSON(value),
		mustMarshalJSON(metadata),
	)
	if err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to complete event")
		return
	}
	if commandTag.RowsAffected() == 0 {
		c.AbortWithStatusJSON(http.StatusConflict, gin.H{
			"detail":   "event completion conflict",
			"event_id": eventID,
		})
		return
	}

	if err := recordAuditLog(
		c.Request.Context(),
		tx,
		baby.HouseholdID,
		user.ID,
		"EVENT_MANUAL_COMPLETED",
		"Event",
		&eventID,
		gin.H{
			"baby_id": baby.ID,
			"type":    eventType,
		},
	); err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to write audit log")
		return
	}

	if err := tx.Commit(c.Request.Context()); err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to commit transaction")
		return
	}

	durationMin := int(resolvedEnd.Sub(startTime.UTC()).Minutes())
	if durationMin < 0 {
		durationMin = 0
	}

	c.JSON(http.StatusOK, gin.H{
		"status":       "COMPLETED",
		"event_id":     eventID,
		"type":         eventType,
		"start_time":   startTime.UTC().Format(time.RFC3339),
		"end_time":     resolvedEnd.Format(time.RFC3339),
		"duration_min": durationMin,
		"event_state":  "CLOSED",
	})
}

func (a *App) cancelManualEvent(c *gin.Context) {
	user, ok := authUserFromContext(c)
	if !ok {
		writeError(c, http.StatusUnauthorized, "Unauthorized")
		return
	}

	eventID := strings.TrimSpace(c.Param("event_id"))
	if eventID == "" {
		writeError(c, http.StatusBadRequest, "event_id is required")
		return
	}

	var payload manualEventCancelRequest
	if !mustJSON(c, &payload) {
		return
	}

	var eventBabyID string
	err := a.db.QueryRow(
		c.Request.Context(),
		`SELECT "babyId" FROM "Event" WHERE id = $1`,
		eventID,
	).Scan(&eventBabyID)
	if errors.Is(err, pgx.ErrNoRows) {
		writeError(c, http.StatusNotFound, "Event not found")
		return
	}
	if err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to load event")
		return
	}

	baby, statusCode, err := a.getBabyWithAccess(c.Request.Context(), user.ID, eventBabyID, writeRoles)
	if err != nil {
		writeError(c, statusCode, err.Error())
		return
	}

	tx, err := a.db.Begin(c.Request.Context())
	if err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to start transaction")
		return
	}
	defer tx.Rollback(c.Request.Context())

	var eventStatus string
	var eventType string
	var metadataRaw []byte
	err = tx.QueryRow(
		c.Request.Context(),
		`SELECT status, type, "metadataJson"
		 FROM "Event"
		 WHERE id = $1 AND "babyId" = $2
		 FOR UPDATE`,
		eventID,
		baby.ID,
	).Scan(&eventStatus, &eventType, &metadataRaw)
	if errors.Is(err, pgx.ErrNoRows) {
		writeError(c, http.StatusNotFound, "Event not found")
		return
	}
	if err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to lock event")
		return
	}
	if eventStatus != "OPEN" {
		c.AbortWithStatusJSON(http.StatusConflict, gin.H{
			"detail":       "event is not open",
			"event_id":     eventID,
			"event_status": eventStatus,
		})
		return
	}

	metadata := parseJSONStringMap(metadataRaw)
	metadata["entry_mode"] = "manual_cancel"
	if reason := strings.TrimSpace(payload.Reason); reason != "" {
		metadata["cancel_reason"] = reason
	}

	if _, err := tx.Exec(
		c.Request.Context(),
		`UPDATE "Event"
		 SET status = 'CANCELED',
		     "metadataJson" = $2,
		     "updatedAt" = NOW()
		 WHERE id = $1`,
		eventID,
		mustMarshalJSON(metadata),
	); err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to cancel event")
		return
	}

	if err := recordAuditLog(
		c.Request.Context(),
		tx,
		baby.HouseholdID,
		user.ID,
		"EVENT_MANUAL_CANCELED",
		"Event",
		&eventID,
		gin.H{
			"baby_id": baby.ID,
			"type":    eventType,
		},
	); err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to write audit log")
		return
	}

	if err := tx.Commit(c.Request.Context()); err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to commit transaction")
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"status":      "CANCELED",
		"event_id":    eventID,
		"type":        eventType,
		"event_state": "CANCELED",
	})
}

func (a *App) listOpenEvents(c *gin.Context) {
	user, ok := authUserFromContext(c)
	if !ok {
		writeError(c, http.StatusUnauthorized, "Unauthorized")
		return
	}

	babyID := strings.TrimSpace(c.Query("baby_id"))
	if babyID == "" {
		writeError(c, http.StatusBadRequest, "baby_id is required")
		return
	}

	baby, statusCode, err := a.getBabyWithAccess(c.Request.Context(), user.ID, babyID, readRoles)
	if err != nil {
		writeError(c, statusCode, err.Error())
		return
	}

	queryType := strings.TrimSpace(c.Query("type"))
	rowsQuery := `SELECT id, type, "startTime", "valueJson", "metadataJson", "createdAt"
		FROM "Event"
		WHERE "babyId" = $1 AND status = 'OPEN'
		ORDER BY "startTime" DESC`
	args := []any{baby.ID}
	if queryType != "" {
		eventType, valid := normalizeEventType(queryType)
		if !valid {
			writeError(c, http.StatusBadRequest, "type is invalid")
			return
		}
		rowsQuery = `SELECT id, type, "startTime", "valueJson", "metadataJson", "createdAt"
			FROM "Event"
			WHERE "babyId" = $1 AND status = 'OPEN' AND type = $2
			ORDER BY "startTime" DESC`
		args = []any{baby.ID, eventType}
	}

	rows, err := a.db.Query(c.Request.Context(), rowsQuery, args...)
	if err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to load open events")
		return
	}
	defer rows.Close()

	events := make([]gin.H, 0)
	for rows.Next() {
		var eventID string
		var eventType string
		var startTime time.Time
		var valueRaw []byte
		var metadataRaw []byte
		var createdAt time.Time
		if err := rows.Scan(&eventID, &eventType, &startTime, &valueRaw, &metadataRaw, &createdAt); err != nil {
			writeError(c, http.StatusInternalServerError, "Failed to parse open events")
			return
		}
		events = append(events, gin.H{
			"event_id":     eventID,
			"type":         eventType,
			"status":       "OPEN",
			"start_time":   startTime.UTC().Format(time.RFC3339),
			"value":        parseJSONStringMap(valueRaw),
			"metadata":     parseJSONStringMap(metadataRaw),
			"created_at":   createdAt.UTC().Format(time.RFC3339),
			"can_complete": true,
			"can_cancel":   true,
		})
	}

	c.JSON(http.StatusOK, gin.H{
		"baby_id":        baby.ID,
		"open_events":    events,
		"open_count":     len(events),
		"event_state":    "OPEN",
		"reference_text": "Open events represent in-progress records awaiting completion.",
	})
}
