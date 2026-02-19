package server

import (
	"errors"
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
)

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
	nowUTC := time.Now().UTC()

	rows, err := a.db.Query(
		c.Request.Context(),
		`SELECT "startTime" FROM "Event"
		 WHERE "babyId" = $1
		   AND type IN ('FORMULA', 'BREASTFEED')
		   AND "startTime" <= $2
		 ORDER BY "startTime" DESC LIMIT 10`,
		baby.ID,
		nowUTC,
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

	result := calculateNextFeedingETA(times, nowUTC)
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

func (a *App) quickLandingSnapshot(c *gin.Context) {
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

	now := time.Now().UTC()
	start := startOfUTCDay(now)
	end := start.Add(24 * time.Hour)

	rows, err := a.db.Query(
		c.Request.Context(),
		`SELECT type, "startTime", "endTime", "valueJson"
		 FROM "Event"
		 WHERE "babyId" = $1
		   AND "startTime" >= $2
		   AND "startTime" < $3
		   AND type IN ('FORMULA', 'BREASTFEED', 'SLEEP', 'PEE', 'POO', 'MEDICATION', 'MEMO')
		 ORDER BY "startTime" DESC`,
		baby.ID,
		start,
		end,
	)
	if err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to load events")
		return
	}
	defer rows.Close()

	formulaBands := map[string]int{
		"night":     0,
		"morning":   0,
		"afternoon": 0,
		"evening":   0,
	}
	formulaCount := 0
	formulaTimes := make([]string, 0)
	breastfeedCount := 0
	breastfeedTimes := make([]string, 0)
	var lastFormulaTime *time.Time
	var lastBreastfeedTime *time.Time
	var recentSleepTime *time.Time
	var recentSleepDurationMin *int
	var sleepReferenceTime *time.Time
	diaperPeeCount := 0
	diaperPooCount := 0
	var lastDiaperTime *time.Time
	medicationCount := 0
	var lastMedicationTime *time.Time
	specialMemo := "No special memo for today."

	for rows.Next() {
		var eventType string
		var startedAt time.Time
		var endedAt *time.Time
		var valueRaw []byte
		if err := rows.Scan(&eventType, &startedAt, &endedAt, &valueRaw); err != nil {
			writeError(c, http.StatusInternalServerError, "Failed to parse events")
			return
		}

		startedUTC := startedAt.UTC()
		valueMap := parseJSONStringMap(valueRaw)

		switch eventType {
		case "FORMULA":
			formulaCount++
			if lastFormulaTime == nil {
				lastFormulaTime = &startedUTC
			}
			formulaTimes = append(formulaTimes, startedUTC.Format(time.RFC3339))
			amountML := int(extractNumberFromMap(valueMap, "ml", "amount_ml", "volume_ml") + 0.5)
			formulaBands[landingFormulaBand(startedUTC.Hour())] += amountML

		case "BREASTFEED":
			breastfeedCount++
			if lastBreastfeedTime == nil {
				lastBreastfeedTime = &startedUTC
			}
			breastfeedTimes = append(breastfeedTimes, startedUTC.Format(time.RFC3339))

		case "SLEEP":
			if recentSleepTime == nil {
				recentSleepTime = &startedUTC
				if endedAt != nil {
					endedUTC := endedAt.UTC()
					sleepReferenceTime = &endedUTC
					duration := int(endedUTC.Sub(startedUTC).Minutes())
					if duration < 0 {
						duration = 0
					}
					recentSleepDurationMin = &duration
				} else {
					sleepReferenceTime = &startedUTC
				}
			}

		case "PEE":
			diaperPeeCount++
			if lastDiaperTime == nil {
				lastDiaperTime = &startedUTC
			}

		case "POO":
			diaperPooCount++
			if lastDiaperTime == nil {
				lastDiaperTime = &startedUTC
			}

		case "MEDICATION":
			medicationCount++
			if lastMedicationTime == nil {
				lastMedicationTime = &startedUTC
			}

		case "MEMO":
			if specialMemo == "No special memo for today." {
				memoText := extractMemoText(valueMap)
				if memoText == "" {
					memoText = "Memo recorded today."
				}
				specialMemo = memoText
			}
		}
	}

	var minutesSinceLastSleep *int
	if sleepReferenceTime != nil {
		elapsed := int(now.Sub(sleepReferenceTime.UTC()).Minutes())
		if elapsed < 0 {
			elapsed = 0
		}
		minutesSinceLastSleep = &elapsed
	}

	formulaTotalML := formulaBands["night"] + formulaBands["morning"] + formulaBands["afternoon"] + formulaBands["evening"]

	profile, _, err := a.resolveBabyProfile(c.Request.Context(), user.ID, baby.ID, readRoles)
	if err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to resolve baby profile")
		return
	}
	lastFeedingTime, err := a.latestFeedingTime(c.Request.Context(), baby.ID)
	if err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to load latest feeding event")
		return
	}
	recommendation := calculateFeedingRecommendation(profile, lastFeedingTime, now)

	plan, err := a.ensureMonthlyGrant(c.Request.Context(), a.db, user.ID, baby.HouseholdID, now)
	if err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to resolve AI credit plan")
		return
	}
	balance, err := a.getWalletBalance(c.Request.Context(), a.db, user.ID)
	if err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to load AI credit balance")
		return
	}
	graceUsed, err := a.countGraceUsedToday(c.Request.Context(), a.db, user.ID, now)
	if err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to load AI grace usage")
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"date":                            start.Format("2006-01-02"),
		"formula_count":                   formulaCount,
		"formula_times":                   formulaTimes,
		"formula_total_ml":                formulaTotalML,
		"formula_amount_by_time_band_ml":  formulaBands,
		"last_formula_time":               formatNullableTimeRFC3339(lastFormulaTime),
		"breastfeed_count":                breastfeedCount,
		"breastfeed_times":                breastfeedTimes,
		"last_breastfeed_time":            formatNullableTimeRFC3339(lastBreastfeedTime),
		"recent_sleep_time":               formatNullableTimeRFC3339(recentSleepTime),
		"recent_sleep_duration_min":       recentSleepDurationMin,
		"minutes_since_last_sleep":        minutesSinceLastSleep,
		"diaper_pee_count":                diaperPeeCount,
		"diaper_poo_count":                diaperPooCount,
		"last_diaper_time":                formatNullableTimeRFC3339(lastDiaperTime),
		"medication_count":                medicationCount,
		"last_medication_time":            formatNullableTimeRFC3339(lastMedicationTime),
		"special_memo":                    specialMemo,
		"feeding_method":                  profile.FeedingMethod,
		"formula_type":                    profile.FormulaType,
		"formula_brand":                   profile.FormulaBrand,
		"formula_product":                 profile.FormulaProduct,
		"formula_contains_starch":         profile.FormulaContainsStarch,
		"formula_display_name":            formulaDisplayName(profile),
		"baby_age_days":                   profile.AgeDays,
		"baby_weight_kg":                  profile.WeightKg,
		"recommended_formula_daily_ml":    recommendation.RecommendedFormulaDailyML,
		"recommended_formula_per_feed_ml": recommendation.RecommendedFormulaPerFeedML,
		"recommended_feed_interval_min":   recommendation.RecommendedIntervalMin,
		"recommended_next_feeding_time":   formatNullableTimeRFC3339(recommendation.RecommendedNextFeedingTime),
		"recommended_next_feeding_in_min": recommendation.RecommendedNextFeedingInMin,
		"recommendation_note":             recommendation.Note,
		"recommendation_reference_text":   recommendation.ReferenceText,
		"ai_credit_balance":               balance,
		"ai_grace_used_today":             graceUsed,
		"ai_grace_limit":                  graceLimitPerDay,
		"ai_plan":                         plan,
		"reference_text":                  "Derived from today's confirmed events.",
	})
}

