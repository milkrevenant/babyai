package server

import (
	"context"
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

type subscriptionFeature string

const (
	subscriptionFeatureAI         subscriptionFeature = "ai"
	subscriptionFeaturePhotoShare subscriptionFeature = "photo_share"
)

func normalizeSubscriptionPlan(raw string) string {
	return strings.ToUpper(strings.TrimSpace(raw))
}

func normalizeSubscriptionStatus(raw string) string {
	return strings.ToUpper(strings.TrimSpace(raw))
}

func isEnabledSubscriptionStatus(raw string) bool {
	switch normalizeSubscriptionStatus(raw) {
	case "ACTIVE", "TRIALING":
		return true
	default:
		return false
	}
}

func requiredPlansForFeature(feature subscriptionFeature) []string {
	switch feature {
	case subscriptionFeatureAI:
		return []string{"AI_ONLY", "AI_PHOTO"}
	case subscriptionFeaturePhotoShare:
		return []string{"PHOTO_SHARE", "AI_PHOTO"}
	default:
		return nil
	}
}

func planSupportsFeature(plan string, feature subscriptionFeature) bool {
	normalizedPlan := normalizeSubscriptionPlan(plan)
	switch feature {
	case subscriptionFeatureAI:
		return normalizedPlan == "AI_ONLY" || normalizedPlan == "AI_PHOTO"
	case subscriptionFeaturePhotoShare:
		return normalizedPlan == "PHOTO_SHARE" || normalizedPlan == "AI_PHOTO"
	default:
		return false
	}
}

func (a *App) getLatestSubscription(
	ctx context.Context,
	householdID string,
) (string, string, error) {
	var plan string
	var statusValue string
	err := a.db.QueryRow(
		ctx,
		`SELECT plan::text, status::text
		 FROM "Subscription"
		 WHERE "householdId" = $1
		 ORDER BY "createdAt" DESC
		 LIMIT 1`,
		strings.TrimSpace(householdID),
	).Scan(&plan, &statusValue)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", "", nil
	}
	if err != nil {
		return "", "", err
	}
	return normalizeSubscriptionPlan(plan), normalizeSubscriptionStatus(statusValue), nil
}

func (a *App) hasSubscriptionFeature(
	ctx context.Context,
	householdID string,
	feature subscriptionFeature,
) (bool, string, string, error) {
	plan, statusValue, err := a.getLatestSubscription(ctx, householdID)
	if err != nil {
		return false, "", "", err
	}
	if !isEnabledSubscriptionStatus(statusValue) {
		return false, plan, statusValue, nil
	}
	if !planSupportsFeature(plan, feature) {
		return false, plan, statusValue, nil
	}
	return true, plan, statusValue, nil
}

func subscriptionFeatureDetail(feature subscriptionFeature) string {
	switch feature {
	case subscriptionFeatureAI:
		return "AI subscription required. Choose AI_ONLY or AI_PHOTO."
	case subscriptionFeaturePhotoShare:
		return "Photo subscription required. Choose PHOTO_SHARE or AI_PHOTO."
	default:
		return "Subscription required."
	}
}

func maybeLowerOrNil(raw string) any {
	trimmed := strings.TrimSpace(raw)
	if trimmed == "" {
		return nil
	}
	return strings.ToLower(trimmed)
}

func maybeUpperOrNil(raw string) any {
	trimmed := strings.TrimSpace(raw)
	if trimmed == "" {
		return nil
	}
	return strings.ToUpper(trimmed)
}

func (a *App) writeSubscriptionRequired(
	c *gin.Context,
	feature subscriptionFeature,
	currentPlan string,
	currentStatus string,
) {
	c.AbortWithStatusJSON(http.StatusPaymentRequired, gin.H{
		"detail":         subscriptionFeatureDetail(feature),
		"feature":        string(feature),
		"required_plans": requiredPlansForFeature(feature),
		"current_plan":   maybeUpperOrNil(currentPlan),
		"current_status": maybeLowerOrNil(currentStatus),
	})
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
	hasFeature, plan, statusValue, err := a.hasSubscriptionFeature(
		c.Request.Context(),
		householdID,
		subscriptionFeaturePhotoShare,
	)
	if err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to load subscription")
		return
	}
	if !hasFeature {
		a.writeSubscriptionRequired(c, subscriptionFeaturePhotoShare, plan, statusValue)
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
	hasFeature, plan, statusValue, err := a.hasSubscriptionFeature(
		c.Request.Context(),
		householdID,
		subscriptionFeaturePhotoShare,
	)
	if err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to load subscription")
		return
	}
	if !hasFeature {
		a.writeSubscriptionRequired(c, subscriptionFeaturePhotoShare, plan, statusValue)
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
		`SELECT plan::text, status::text
		 FROM "Subscription"
		 WHERE "householdId" = $1
		 ORDER BY "createdAt" DESC
		 LIMIT 1`,
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
		"plan":         normalizeSubscriptionPlan(plan),
		"status":       strings.ToLower(normalizeSubscriptionStatus(statusValue)),
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
		nowUTC := time.Now().UTC()
		rows, err := a.db.Query(
			ctx,
			`SELECT "startTime" FROM "Event"
			 WHERE "babyId" = $1
			   AND type IN ('FORMULA', 'BREASTFEED')
			   AND "startTime" <= $2
			 ORDER BY "startTime" DESC LIMIT 10`,
			babyID,
			nowUTC,
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

		result := calculateNextFeedingETA(feedingTimes, nowUTC)
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
	hasFeature, plan, statusValue, err := a.hasSubscriptionFeature(
		c.Request.Context(),
		baby.HouseholdID,
		subscriptionFeatureAI,
	)
	if err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to load subscription")
		return
	}
	if !hasFeature {
		a.writeSubscriptionRequired(c, subscriptionFeatureAI, plan, statusValue)
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
	hasFeature, plan, statusValue, err := a.hasSubscriptionFeature(
		c.Request.Context(),
		baby.HouseholdID,
		subscriptionFeatureAI,
	)
	if err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to load subscription")
		return
	}
	if !hasFeature {
		a.writeSubscriptionRequired(c, subscriptionFeatureAI, plan, statusValue)
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
