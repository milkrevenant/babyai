package server

import (
	"context"
	"errors"
	"fmt"
	"math"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
)

type resolvedBabyProfile struct {
	BabyID                string
	HouseholdID           string
	Name                  string
	BirthDate             time.Time
	AgeDays               int
	Sex                   string
	ProfilePhotoURL       string
	WeightKg              *float64
	FeedingMethod         string
	FormulaBrand          string
	FormulaProduct        string
	FormulaType           string
	FormulaContainsStarch *bool
}

type feedingRecommendation struct {
	RecommendedFormulaDailyML   *int
	RecommendedFormulaPerFeedML *int
	RecommendedIntervalMin      int
	RecommendedNextFeedingTime  *time.Time
	RecommendedNextFeedingInMin *int
	ReferenceText               string
	Note                        string
}

func (a *App) getBabyProfile(c *gin.Context) {
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

	profile, statusCode, err := a.resolveBabyProfile(c.Request.Context(), user.ID, babyID, readRoles)
	if err != nil {
		writeError(c, statusCode, err.Error())
		return
	}

	lastFeeding, err := a.latestFeedingTime(c.Request.Context(), profile.BabyID)
	if err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to load latest feeding event")
		return
	}
	recommendation := calculateFeedingRecommendation(profile, lastFeeding, time.Now().UTC())

	c.JSON(http.StatusOK, profileResponse(profile, recommendation))
}

func (a *App) upsertBabyProfile(c *gin.Context) {
	user, ok := authUserFromContext(c)
	if !ok {
		writeError(c, http.StatusUnauthorized, "Unauthorized")
		return
	}

	var payload babyProfileUpsertRequest
	if !mustJSON(c, &payload) {
		return
	}

	payload.BabyID = strings.TrimSpace(payload.BabyID)
	if payload.BabyID == "" {
		writeError(c, http.StatusBadRequest, "baby_id is required")
		return
	}

	baby, statusCode, err := a.getBabyWithAccess(c.Request.Context(), user.ID, payload.BabyID, writeRoles)
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

	var currentName string
	var currentBirthDate time.Time
	var currentSex *string
	err = tx.QueryRow(
		c.Request.Context(),
		`SELECT name, "birthDate", sex FROM "Baby" WHERE id = $1`,
		baby.ID,
	).Scan(&currentName, &currentBirthDate, &currentSex)
	if errors.Is(err, pgx.ErrNoRows) {
		writeError(c, http.StatusNotFound, "Baby not found")
		return
	}
	if err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to load baby profile")
		return
	}

	nextName := currentName
	if candidate := strings.TrimSpace(payload.BabyName); candidate != "" {
		nextName = candidate
	}

	nextBirthDate := currentBirthDate.UTC()
	if birthDateRaw := strings.TrimSpace(payload.BabyBirthDate); birthDateRaw != "" {
		parsedBirthDate, parseErr := parseDate(birthDateRaw)
		if parseErr != nil {
			writeError(c, http.StatusBadRequest, "baby_birth_date must be YYYY-MM-DD")
			return
		}
		nextBirthDate = parsedBirthDate
	}

	var nextSex *string
	if currentSex != nil && strings.TrimSpace(*currentSex) != "" {
		normalized := normalizeBabySex(*currentSex)
		if normalized != "" {
			nextSex = &normalized
		}
	}
	if sexRaw := strings.TrimSpace(payload.BabySex); sexRaw != "" {
		normalized := normalizeBabySex(sexRaw)
		if normalized == "" {
			writeError(c, http.StatusBadRequest, "baby_sex must be one of: male, female, other, unknown")
			return
		}
		nextSex = &normalized
	}

	if _, err := tx.Exec(
		c.Request.Context(),
		`UPDATE "Baby" SET name = $2, "birthDate" = $3, sex = $4 WHERE id = $1`,
		baby.ID,
		nextName,
		nextBirthDate,
		nextSex,
	); err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to update baby profile")
		return
	}

	persona, err := loadPersonaSettingsWithQuerier(c.Request.Context(), tx, user.ID)
	if err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to load settings")
		return
	}

	babySettings := readBabySettings(persona, baby.ID)
	if payload.BabyWeightKg != nil {
		clampedWeight := clampWeightKg(*payload.BabyWeightKg)
		babySettings["weight_kg"] = roundToOneDecimal(clampedWeight)
	}
	if feedingMethodRaw := strings.TrimSpace(payload.FeedingMethod); feedingMethodRaw != "" {
		normalizedMethod := normalizeFeedingMethod(feedingMethodRaw)
		if normalizedMethod == "" {
			writeError(c, http.StatusBadRequest, "feeding_method must be one of: formula, breastmilk, mixed")
			return
		}
		babySettings["feeding_method"] = normalizedMethod
	}
	if brandRaw := strings.TrimSpace(payload.FormulaBrand); brandRaw != "" {
		babySettings["formula_brand"] = brandRaw
	}
	if productRaw := strings.TrimSpace(payload.FormulaProduct); productRaw != "" {
		babySettings["formula_product"] = productRaw
	}
	if typeRaw := strings.TrimSpace(payload.FormulaType); typeRaw != "" {
		normalizedType := normalizeFormulaType(typeRaw)
		if normalizedType == "" {
			writeError(c, http.StatusBadRequest, "formula_type is invalid")
			return
		}
		babySettings["formula_type"] = normalizedType
	}
	if payload.FormulaContainsStarch != nil {
		babySettings["formula_contains_starch"] = *payload.FormulaContainsStarch
	}
	babySettings["updated_at"] = time.Now().UTC().Format(time.RFC3339)
	writeBabySettings(persona, baby.ID, babySettings)

	if err := upsertPersonaSettingsWithQuerier(c.Request.Context(), tx, user.ID, persona); err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to save baby settings")
		return
	}

	if err := recordAuditLog(
		c.Request.Context(),
		tx,
		baby.HouseholdID,
		user.ID,
		"BABY_PROFILE_UPDATED",
		"Baby",
		&baby.ID,
		gin.H{"baby_id": baby.ID},
	); err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to write audit log")
		return
	}

	if err := tx.Commit(c.Request.Context()); err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to commit transaction")
		return
	}

	profile, statusCode, err := a.resolveBabyProfile(c.Request.Context(), user.ID, baby.ID, readRoles)
	if err != nil {
		writeError(c, statusCode, err.Error())
		return
	}
	lastFeeding, err := a.latestFeedingTime(c.Request.Context(), profile.BabyID)
	if err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to load latest feeding event")
		return
	}
	recommendation := calculateFeedingRecommendation(profile, lastFeeding, time.Now().UTC())
	c.JSON(http.StatusOK, profileResponse(profile, recommendation))
}