func landingFormulaBand(hour int) string {
	switch {
	case hour < 6:
		return "night"
	case hour < 12:
		return "morning"
	case hour < 18:
		return "afternoon"
	default:
		return "evening"
	}
}

func extractMemoText(value map[string]any) string {
	for _, key := range []string{"memo", "note", "text", "content", "message"} {
		memoText := strings.TrimSpace(toString(value[key]))
		if memoText != "" {
			return memoText
		}
	}
	return ""
}

func formatNullableTimeRFC3339(value *time.Time) *string {
	if value == nil {
		return nil
	}
	formatted := value.UTC().Format(time.RFC3339)
	return &formatted
}

type aiIntent string

const (
	aiIntentMedicalRelated aiIntent = "medical_related"
	aiIntentDataQuery      aiIntent = "data_query"
	aiIntentCareRoutine    aiIntent = "care_routine"
	aiIntentSmalltalk      aiIntent = "smalltalk"
)

func classifyAIIntent(question string) aiIntent {
	normalized := strings.ToLower(strings.Join(strings.Fields(strings.TrimSpace(question)), " "))
	if normalized == "" {
		return aiIntentSmalltalk
	}

	medicalKeywords := []string{
		"fever", "temp", "temperature", "diarrhea", "vomit", "rash", "cough", "blood",
		"medication", "medicine", "antibiotic", "emergency", "hospital", "pediatric",
	}
	if containsAnyKeyword(normalized, medicalKeywords) {
		return aiIntentMedicalRelated
	}

	dataKeywords := []string{
		"how many", "count", "total", "last", "when", "eta", "summary", "trend",
		"record", "history", "stats", "average", "interval",
	}
	if containsAnyKeyword(normalized, dataKeywords) {
		return aiIntentDataQuery
	}

	careKeywords := []string{
		"sleep", "nap", "night sleep", "routine", "schedule", "pattern", "feeding plan",
		"bedtime", "wake", "soothe", "care plan",
	}
	if containsAnyKeyword(normalized, careKeywords) {
		return aiIntentCareRoutine
	}

	casualKeywords := []string{
		"thanks", "thank you", "ok", "okay", "got it", "hello", "hi", "tired", "hungry",
	}
	if containsAnyKeyword(normalized, casualKeywords) {
		return aiIntentSmalltalk
	}
	if len([]rune(normalized)) <= 8 {
		return aiIntentSmalltalk
	}

	return aiIntentSmalltalk
}

