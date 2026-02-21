package server

import (
	"errors"
	"fmt"
	"math"
	"net/http"
	"sort"
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

	localZone, tzNormalized, err := parseTZOffset(c.Query("tz_offset"))
	if err != nil {
		writeError(c, http.StatusBadRequest, err.Error())
		return
	}
	rangeKey := strings.ToLower(strings.TrimSpace(c.DefaultQuery("range", "day")))
	nowUTC := time.Now().UTC()
	localNow := nowUTC.In(localZone)
	localAnchor, err := parseQuickAnchorDate(c.Query("anchor_date"), localNow, localZone)
	if err != nil {
		writeError(c, http.StatusBadRequest, err.Error())
		return
	}
	localStart, localEnd, rangeDays, rangeLabel, err := quickRangeWindow(localAnchor, rangeKey)
	if err != nil {
		writeError(c, http.StatusBadRequest, err.Error())
		return
	}
	start := localStart.UTC()
	end := localEnd.UTC()

	rows, err := a.db.Query(
		c.Request.Context(),
		`SELECT type, "startTime", "endTime", "valueJson", "metadataJson"
		 FROM "Event"
		 WHERE "babyId" = $1
		   AND "startTime" >= $2
		   AND "startTime" < $3
		   AND NOT (
		     "endTime" IS NULL
		     AND (
		       COALESCE("metadataJson"->>'event_state', '') = 'OPEN'
		       OR COALESCE("metadataJson"->>'entry_mode', '') = 'manual_start'
		     )
		   )
		   AND COALESCE("metadataJson"->>'event_state', 'CLOSED') <> 'CANCELED'
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
	formulaByDay := map[string]int{}
	type formulaPoint struct {
		StartedAt time.Time
		AmountML  int
	}
	formulaEvents := make([]formulaPoint, 0)
	formulaCount := 0
	formulaTimes := make([]string, 0)
	breastfeedCount := 0
	breastfeedTimes := make([]string, 0)
	feedingsCount := 0
	var lastFormulaTime *time.Time
	var lastBreastfeedTime *time.Time
	var recentSleepTime *time.Time
	var recentSleepDurationMin *int
	var sleepReferenceTime *time.Time
	var lastSleepEndTime *time.Time
	sleepTotalMin := 0
	sleepNapTotalMin := 0
	sleepNightTotalMin := 0
	diaperPeeCount := 0
	diaperPooCount := 0
	var lastPeeTime *time.Time
	var lastPooTime *time.Time
	var lastDiaperTime *time.Time
	weaningCount := 0
	memoCount := 0
	var lastWeaningTime *time.Time
	medicationCount := 0
	var lastMedicationTime *time.Time
	var lastMedicationName *string
	var lastFormulaAmountML *int
	specialMemo := "No special memo in selected range."

	for rows.Next() {
		var eventType string
		var startedAt time.Time
		var endedAt *time.Time
		var valueRaw []byte
		var metadataRaw []byte
		if err := rows.Scan(&eventType, &startedAt, &endedAt, &valueRaw, &metadataRaw); err != nil {
			writeError(c, http.StatusInternalServerError, "Failed to parse events")
			return
		}

		startedUTC := startedAt.UTC()
		startedLocal := startedUTC.In(localZone)
		valueMap := parseJSONStringMap(valueRaw)
		metadataMap := parseJSONStringMap(metadataRaw)

		switch eventType {
		case "FORMULA":
			feedingsCount++
			formulaCount++
			if lastFormulaTime == nil {
				lastFormulaTime = &startedUTC
			}
			formulaTimes = append(formulaTimes, startedUTC.Format(time.RFC3339))
			amountML := int(extractNumberFromMap(valueMap, "ml", "amount_ml", "volume_ml") + 0.5)
			if amountML < 0 {
				amountML = 0
			}
			if lastFormulaAmountML == nil {
				amountCopy := amountML
				lastFormulaAmountML = &amountCopy
			}
			formulaBands[landingFormulaBand(startedLocal.Hour())] += amountML
			dayKey := startedLocal.Format("2006-01-02")
			formulaByDay[dayKey] += amountML
			formulaEvents = append(formulaEvents, formulaPoint{
				StartedAt: startedLocal,
				AmountML:  amountML,
			})

		case "BREASTFEED":
			feedingsCount++
			breastfeedCount++
			if lastBreastfeedTime == nil {
				lastBreastfeedTime = &startedUTC
			}
			breastfeedTimes = append(breastfeedTimes, startedUTC.Format(time.RFC3339))

		case "SLEEP":
			if recentSleepTime == nil {
				recentSleepTime = &startedUTC
			}
			durationPtr := extractDurationMinutes(valueMap, startedUTC, endedAt)
			duration := 0
			if durationPtr != nil {
				duration = int(*durationPtr + 0.5)
				if duration < 0 {
					duration = 0
				}
				if recentSleepDurationMin == nil {
					recentSleepDurationMin = &duration
				}
			}
			sleepTotalMin += duration
			if startedLocal.Hour() >= 6 && startedLocal.Hour() < 18 {
				sleepNapTotalMin += duration
			} else {
				sleepNightTotalMin += duration
			}
			if endedAt != nil {
				endedUTC := endedAt.UTC()
				if lastSleepEndTime == nil {
					lastSleepEndTime = &endedUTC
				}
			}

		case "PEE":
			diaperPeeCount++
			if lastPeeTime == nil {
				lastPeeTime = &startedUTC
			}
			if lastDiaperTime == nil {
				lastDiaperTime = &startedUTC
			}

		case "POO":
			diaperPooCount++
			if lastPooTime == nil {
				lastPooTime = &startedUTC
			}
			if lastDiaperTime == nil {
				lastDiaperTime = &startedUTC
			}

		case "MEDICATION":
			medicationCount++
			if lastMedicationTime == nil {
				lastMedicationTime = &startedUTC
				medicationName := ""
				for _, raw := range []any{
					valueMap["name"],
					valueMap["medication_name"],
					valueMap["medication_type"],
				} {
					text := strings.TrimSpace(toString(raw))
					if text == "" {
						continue
					}
					medicationName = text
					break
				}
				if medicationName != "" {
					nameCopy := medicationName
					lastMedicationName = &nameCopy
				}
			}

		case "MEMO":
			memoCount++
			if isWeaningMemo(valueMap, metadataMap) {
				weaningCount++
				if lastWeaningTime == nil {
					lastWeaningTime = &startedUTC
				}
			}
		}

		if specialMemo == "No special memo in selected range." {
			memoText := extractMemoText(valueMap)
			if memoText != "" {
				specialMemo = memoText
			}
		}
	}
	if err := rows.Err(); err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to parse events")
		return
	}

	var openFormulaEventID *string
	var openFormulaStartTime *time.Time
	var openFormulaValue map[string]any
	var openFormulaMemo *string
	var openBreastfeedEventID *string
	var openBreastfeedStartTime *time.Time
	var openBreastfeedValue map[string]any
	var openBreastfeedMemo *string
	var openSleepEventID *string
	var openSleepStartTime *time.Time
	var openSleepValue map[string]any
	var openSleepMemo *string
	var openDiaperEventID *string
	var openDiaperStartTime *time.Time
	var openDiaperValue map[string]any
	var openDiaperMemo *string
	var openDiaperType *string
	var openWeaningEventID *string
	var openWeaningStartTime *time.Time
	var openWeaningValue map[string]any
	var openWeaningMemo *string
	var openMedicationEventID *string
	var openMedicationStartTime *time.Time
	var openMedicationValue map[string]any
	var openMedicationMemo *string

	openRows, err := a.db.Query(
		c.Request.Context(),
		`SELECT id, type, "startTime", "valueJson", "metadataJson"
		 FROM "Event"
		 WHERE "babyId" = $1
		   AND "endTime" IS NULL
		   AND (
		     COALESCE("metadataJson"->>'event_state', '') = 'OPEN'
		     OR COALESCE("metadataJson"->>'entry_mode', '') = 'manual_start'
		   )
		   AND type IN ('FORMULA', 'BREASTFEED', 'SLEEP', 'PEE', 'POO', 'MEDICATION', 'MEMO')
		 ORDER BY "startTime" DESC`,
		baby.ID,
	)
	if err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to load open events")
		return
	}
	defer openRows.Close()

	for openRows.Next() {
		var eventID string
		var eventType string
		var startTime time.Time
		var valueRaw []byte
		var metadataRaw []byte
		if err := openRows.Scan(&eventID, &eventType, &startTime, &valueRaw, &metadataRaw); err != nil {
			writeError(c, http.StatusInternalServerError, "Failed to parse open events")
			return
		}
		valueMap := parseJSONStringMap(valueRaw)
		metadataMap := parseJSONStringMap(metadataRaw)
		switch eventType {
		case "FORMULA":
			if openFormulaEventID == nil {
				eventIDCopy := eventID
				startCopy := startTime.UTC()
				openFormulaEventID = &eventIDCopy
				openFormulaStartTime = &startCopy
				openFormulaValue = valueMap
				memoText := extractMemoText(valueMap)
				if memoText != "" {
					openFormulaMemo = &memoText
				}
			}
		case "BREASTFEED":
			if openBreastfeedEventID == nil {
				eventIDCopy := eventID
				startCopy := startTime.UTC()
				openBreastfeedEventID = &eventIDCopy
				openBreastfeedStartTime = &startCopy
				openBreastfeedValue = valueMap
				memoText := extractMemoText(valueMap)
				if memoText != "" {
					openBreastfeedMemo = &memoText
				}
			}
		case "SLEEP":
			if openSleepEventID == nil {
				eventIDCopy := eventID
				startCopy := startTime.UTC()
				openSleepEventID = &eventIDCopy
				openSleepStartTime = &startCopy
				openSleepValue = valueMap
				memoText := extractMemoText(valueMap)
				if memoText != "" {
					openSleepMemo = &memoText
				}
			}
		case "PEE", "POO":
			if openDiaperEventID == nil {
				eventIDCopy := eventID
				startCopy := startTime.UTC()
				typeCopy := eventType
				openDiaperEventID = &eventIDCopy
				openDiaperStartTime = &startCopy
				openDiaperType = &typeCopy
				openDiaperValue = valueMap
				memoText := extractMemoText(valueMap)
				if memoText != "" {
					openDiaperMemo = &memoText
				}
			}
		case "MEDICATION":
			if openMedicationEventID == nil {
				eventIDCopy := eventID
				startCopy := startTime.UTC()
				openMedicationEventID = &eventIDCopy
				openMedicationStartTime = &startCopy
				openMedicationValue = valueMap
				memoText := extractMemoText(valueMap)
				if memoText != "" {
					openMedicationMemo = &memoText
				}
			}
		case "MEMO":
			if !isWeaningMemo(valueMap, metadataMap) {
				continue
			}
			if openWeaningEventID == nil {
				eventIDCopy := eventID
				startCopy := startTime.UTC()
				openWeaningEventID = &eventIDCopy
				openWeaningStartTime = &startCopy
				openWeaningValue = valueMap
				memoText := extractMemoText(valueMap)
				if memoText != "" {
					openWeaningMemo = &memoText
				}
			}
		}
	}
	if err := openRows.Err(); err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to parse open events")
		return
	}

	if recentSleepDurationMin == nil && lastSleepEndTime != nil && recentSleepTime != nil {
		duration := int(lastSleepEndTime.UTC().Sub(recentSleepTime.UTC()).Minutes())
		if duration < 0 {
			duration = 0
		}
		recentSleepDurationMin = &duration
	}
	if lastSleepEndTime != nil {
		sleepReferenceTime = lastSleepEndTime
	} else if recentSleepTime != nil {
		sleepReferenceTime = recentSleepTime
	}

	var minutesSinceLastSleep *int
	if sleepReferenceTime != nil {
		elapsed := int(nowUTC.Sub(sleepReferenceTime.UTC()).Minutes())
		if elapsed < 0 {
			elapsed = 0
		}
		minutesSinceLastSleep = &elapsed
	}

	formulaTotalML := formulaBands["night"] + formulaBands["morning"] + formulaBands["afternoon"] + formulaBands["evening"]
	avgFormulaMLPerDay := quickAvgPerDay(formulaTotalML, rangeDays)
	avgFeedingsPerDay := quickAvgPerDay(feedingsCount, rangeDays)
	avgSleepMinPerDay := quickAvgPerDay(sleepTotalMin, rangeDays)
	avgNapSleepMinPerDay := quickAvgPerDay(sleepNapTotalMin, rangeDays)
	avgNightSleepMinPerDay := quickAvgPerDay(sleepNightTotalMin, rangeDays)
	avgPeePerDay := quickAvgPerDay(diaperPeeCount, rangeDays)
	avgPooPerDay := quickAvgPerDay(diaperPooCount, rangeDays)

	graphLabels := make([]string, 0)
	graphPoints := make([]float64, 0)
	graphMode := ""
	switch rangeKey {
	case "day":
		graphMode = "feeding_by_session"
		sort.Slice(formulaEvents, func(i, j int) bool {
			return formulaEvents[i].StartedAt.Before(formulaEvents[j].StartedAt)
		})
		for _, event := range formulaEvents {
			graphLabels = append(graphLabels, event.StartedAt.Format("15:04"))
			graphPoints = append(graphPoints, float64(event.AmountML))
		}
	case "week":
		graphMode = "daily_total_ml_7d"
		for day := localStart; day.Before(localEnd); day = day.Add(24 * time.Hour) {
			dayKey := day.Format("2006-01-02")
			graphLabels = append(graphLabels, day.Format("1/2"))
			graphPoints = append(graphPoints, float64(formulaByDay[dayKey]))
		}
	case "month":
		graphMode = "daily_total_ml_month"
		for day := localStart; day.Before(localEnd); day = day.Add(24 * time.Hour) {
			dayKey := day.Format("2006-01-02")
			graphLabels = append(graphLabels, day.Format("2"))
			graphPoints = append(graphPoints, float64(formulaByDay[dayKey]))
		}
	default:
		graphMode = "daily_total_ml"
	}
	if len(graphPoints) == 0 {
		graphLabels = []string{"-"}
		graphPoints = []float64{0}
	}

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
	recommendation := calculateFeedingRecommendation(profile, lastFeedingTime, nowUTC)

	plan, err := a.ensureMonthlyGrant(c.Request.Context(), a.db, user.ID, baby.HouseholdID, nowUTC)
	if err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to resolve AI credit plan")
		return
	}
	balance, err := a.getWalletBalance(c.Request.Context(), a.db, user.ID)
	if err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to load AI credit balance")
		return
	}
	graceUsed, err := a.countGraceUsedToday(c.Request.Context(), a.db, user.ID, nowUTC)
	if err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to load AI grace usage")
		return
	}

	rangeEndDate := localEnd.Add(-24 * time.Hour).Format("2006-01-02")
	if rangeEndDate < localStart.Format("2006-01-02") {
		rangeEndDate = localStart.Format("2006-01-02")
	}

	c.JSON(http.StatusOK, gin.H{
		"baby_id":                         baby.ID,
		"baby_name":                       profile.Name,
		"baby_profile_photo_url":          profile.ProfilePhotoURL,
		"date":                            localAnchor.Format("2006-01-02"),
		"anchor_date":                     localAnchor.Format("2006-01-02"),
		"range":                           rangeKey,
		"range_label":                     rangeLabel,
		"range_start_date":                localStart.Format("2006-01-02"),
		"range_end_date":                  rangeEndDate,
		"range_day_count":                 rangeDays,
		"tz_offset":                       tzNormalized,
		"formula_count":                   formulaCount,
		"formula_times":                   formulaTimes,
		"feedings_count":                  feedingsCount,
		"formula_total_ml":                formulaTotalML,
		"avg_formula_ml_per_day":          avgFormulaMLPerDay,
		"avg_feedings_per_day":            avgFeedingsPerDay,
		"formula_amount_by_time_band_ml":  formulaBands,
		"last_formula_time":               formatNullableTimeRFC3339(lastFormulaTime),
		"last_formula_amount_ml":          lastFormulaAmountML,
		"breastfeed_count":                breastfeedCount,
		"breastfeed_times":                breastfeedTimes,
		"last_breastfeed_time":            formatNullableTimeRFC3339(lastBreastfeedTime),
		"recent_sleep_time":               formatNullableTimeRFC3339(recentSleepTime),
		"recent_sleep_duration_min":       recentSleepDurationMin,
		"sleep_total_min":                 sleepTotalMin,
		"sleep_day_total_min":             sleepNapTotalMin,
		"sleep_night_total_min":           sleepNightTotalMin,
		"avg_sleep_minutes_per_day":       avgSleepMinPerDay,
		"avg_nap_minutes_per_day":         avgNapSleepMinPerDay,
		"avg_night_sleep_minutes_per_day": avgNightSleepMinPerDay,
		"last_sleep_end_time":             formatNullableTimeRFC3339(lastSleepEndTime),
		"minutes_since_last_sleep":        minutesSinceLastSleep,
		"diaper_pee_count":                diaperPeeCount,
		"diaper_poo_count":                diaperPooCount,
		"avg_diaper_pee_per_day":          avgPeePerDay,
		"avg_diaper_poo_per_day":          avgPooPerDay,
		"last_pee_time":                   formatNullableTimeRFC3339(lastPeeTime),
		"last_poo_time":                   formatNullableTimeRFC3339(lastPooTime),
		"last_diaper_time":                formatNullableTimeRFC3339(lastDiaperTime),
		"weaning_count":                   weaningCount,
		"last_weaning_time":               formatNullableTimeRFC3339(lastWeaningTime),
		"memo_count":                      memoCount,
		"medication_count":                medicationCount,
		"last_medication_time":            formatNullableTimeRFC3339(lastMedicationTime),
		"last_medication_name":            lastMedicationName,
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
		"feeding_graph_mode":              graphMode,
		"feeding_graph_labels":            graphLabels,
		"feeding_graph_points":            graphPoints,
		"ai_credit_balance":               balance,
		"ai_grace_used_today":             graceUsed,
		"ai_grace_limit":                  graceLimitPerDay,
		"ai_plan":                         plan,
		"open_formula_event_id":           openFormulaEventID,
		"open_formula_start_time":         formatNullableTimeRFC3339(openFormulaStartTime),
		"open_formula_value":              openFormulaValue,
		"open_formula_memo":               openFormulaMemo,
		"open_breastfeed_event_id":        openBreastfeedEventID,
		"open_breastfeed_start_time":      formatNullableTimeRFC3339(openBreastfeedStartTime),
		"open_breastfeed_value":           openBreastfeedValue,
		"open_breastfeed_memo":            openBreastfeedMemo,
		"open_sleep_event_id":             openSleepEventID,
		"open_sleep_start_time":           formatNullableTimeRFC3339(openSleepStartTime),
		"open_sleep_value":                openSleepValue,
		"open_sleep_memo":                 openSleepMemo,
		"open_diaper_event_id":            openDiaperEventID,
		"open_diaper_start_time":          formatNullableTimeRFC3339(openDiaperStartTime),
		"open_diaper_type":                openDiaperType,
		"open_diaper_value":               openDiaperValue,
		"open_diaper_memo":                openDiaperMemo,
		"open_weaning_event_id":           openWeaningEventID,
		"open_weaning_start_time":         formatNullableTimeRFC3339(openWeaningStartTime),
		"open_weaning_value":              openWeaningValue,
		"open_weaning_memo":               openWeaningMemo,
		"open_medication_event_id":        openMedicationEventID,
		"open_medication_start_time":      formatNullableTimeRFC3339(openMedicationStartTime),
		"open_medication_value":           openMedicationValue,
		"open_medication_memo":            openMedicationMemo,
		"reference_text":                  "Derived from selected range confirmed events.",
	})
}

func quickRangeWindow(localAnchor time.Time, rangeKey string) (time.Time, time.Time, int, string, error) {
	location := localAnchor.Location()
	year, month, day := localAnchor.Date()
	dayStart := time.Date(year, month, day, 0, 0, 0, 0, location)

	switch rangeKey {
	case "day":
		return dayStart, dayStart.Add(24 * time.Hour), 1, dayStart.Format("2006-01-02"), nil
	case "week":
		weekdayOffset := int(dayStart.Weekday() - time.Monday)
		if weekdayOffset < 0 {
			weekdayOffset = 6
		}
		weekStart := dayStart.AddDate(0, 0, -weekdayOffset)
		weekEnd := weekStart.AddDate(0, 0, 7)
		label := fmt.Sprintf("%d/%d - %d/%d", weekStart.Month(), weekStart.Day(), weekStart.AddDate(0, 0, 6).Month(), weekStart.AddDate(0, 0, 6).Day())
		return weekStart, weekEnd, 7, label, nil
	case "month":
		monthStart := time.Date(year, month, 1, 0, 0, 0, 0, location)
		monthEnd := monthStart.AddDate(0, 1, 0)
		days := int(monthEnd.Sub(monthStart).Hours() / 24)
		if days <= 0 {
			days = 1
		}
		label := monthStart.Format("2006-01")
		return monthStart, monthEnd, days, label, nil
	default:
		return time.Time{}, time.Time{}, 0, "", errors.New("range must be one of: day, week, month")
	}
}

func parseQuickAnchorDate(raw string, localNow time.Time, zone *time.Location) (time.Time, error) {
	if zone == nil {
		zone = time.UTC
	}
	trimmed := strings.TrimSpace(raw)
	if trimmed == "" {
		local := localNow.In(zone)
		return time.Date(local.Year(), local.Month(), local.Day(), 0, 0, 0, 0, zone), nil
	}
	parsed, err := parseDate(trimmed)
	if err != nil {
		return time.Time{}, errors.New("anchor_date must be YYYY-MM-DD")
	}
	return time.Date(parsed.Year(), parsed.Month(), parsed.Day(), 0, 0, 0, 0, zone), nil
}

func parseTZOffset(raw string) (*time.Location, string, error) {
	trimmed := strings.TrimSpace(raw)
	if trimmed == "" {
		return time.UTC, "+00:00", nil
	}
	if len(trimmed) != 6 || trimmed[3] != ':' || (trimmed[0] != '+' && trimmed[0] != '-') {
		return nil, "", errors.New("tz_offset must be in +/-HH:MM format")
	}
	hours, err := strconv.Atoi(trimmed[1:3])
	if err != nil {
		return nil, "", errors.New("tz_offset must be in +/-HH:MM format")
	}
	minutes, err := strconv.Atoi(trimmed[4:6])
	if err != nil {
		return nil, "", errors.New("tz_offset must be in +/-HH:MM format")
	}
	if hours > 14 || minutes > 59 || (hours == 14 && minutes != 0) {
		return nil, "", errors.New("tz_offset is out of range")
	}
	totalSeconds := (hours * 60 * 60) + (minutes * 60)
	sign := trimmed[0:1]
	if sign == "-" {
		totalSeconds *= -1
	}
	normalized := fmt.Sprintf("%s%02d:%02d", sign, hours, minutes)
	return time.FixedZone("UTC"+normalized, totalSeconds), normalized, nil
}

func quickAvgPerDay(total int, days int) float64 {
	if days <= 0 {
		return 0
	}
	return math.Round((float64(total)/float64(days))*10) / 10
}

func extractDurationMinutes(valueMap map[string]any, startTime time.Time, endTime *time.Time) *float64 {
	if valueMap != nil {
		for _, key := range []string{"duration_min", "duration_minutes", "minutes"} {
			raw, ok := valueMap[key]
			if !ok {
				continue
			}
			switch parsed := raw.(type) {
			case float64:
				if parsed < 0 {
					zero := 0.0
					return &zero
				}
				return &parsed
			case int:
				value := float64(parsed)
				if value < 0 {
					zero := 0.0
					return &zero
				}
				return &value
			case string:
				trimmed := strings.TrimSpace(parsed)
				if trimmed == "" {
					continue
				}
				value, err := strconv.ParseFloat(trimmed, 64)
				if err != nil {
					continue
				}
				if value < 0 {
					zero := 0.0
					return &zero
				}
				return &value
			}
		}
	}
	if endTime == nil {
		return nil
	}
	duration := endTime.UTC().Sub(startTime.UTC()).Minutes()
	if duration < 0 {
		duration = 0
	}
	return &duration
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

func isWeaningMemo(value map[string]any, metadata map[string]any) bool {
	candidates := []string{
		toString(value["category"]),
		toString(value["entry_kind"]),
		toString(metadata["category"]),
		toString(metadata["entry_kind"]),
	}
	for _, candidate := range candidates {
		if strings.EqualFold(strings.TrimSpace(candidate), "WEANING") {
			return true
		}
	}
	return false
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
	localZone, _, err := parseTZOffset(c.Query("tz_offset"))
	if err != nil {
		writeError(c, http.StatusBadRequest, err.Error())
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

	localStart := time.Date(
		targetDate.Year(),
		targetDate.Month(),
		targetDate.Day(),
		0,
		0,
		0,
		0,
		localZone,
	)
	start := localStart.UTC()
	end := localStart.Add(24 * time.Hour).UTC()
	rows, err := a.db.Query(
		c.Request.Context(),
		`SELECT id, type, "startTime", "endTime", "valueJson"
		 FROM "Event"
		 WHERE "babyId" = $1
		   AND "startTime" >= $2
		   AND "startTime" < $3
		   AND NOT (
		     "endTime" IS NULL
		     AND (
		       COALESCE("metadataJson"->>'event_state', '') = 'OPEN'
		       OR COALESCE("metadataJson"->>'entry_mode', '') = 'manual_start'
		     )
		   )
		   AND COALESCE("metadataJson"->>'event_state', 'CLOSED') <> 'CANCELED'
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
		var eventID string
		var eventType string
		var startedAt time.Time
		var endedAt *time.Time
		var valueRaw []byte
		if err := rows.Scan(&eventID, &eventType, &startedAt, &endedAt, &valueRaw); err != nil {
			writeError(c, http.StatusInternalServerError, "Failed to parse events")
			return
		}
		counts[eventType]++
		valueMap := parseJSONStringMap(valueRaw)
		eventItem := gin.H{
			"event_id":   eventID,
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
	localZone, _, err := parseTZOffset(c.Query("tz_offset"))
	if err != nil {
		writeError(c, http.StatusBadRequest, err.Error())
		return
	}
	localStart := time.Date(
		start.Year(),
		start.Month(),
		start.Day(),
		0,
		0,
		0,
		0,
		localZone,
	)
	startUTC := localStart.UTC()
	endUTC := localStart.Add(7 * 24 * time.Hour).UTC()

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
		startUTC,
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
			"week_start":  localStart.Format("2006-01-02"),
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

	currentMetrics, err := a.computeWeeklyMetrics(c, baby.ID, startUTC, endUTC)
	if err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to compute weekly metrics")
		return
	}
	previousStart := localStart.Add(-7 * 24 * time.Hour).UTC()
	previousMetrics, err := a.computeWeeklyMetrics(c, baby.ID, previousStart, startUTC)
	if err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to compute weekly metrics")
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"baby_id":    baby.ID,
		"week_start": localStart.Format("2006-01-02"),
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

func (a *App) getMonthlyReport(c *gin.Context) {
	user, ok := authUserFromContext(c)
	if !ok {
		writeError(c, http.StatusUnauthorized, "Unauthorized")
		return
	}
	babyID := c.Query("baby_id")
	monthStartRaw := strings.TrimSpace(c.Query("month_start"))
	if monthStartRaw == "" {
		writeError(c, http.StatusBadRequest, "month_start must be YYYY-MM-DD")
		return
	}
	requestedDate, err := parseDate(monthStartRaw)
	if err != nil {
		writeError(c, http.StatusBadRequest, "month_start must be YYYY-MM-DD")
		return
	}
	localZone, _, err := parseTZOffset(c.Query("tz_offset"))
	if err != nil {
		writeError(c, http.StatusBadRequest, err.Error())
		return
	}
	localMonthStart := time.Date(
		requestedDate.Year(),
		requestedDate.Month(),
		1,
		0,
		0,
		0,
		0,
		localZone,
	)
	startUTC := localMonthStart.UTC()
	endUTC := localMonthStart.AddDate(0, 1, 0).UTC()

	baby, statusCode, err := a.getBabyWithAccess(c.Request.Context(), user.ID, babyID, readRoles)
	if err != nil {
		writeError(c, statusCode, err.Error())
		return
	}

	currentMetrics, err := a.computeWeeklyMetrics(c, baby.ID, startUTC, endUTC)
	if err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to compute monthly metrics")
		return
	}
	previousStart := localMonthStart.AddDate(0, -1, 0).UTC()
	previousMetrics, err := a.computeWeeklyMetrics(c, baby.ID, previousStart, startUTC)
	if err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to compute monthly metrics")
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"baby_id":     baby.ID,
		"month_start": localMonthStart.Format("2006-01-02"),
		"trend": gin.H{
			"feeding_total_ml": trendString(currentMetrics.FeedingML, previousMetrics.FeedingML),
			"sleep_total_min":  trendString(float64(currentMetrics.SleepMinutes), float64(previousMetrics.SleepMinutes)),
		},
		"suggestions": []string{
			"Use the month view to compare weekday patterns and spot routine drift.",
			"Keep start/end timestamps complete to improve monthly averages.",
		},
		"labels": []string{"record_based"},
	})
}

func (a *App) computeWeeklyMetrics(c *gin.Context, babyID string, start, end time.Time) (weeklyMetrics, error) {
	rows, err := a.db.Query(
		c.Request.Context(),
		`SELECT type, "startTime", "endTime", "valueJson"
		 FROM "Event"
		 WHERE "babyId" = $1
		   AND "startTime" >= $2
		   AND "startTime" < $3
		   AND NOT (
		     "endTime" IS NULL
		     AND (
		       COALESCE("metadataJson"->>'event_state', '') = 'OPEN'
		       OR COALESCE("metadataJson"->>'entry_mode', '') = 'manual_start'
		     )
		   )
		   AND COALESCE("metadataJson"->>'event_state', 'CLOSED') <> 'CANCELED'`,
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