func (a *App) resolveBabyProfile(
	ctx context.Context,
	userID, babyID string,
	allowed map[string]struct{},
) (resolvedBabyProfile, int, error) {
	baby, statusCode, err := a.getBabyWithAccess(ctx, userID, babyID, allowed)
	if err != nil {
		return resolvedBabyProfile{}, statusCode, err
	}

	var name string
	var birthDate time.Time
	var sex *string
	err = a.db.QueryRow(
		ctx,
		`SELECT name, "birthDate", sex FROM "Baby" WHERE id = $1`,
		baby.ID,
	).Scan(&name, &birthDate, &sex)
	if errors.Is(err, pgx.ErrNoRows) {
		return resolvedBabyProfile{}, http.StatusNotFound, errors.New("Baby not found")
	}
	if err != nil {
		return resolvedBabyProfile{}, http.StatusInternalServerError, err
	}

	persona, err := loadPersonaSettingsWithQuerier(ctx, a.db, userID)
	if err != nil {
		return resolvedBabyProfile{}, http.StatusInternalServerError, err
	}
	babySettings := readBabySettings(persona, baby.ID)
	profilePhotoURL := strings.TrimSpace(toString(babySettings["profile_photo_url"]))
	profilePhotoURL = coalesceNonEmpty(profilePhotoURL, strings.TrimSpace(toString(babySettings["baby_profile_photo_url"])))
	profilePhotoURL = coalesceNonEmpty(profilePhotoURL, strings.TrimSpace(toString(babySettings["avatar_url"])))
	profilePhotoURL = coalesceNonEmpty(profilePhotoURL, strings.TrimSpace(toString(babySettings["photo_url"])))
	profilePhotoURL = coalesceNonEmpty(profilePhotoURL, strings.TrimSpace(toString(babySettings["image_url"])))
	profilePhotoURL = coalesceNonEmpty(profilePhotoURL, strings.TrimSpace(toString(babySettings["picture"])))

	profile := resolvedBabyProfile{
		BabyID:          baby.ID,
		HouseholdID:     baby.HouseholdID,
		Name:            name,
		BirthDate:       birthDate.UTC(),
		AgeDays:         ageDaysFromBirth(birthDate.UTC(), time.Now().UTC()),
		Sex:             "unknown",
		ProfilePhotoURL: profilePhotoURL,
		WeightKg:        mapFloatPointer(babySettings["weight_kg"]),
		FeedingMethod: coalesceNonEmpty(
			normalizeFeedingMethod(toString(babySettings["feeding_method"])),
			"mixed",
		),
		FormulaBrand:          strings.TrimSpace(toString(babySettings["formula_brand"])),
		FormulaProduct:        strings.TrimSpace(toString(babySettings["formula_product"])),
		FormulaType:           coalesceNonEmpty(normalizeFormulaType(toString(babySettings["formula_type"])), "standard"),
		FormulaContainsStarch: mapBoolPointer(babySettings["formula_contains_starch"]),
	}

	if sex != nil {
		if normalized := normalizeBabySex(*sex); normalized != "" {
			profile.Sex = normalized
		}
	}

	return profile, http.StatusOK, nil
}