func containsAnyKeyword(question string, keywords []string) bool {
	for _, keyword := range keywords {
		needle := strings.TrimSpace(strings.ToLower(keyword))
		if needle == "" {
			continue
		}
		if strings.Contains(question, needle) {
			return true
		}
	}
	return false
}
func (a *App) loadRecentEventCounts(ctx *gin.Context, babyID string, since time.Time) (map[string]int, error) {
	rows, err := a.db.Query(
		ctx.Request.Context(),
		`SELECT type::text, COUNT(*)::int
		 FROM "Event"
		 WHERE "babyId" = $1
		   AND "startTime" >= $2
		   AND type::text = ANY($3::text[])
		 GROUP BY type`,
		babyID,
		since,
		[]string{"SYMPTOM", "MEDICATION", "FORMULA", "BREASTFEED", "PEE", "POO"},
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	counts := map[string]int{}
	for rows.Next() {
		var eventType string
		var count int
		if err := rows.Scan(&eventType, &count); err != nil {
			return nil, err
		}
		counts[eventType] = count
	}
	return counts, nil
}

func (a *App) buildMedicalGuidance(c *gin.Context, babyID string) (string, string, error) {
	since := time.Now().UTC().Add(-72 * time.Hour)
	counts, err := a.loadRecentEventCounts(c, babyID, since)
	if err != nil {
		return "", "", err
	}

	feedings := counts["FORMULA"] + counts["BREASTFEED"]
	summaryLine := fmt.Sprintf(
		"1) Record summary (last 72h): symptom logs %d, medication logs %d, feedings %d, diapers pee %d / poo %d.",
		counts["SYMPTOM"], counts["MEDICATION"], feedings, counts["PEE"], counts["POO"],
	)
	if counts["SYMPTOM"]+counts["MEDICATION"]+feedings+counts["PEE"]+counts["POO"] == 0 {
		summaryLine = "1) Record summary (last 72h): no confirmed symptom/medication/feeding/diaper logs were found."
	}

	answer := strings.Join([]string{
		summaryLine,
		"2) Possibilities: viral illness, feeding intolerance, mild GI upset, or medication side effect.",
		"3) Before clinic visit: keep hydration and small frequent feeding, track temperature and diaper output every 4-6h, and avoid adding new medicine without clinician guidance.",
		"4) Where to go: start with Pediatrics for same-day evaluation if symptoms persist; use ER now if red flags appear.",
		"5) Red flags now: breathing difficulty, repeated vomiting, blood in stool/vomit, no urine for 8+ hours, persistent high fever, unusual drowsiness, or seizure.",
	}, "\n")
	referenceText := "Built from confirmed event logs; this is guidance and not a diagnosis."
	return answer, referenceText, nil
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
	var summary []string
	err = a.db.QueryRow(
		c.Request.Context(),
		`SELECT "summaryText" FROM "Report"
		 WHERE "babyId" = $1 AND "periodType" = 'DAILY' AND "periodStart" = $2
		 ORDER BY "createdAt" DESC LIMIT 1`,
		baby.ID,
		targetDate,
	).Scan(&summaryText)
	if err == nil {
		summary = splitNonEmptyLines(summaryText)
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
		 WHERE "babyId" = $1 AND "startTime" >= $2 AND "startTime" < $3
		 ORDER BY "startTime" ASC`,
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
	events := make([]gin.H, 0, 16)
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
		eventItem := gin.H{
			"type":       eventType,
			"start_time": startedAt.UTC().Format(time.RFC3339),
			"value":      valueMap,
		}
		if endedAt != nil {
			eventItem["end_time"] = endedAt.UTC().Format(time.RFC3339)
		} else {
			eventItem["end_time"] = nil
		}
		events = append(events, eventItem)
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
	if err := rows.Err(); err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to parse events")
		return
	}

	if len(summary) == 0 {
		summary = []string{
			"Feeding events: " + strconv.Itoa(counts["FORMULA"]+counts["BREASTFEED"]),
			"Formula total: " + strconv.Itoa(int(formulaTotal)) + " ml",
			"Sleep total: " + strconv.Itoa(sleepMinutes) + " minutes",
			"Diaper events: pee " + strconv.Itoa(counts["PEE"]) + ", poo " + strconv.Itoa(counts["POO"]),
		}
	}

	c.JSON(http.StatusOK, gin.H{
		"baby_id": baby.ID,
		"date":    targetDate.Format("2006-01-02"),
		"summary": summary,
		"events":  events,
		"labels":  []string{"record_based"},
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
