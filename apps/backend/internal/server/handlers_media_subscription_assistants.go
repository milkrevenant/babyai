package server

import (
	"context"
	"errors"
	"fmt"
	"log"
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
	subscriptionFormulaGuideURL       = "https://www.cdc.gov/infant-toddler-nutrition/formula-feeding/how-much-and-how-often.html"
	subscriptionBreastfeedingGuideURL = "https://www.cdc.gov/breastfeeding/php/guidelines-recommendations/index.html"
)

const (
	subscriptionFeatureAI         subscriptionFeature = "ai"
	subscriptionFeaturePhotoShare subscriptionFeature = "photo_share"
)

func normalizeSubscriptionPlan(raw string) string {
	return strings.ToUpper(strings.TrimSpace(raw))
}

func isKnownSubscriptionPlan(plan string) bool {
	switch normalizeSubscriptionPlan(plan) {
	case "AI_ONLY", "AI_PHOTO":
		return true
	default:
		return false
	}
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
		return []string{"AI_ONLY", "AI_PHOTO"}
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
		return normalizedPlan == "AI_ONLY" || normalizedPlan == "AI_PHOTO"
	default:
		return false
	}
}

func (a *App) localForcedSubscription() (string, string, bool) {
	if !strings.EqualFold(strings.TrimSpace(a.cfg.AppEnv), "local") {
		return "", "", false
	}
	plan := normalizeSubscriptionPlan(a.cfg.LocalForceSubscriptionPlan)
	if !isKnownSubscriptionPlan(plan) {
		return "", "", false
	}
	return plan, "ACTIVE", true
}