func (a *App) latestFeedingTime(ctx context.Context, babyID string) (*time.Time, error) {
	var latest time.Time
	err := a.db.QueryRow(
		ctx,
		`SELECT "startTime" FROM "Event"
		 WHERE "babyId" = $1
		   AND type IN ('FORMULA', 'BREASTFEED')
		   AND state = 'CLOSED'
		 ORDER BY "startTime" DESC LIMIT 1`,
		babyID,
	).Scan(&latest)
	if err != nil && isUndefinedSchemaReferenceError(err) {
		err = a.db.QueryRow(
			ctx,
			`SELECT "startTime" FROM "Event"
			 WHERE "babyId" = $1
			   AND type IN ('FORMULA', 'BREASTFEED')
			 ORDER BY "startTime" DESC LIMIT 1`,
			babyID,
		).Scan(&latest)
	}
	if err != nil && isUndefinedSchemaReferenceError(err) {
		// Legacy/local schemas may not yet have aligned Event columns.
		// Return no feeding history instead of failing profile/landing APIs.
		return nil, nil
	}
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	latestUTC := latest.UTC()
	return &latestUTC, nil
}

func isUndefinedSchemaReferenceError(err error) bool {
	var pgErr *pgconn.PgError
	if !errors.As(err, &pgErr) {
		return false
	}
	return pgErr.Code == "42703" || pgErr.Code == "42P01"
}

func calculateFeedingRecommendation(
	profile resolvedBabyProfile,
	lastFeedingTime *time.Time,
	now time.Time,
) feedingRecommendation {
	normalizedNow := now.UTC()
	weightKg := profile.WeightKg
	if weightKg == nil {
		defaultWeight := fallbackWeightKg(profile.AgeDays)
		weightKg = &defaultWeight
	}

	mlPerKgPerDay := baselineMLPerKgPerDay(profile.AgeDays)
	intervalMin := baselineFeedingInterval(profile.AgeDays, profile.FeedingMethod)

	methodRatio := 1.0
	switch profile.FeedingMethod {
	case "formula":
		methodRatio = 1.0
	case "mixed":
		methodRatio = 0.55
	case "breastmilk":
		methodRatio = 0.0
	}

	note := "Profile-based estimate. Confirm with your pediatric clinician."
	if profile.FormulaContainsStarch != nil && *profile.FormulaContainsStarch {
		note = "Starch/thickened formula does not automatically mean longer feeding intervals. Keep clinician guidance first."
	}

	var dailyFormulaMLPtr *int
	var perFeedMLPtr *int
	if methodRatio > 0 && weightKg != nil {
		dailyFormulaML := int(math.Round((*weightKg) * float64(mlPerKgPerDay) * methodRatio))
		if dailyFormulaML < 0 {
			dailyFormulaML = 0
		}
		dailyFormulaMLPtr = &dailyFormulaML

		feedsPerDay := float64(24*60) / float64(intervalMin)
		if feedsPerDay < 1 {
			feedsPerDay = 1
		}
		perFeed := int(math.Round(float64(dailyFormulaML) / feedsPerDay))
		perFeed = clampInt(perFeed, 30, maxPerFeedByAge(profile.AgeDays))
		perFeed = roundToNearest5(perFeed)
		perFeedMLPtr = &perFeed
	}

	var nextFeedingTime *time.Time
	var nextFeedingInMin *int
	if lastFeedingTime != nil {
		next := lastFeedingTime.UTC().Add(time.Duration(intervalMin) * time.Minute)
		nextFeedingTime = &next
		inMin := int(next.Sub(normalizedNow).Minutes())
		if inMin < 0 {
			inMin = 0
		}
		nextFeedingInMin = &inMin
	}

	referenceText := fmt.Sprintf(
		"Approximate plan using age_days=%d, feeding_method=%s, weight_kg=%s.",
		profile.AgeDays,
		profile.FeedingMethod,
		formatWeightForReference(weightKg),
	)

	return feedingRecommendation{
		RecommendedFormulaDailyML:   dailyFormulaMLPtr,
		RecommendedFormulaPerFeedML: perFeedMLPtr,
		RecommendedIntervalMin:      intervalMin,
		RecommendedNextFeedingTime:  nextFeedingTime,
		RecommendedNextFeedingInMin: nextFeedingInMin,
		ReferenceText:               referenceText,
		Note:                        note,
	}
}

func profileResponse(profile resolvedBabyProfile, recommendation feedingRecommendation) gin.H {
	return gin.H{
		"baby_id":                         profile.BabyID,
		"baby_name":                       profile.Name,
		"profile_photo_url":               profile.ProfilePhotoURL,
		"baby_profile_photo_url":          profile.ProfilePhotoURL,
		"birth_date":                      profile.BirthDate.Format("2006-01-02"),
		"age_days":                        profile.AgeDays,
		"sex":                             profile.Sex,
		"weight_kg":                       profile.WeightKg,
		"feeding_method":                  profile.FeedingMethod,
		"formula_brand":                   profile.FormulaBrand,
		"formula_product":                 profile.FormulaProduct,
		"formula_type":                    profile.FormulaType,
		"formula_contains_starch":         profile.FormulaContainsStarch,
		"formula_display_name":            formulaDisplayName(profile),
		"recommended_formula_daily_ml":    recommendation.RecommendedFormulaDailyML,
		"recommended_formula_per_feed_ml": recommendation.RecommendedFormulaPerFeedML,
		"recommended_feed_interval_min":   recommendation.RecommendedIntervalMin,
		"recommended_next_feeding_time":   formatNullableTimeRFC3339(recommendation.RecommendedNextFeedingTime),
		"recommended_next_feeding_in_min": recommendation.RecommendedNextFeedingInMin,
		"recommendation_reference_text":   recommendation.ReferenceText,
		"recommendation_note":             recommendation.Note,
		"formula_catalog":                 formulaCatalog(),
		"formula_catalog_source":          "curated_internal",
	}
}

func formulaDisplayName(profile resolvedBabyProfile) string {
	parts := make([]string, 0, 3)
	if profile.FormulaBrand != "" {
		parts = append(parts, profile.FormulaBrand)
	}
	if profile.FormulaProduct != "" {
		parts = append(parts, profile.FormulaProduct)
	}
	if profile.FormulaType != "" {
		parts = append(parts, profile.FormulaType)
	}
	if len(parts) == 0 {
		return ""
	}
	return strings.Join(parts, " / ")
}