func (a *App) getLatestSubscription(
	ctx context.Context,
	householdID string,
) (string, string, error) {
	if forcedPlan, forcedStatus, ok := a.localForcedSubscription(); ok {
		return forcedPlan, forcedStatus, nil
	}

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
		return "Photo sharing is included in AI plan. Choose AI_ONLY or AI_PHOTO."
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
	if !a.cfg.EnablePhotoPlaceholderUpload {
		writeError(c, http.StatusNotImplemented, "Photo upload placeholder is not enabled in this environment")
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
	if !a.cfg.EnablePhotoPlaceholderUpload {
		writeError(c, http.StatusNotImplemented, "Photo upload placeholder is not enabled in this environment")
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

	plan, statusValue, err := a.getLatestSubscription(c.Request.Context(), householdID)
	if errors.Is(err, pgx.ErrNoRows) || (strings.TrimSpace(plan) == "" && strings.TrimSpace(statusValue) == "") {
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
		"AI_ONLY":  {},
		"AI_PHOTO": {},
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

	enrichedChildren := 0

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

	if count, enrichErr := a.refreshSubscriptionCareMetadata(
		c.Request.Context(),
		tx,
		user.ID,
		payload.HouseholdID,
	); enrichErr != nil {
		log.Printf("failed to refresh subscription care metadata user_id=%s household_id=%s err=%v", user.ID, payload.HouseholdID, enrichErr)
	} else {
		enrichedChildren = count
	}

	if err := recordAuditLog(
		c.Request.Context(),
		tx,
		payload.HouseholdID,
		user.ID,
		"SUBSCRIPTION_CHECKOUT_STARTED",
		"Subscription",
		&subscriptionID,
		gin.H{
			"plan":                    payload.Plan,
			"care_meta_enriched_baby": enrichedChildren,
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
		"status":                  "pending_payment",
		"plan":                    payload.Plan,
		"household_id":            payload.HouseholdID,
		"care_meta_enriched_baby": enrichedChildren,
	})
}

func (a *App) refreshSubscriptionCareMetadata(
	ctx context.Context,
	q dbQuerier,
	userID, householdID string,
) (int, error) {
	persona, err := loadPersonaSettingsWithQuerier(ctx, q, userID)
	if err != nil {
		return 0, err
	}
	rows, err := q.Query(
		ctx,
		`SELECT id FROM "Baby" WHERE "householdId" = $1`,
		householdID,
	)
	if err != nil {
		return 0, err
	}
	defer rows.Close()

	nowUTC := time.Now().UTC()
	updatedCount := 0
	for rows.Next() {
		var babyID string
		if err := rows.Scan(&babyID); err != nil {
			return 0, err
		}
		babySettings := readBabySettings(persona, babyID)
		if babySettings == nil {
			babySettings = map[string]any{}
		}
		metadata, err := a.buildSubscriptionCareMetadata(ctx, q, babyID, babySettings, nowUTC)
		if err != nil {
			return 0, err
		}
		babySettings["subscription_care_metadata"] = metadata
		writeBabySettings(persona, babyID, babySettings)
		updatedCount++
	}
	if err := rows.Err(); err != nil {
		return 0, err
	}
	if updatedCount == 0 {
		return 0, nil
	}
	if err := upsertPersonaSettingsWithQuerier(ctx, q, userID, persona); err != nil {
		return 0, err
	}
	return updatedCount, nil
}

func (a *App) buildSubscriptionCareMetadata(
	ctx context.Context,
	q dbQuerier,
	babyID string,
	babySettings map[string]any,
	nowUTC time.Time,
) (map[string]any, error) {
	feedingMethod := normalizeFeedingMethod(toString(babySettings["feeding_method"]))
	if feedingMethod == "" {
		feedingMethod = "mixed"
	}
	metadata := map[string]any{
		"version":          "v1",
		"trigger":          "subscription_checkout",
		"generated_at_utc": nowUTC.Format(time.RFC3339),
		"feeding_method":   feedingMethod,
		"official_guides": []string{
			subscriptionFormulaGuideURL,
			subscriptionBreastfeedingGuideURL,
		},
	}

	if formulaMeta := buildFormulaPreanalysisMetadata(babySettings, feedingMethod); len(formulaMeta) > 0 {
		metadata["formula_preanalysis"] = formulaMeta
	}
	if feedingMethod == "breastmilk" || feedingMethod == "mixed" {
		breastfeedMeta, err := a.buildBreastfeedPreanalysisMetadata(ctx, q, babyID, nowUTC.AddDate(0, 0, -14))
		if err != nil {
			return nil, err
		}
		metadata["breastfeed_preanalysis"] = breastfeedMeta
	}

	return metadata, nil
}

func buildFormulaPreanalysisMetadata(babySettings map[string]any, feedingMethod string) map[string]any {
	brand := strings.TrimSpace(toString(babySettings["formula_brand"]))
	product := strings.TrimSpace(toString(babySettings["formula_product"]))
	rawTypeInput := strings.TrimSpace(toString(babySettings["formula_type"]))
	rawType := normalizeFormulaType(rawTypeInput)
	containsStarch := mapBoolPointer(babySettings["formula_contains_starch"])
	if brand == "" && product == "" && rawTypeInput == "" && containsStarch == nil {
		return map[string]any{}
	}
	inferenceSource := "profile_input"
	inferenceReason := ""
	if rawType == "" {
		if inferredType, reason := inferFormulaTypeFromProductName(brand, product); inferredType != "" {
			rawType = inferredType
			inferenceSource = "product_name_keyword"
			inferenceReason = reason
		}
	}
	if rawType == "" {
		rawType = "standard"
		inferenceSource = "default_standard"
	}

	displayNameParts := make([]string, 0, 2)
	if brand != "" {
		displayNameParts = append(displayNameParts, brand)
	}
	if product != "" {
		displayNameParts = append(displayNameParts, product)
	}
	displayName := strings.TrimSpace(strings.Join(displayNameParts, " "))
	if displayName == "" && feedingMethod == "breastmilk" {
		return map[string]any{}
	}

	if containsStarch == nil && rawType == "thickened" {
		defaultTrue := true
		containsStarch = &defaultTrue
	}
	catalogMatch := map[string]any{}
	for _, item := range formulaCatalog() {
		if normalizeFormulaType(toString(item["code"])) != rawType {
			continue
		}
		catalogMatch = map[string]any{}
		for key, value := range item {
			catalogMatch[key] = value
		}
		break
	}
	result := map[string]any{
		"display_name":            displayName,
		"brand":                   brand,
		"product":                 product,
		"normalized_formula_type": rawType,
		"inference_source":        inferenceSource,
		"catalog_source":          "curated_internal",
		"official_guide":          subscriptionFormulaGuideURL,
	}
	if inferenceReason != "" {
		result["inference_reason"] = inferenceReason
	}
	if containsStarch != nil {
		result["contains_starch"] = *containsStarch
	}
	if len(catalogMatch) > 0 {
		result["catalog_match"] = catalogMatch
	}
	return result
}

func inferFormulaTypeFromProductName(brand, product string) (string, string) {
	normalized := strings.ToLower(strings.TrimSpace(strings.Join([]string{brand, product}, " ")))
	if normalized == "" {
		return "", ""
	}
	if containsAnyKeyword(normalized, []string{"thickened", "ar", "역류", "걸쭉", "전분"}) {
		return "thickened", "matched thickened/ar keyword"
	}
	if containsAnyKeyword(normalized, []string{"hydrolyzed", "hypoallergenic", "ha", "부분가수분해", "가수분해"}) {
		return "hydrolyzed", "matched hydrolyzed keyword"
	}
	if containsAnyKeyword(normalized, []string{"soy", "대두"}) {
		return "soy", "matched soy keyword"
	}
	if containsAnyKeyword(normalized, []string{"goat", "산양"}) {
		return "goat", "matched goat keyword"
	}
	if containsAnyKeyword(normalized, []string{"sensitive", "센서티브", "special"}) {
		return "specialty", "matched sensitive/special keyword"
	}
	return "", ""
}

func (a *App) buildBreastfeedPreanalysisMetadata(
	ctx context.Context,
	q dbQuerier,
	babyID string,
	sinceUTC time.Time,
) (map[string]any, error) {
	query := `SELECT "startTime", "endTime"
	          FROM "Event"
	          WHERE "babyId" = $1
	            AND type = 'BREASTFEED'
	            AND "startTime" >= $2
	            AND state = 'CLOSED'
	          ORDER BY "startTime" ASC`
	rows, err := q.Query(ctx, query, babyID, sinceUTC)
	if err != nil && isUndefinedSchemaReferenceError(err) {
		rows, err = q.Query(
			ctx,
			`SELECT "startTime", "endTime"
			 FROM "Event"
			 WHERE "babyId" = $1
			   AND type = 'BREASTFEED'
			   AND "startTime" >= $2
			 ORDER BY "startTime" ASC`,
			babyID,
			sinceUTC,
		)
	}
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	startTimes := make([]time.Time, 0, 32)
	totalDurationMin := 0
	durationCount := 0
	for rows.Next() {
		var startTime time.Time
		var endTime *time.Time
		if err := rows.Scan(&startTime, &endTime); err != nil {
			return nil, err
		}
		startUTC := startTime.UTC()
		startTimes = append(startTimes, startUTC)
		if endTime != nil {
			endUTC := endTime.UTC()
			if endUTC.After(startUTC) {
				totalDurationMin += int(endUTC.Sub(startUTC).Minutes() + 0.5)
				durationCount++
			}
		}
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}

	var lastRecordedAt *time.Time
	sessionCount := len(startTimes)
	if sessionCount > 0 {
		last := startTimes[sessionCount-1]
		lastRecordedAt = &last
	}
	intervalTotalMin := 0
	intervalCount := 0
	for idx := 1; idx < len(startTimes); idx++ {
		diffMin := int(startTimes[idx].Sub(startTimes[idx-1]).Minutes() + 0.5)
		if diffMin <= 0 {
			continue
		}
		intervalTotalMin += diffMin
		intervalCount++
	}

	result := map[string]any{
		"window_days":          14,
		"session_count_14d":    sessionCount,
		"last_recorded_at_utc": formatNullableTimeRFC3339(lastRecordedAt),
		"source":               "event_history_14d",
		"official_guide":       subscriptionBreastfeedingGuideURL,
	}
	if intervalCount > 0 {
		result["average_interval_min_14d"] = int(float64(intervalTotalMin)/float64(intervalCount) + 0.5)
	} else {
		result["average_interval_min_14d"] = nil
	}
	if durationCount > 0 {
		result["average_duration_min_14d"] = int(float64(totalDurationMin)/float64(durationCount) + 0.5)
	} else {
		result["average_duration_min_14d"] = nil
	}
	return result, nil
}

func (a *App) assistantDialog(ctx context.Context, babyID, tone, intent string) (string, string, error) {
	switch intent {
	case "GetLastPooTime":
		var lastPoo time.Time
		err := a.db.QueryRow(
			ctx,
			`SELECT "startTime" FROM "Event"
				 WHERE "babyId" = $1 AND type = 'POO' AND state = 'CLOSED'
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
				   AND state = 'CLOSED'
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
				 WHERE "babyId" = $1 AND "startTime" >= $2 AND "startTime" < $3 AND state = 'CLOSED'`,
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