func formulaCatalog() []gin.H {
	return []gin.H{
		{
			"code":             "standard",
			"label":            "Standard",
			"contains_starch":  false,
			"default_interval": "3-4h",
		},
		{
			"code":             "hydrolyzed",
			"label":            "Hydrolyzed",
			"contains_starch":  false,
			"default_interval": "2-3h",
		},
		{
			"code":             "thickened",
			"label":            "Thickened (AR)",
			"contains_starch":  true,
			"default_interval": "2-4h",
		},
		{
			"code":             "soy",
			"label":            "Soy",
			"contains_starch":  false,
			"default_interval": "3-4h",
		},
		{
			"code":             "goat",
			"label":            "Goat milk based",
			"contains_starch":  false,
			"default_interval": "3-4h",
		},
		{
			"code":             "specialty",
			"label":            "Specialty",
			"contains_starch":  false,
			"default_interval": "Clinician guidance",
		},
	}
}

func normalizeBabySex(raw string) string {
	value := strings.ToLower(strings.TrimSpace(raw))
	switch value {
	case "male", "m", "boy":
		return "male"
	case "female", "f", "girl":
		return "female"
	case "other", "nonbinary", "non-binary":
		return "other"
	case "unknown", "":
		return "unknown"
	default:
		return ""
	}
}

func normalizeFeedingMethod(raw string) string {
	value := strings.ToLower(strings.TrimSpace(raw))
	switch value {
	case "formula", "formula_only":
		return "formula"
	case "breastmilk", "breastfeed", "breastfeeding":
		return "breastmilk"
	case "mixed", "combo", "mixed_feeding":
		return "mixed"
	default:
		return ""
	}
}

func normalizeFormulaType(raw string) string {
	value := strings.ToLower(strings.TrimSpace(raw))
	switch value {
	case "", "standard":
		return "standard"
	case "hydrolyzed", "hypoallergenic":
		return "hydrolyzed"
	case "thickened", "ar", "starch":
		return "thickened"
	case "soy":
		return "soy"
	case "goat", "goat_milk":
		return "goat"
	case "specialty", "medical", "preterm", "premature":
		return "specialty"
	default:
		if len(value) <= 40 {
			return value
		}
		return ""
	}
}

func ageDaysFromBirth(birthDate, now time.Time) int {
	if birthDate.IsZero() {
		return 0
	}
	days := int(now.UTC().Sub(startOfUTCDay(birthDate.UTC())).Hours() / 24)
	if days < 0 {
		return 0
	}
	return days
}

func fallbackWeightKg(ageDays int) float64 {
	switch {
	case ageDays <= 30:
		return 4.0
	case ageDays <= 90:
		return 5.5
	case ageDays <= 180:
		return 7.0
	case ageDays <= 365:
		return 8.5
	default:
		return 10.0
	}
}

func baselineMLPerKgPerDay(ageDays int) int {
	switch {
	case ageDays <= 30:
		return 150
	case ageDays <= 90:
		return 135
	case ageDays <= 180:
		return 120
	case ageDays <= 365:
		return 105
	default:
		return 90
	}
}

func baselineFeedingInterval(ageDays int, feedingMethod string) int {
	method := normalizeFeedingMethod(feedingMethod)
	if method == "breastmilk" {
		if ageDays <= 60 {
			return 150
		}
		return 180
	}
	if method == "mixed" {
		if ageDays <= 60 {
			return 180
		}
		return 210
	}
	if ageDays <= 30 {
		return 180
	}
	if ageDays <= 180 {
		return 210
	}
	return 240
}

func maxPerFeedByAge(ageDays int) int {
	switch {
	case ageDays <= 30:
		return 90
	case ageDays <= 90:
		return 150
	case ageDays <= 180:
		return 210
	default:
		return 240
	}
}

func clampWeightKg(weight float64) float64 {
	if weight < 2.0 {
		return 2.0
	}
	if weight > 25.0 {
		return 25.0
	}
	return weight
}

func roundToOneDecimal(value float64) float64 {
	return math.Round(value*10) / 10
}

func roundToNearest5(value int) int {
	if value <= 0 {
		return 0
	}
	return int(math.Round(float64(value)/5.0) * 5)
}

func clampInt(value, minValue, maxValue int) int {
	if value < minValue {
		return minValue
	}
	if value > maxValue {
		return maxValue
	}
	return value
}

func formatWeightForReference(weight *float64) string {
	if weight == nil {
		return "n/a"
	}
	return strconv.FormatFloat(roundToOneDecimal(*weight), 'f', 1, 64)
}

func mapFloatPointer(raw any) *float64 {
	switch value := raw.(type) {
	case float64:
		clamped := clampWeightKg(value)
		return &clamped
	case float32:
		clamped := clampWeightKg(float64(value))
		return &clamped
	case int:
		clamped := clampWeightKg(float64(value))
		return &clamped
	case int64:
		clamped := clampWeightKg(float64(value))
		return &clamped
	case string:
		trimmed := strings.TrimSpace(value)
		if trimmed == "" {
			return nil
		}
		parsed, err := strconv.ParseFloat(trimmed, 64)
		if err != nil {
			return nil
		}
		clamped := clampWeightKg(parsed)
		return &clamped
	default:
		return nil
	}
}

func mapBoolPointer(raw any) *bool {
	switch value := raw.(type) {
	case bool:
		result := value
		return &result
	case string:
		trimmed := strings.TrimSpace(strings.ToLower(value))
		if trimmed == "true" || trimmed == "1" || trimmed == "yes" {
			result := true
			return &result
		}
		if trimmed == "false" || trimmed == "0" || trimmed == "no" {
			result := false
			return &result
		}
		return nil
	default:
		return nil
	}
}

func coalesceNonEmpty(primary, fallback string) string {
	if strings.TrimSpace(primary) != "" {
		return primary
	}
	return fallback
}

func loadPersonaSettingsWithQuerier(ctx context.Context, q dbQuerier, userID string) (map[string]any, error) {
	var personaRaw []byte
	err := q.QueryRow(
		ctx,
		`SELECT "personaJson" FROM "PersonaProfile" WHERE "userId" = $1 LIMIT 1`,
		userID,
	).Scan(&personaRaw)
	if errors.Is(err, pgx.ErrNoRows) {
		return map[string]any{}, nil
	}
	if err != nil {
		return nil, err
	}
	return parseJSONStringMap(personaRaw), nil
}

func upsertPersonaSettingsWithQuerier(ctx context.Context, q dbQuerier, userID string, persona map[string]any) error {
	_, err := q.Exec(
		ctx,
		`INSERT INTO "PersonaProfile" (id, "userId", "personaJson", "updatedAt")
		 VALUES ($1, $2, $3, NOW())
		 ON CONFLICT ("userId")
		 DO UPDATE SET "personaJson" = EXCLUDED."personaJson", "updatedAt" = NOW()`,
		uuid.NewString(),
		userID,
		mustMarshalJSON(persona),
	)
	return err
}

func readBabySettings(persona map[string]any, babyID string) map[string]any {
	if persona == nil {
		return map[string]any{}
	}
	appSettings, ok := persona["app_settings"].(map[string]any)
	if !ok {
		return map[string]any{}
	}
	babyProfiles, ok := appSettings["baby_profiles"].(map[string]any)
	if !ok {
		return map[string]any{}
	}
	profileAny, ok := babyProfiles[babyID]
	if !ok {
		return map[string]any{}
	}
	profile, ok := profileAny.(map[string]any)
	if !ok {
		return map[string]any{}
	}
	return profile
}

func writeBabySettings(persona map[string]any, babyID string, babySettings map[string]any) {
	if persona == nil {
		return
	}
	appSettings, ok := persona["app_settings"].(map[string]any)
	if !ok {
		appSettings = map[string]any{}
		persona["app_settings"] = appSettings
	}
	babyProfiles, ok := appSettings["baby_profiles"].(map[string]any)
	if !ok {
		babyProfiles = map[string]any{}
		appSettings["baby_profiles"] = babyProfiles
	}
	babyProfiles[babyID] = babySettings
}
