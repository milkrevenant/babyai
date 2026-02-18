package server

import (
	"encoding/json"
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

func formatLocalTimeRFC3339(value *time.Time, location *time.Location) *string {
	if value == nil {
		return nil
	}
	loc := location
	if loc == nil {
		loc = time.UTC
	}
	formatted := value.In(loc).Format(time.RFC3339)
	return &formatted
}

func stringPointer(value string) *string {
	copied := value
	return &copied
}

func parseNumericValue(raw any) (float64, bool) {
	switch value := raw.(type) {
	case float64:
		return value, true
	case float32:
		return float64(value), true
	case int:
		return float64(value), true
	case int64:
		return float64(value), true
	case json.Number:
		parsed, err := value.Float64()
		if err == nil {
			return parsed, true
		}
	case string:
		parsed, err := strconv.ParseFloat(strings.TrimSpace(value), 64)
		if err == nil {
			return parsed, true
		}
	}
	return 0, false
}

func extractOptionalNumberFromMap(data map[string]any, keys ...string) *float64 {
	if data == nil {
		return nil
	}
	for _, key := range keys {
		raw, ok := data[key]
		if !ok {
			continue
		}
		parsed, ok := parseNumericValue(raw)
		if !ok {
			continue
		}
		return &parsed
	}
	return nil
}

func extractConfidenceScore(valueMap map[string]any, metadataMap map[string]any) *float64 {
	candidates := []map[string]any{metadataMap, valueMap}
	for _, candidate := range candidates {
		if score := extractOptionalNumberFromMap(candidate, "confidence", "confidence_score"); score != nil {
			return score
		}
		if candidate == nil {
			continue
		}
		if nested, ok := candidate["confidence"].(map[string]any); ok {
			if score := extractOptionalNumberFromMap(nested, "overall", "score", "value"); score != nil {
				return score
			}
		}
	}
	return nil
}

func extractDurationMinutes(valueMap map[string]any, startTime time.Time, endTime *time.Time) *float64 {
	if fromPayload := extractOptionalNumberFromMap(valueMap, "duration_min", "duration_minutes", "minutes", "duration"); fromPayload != nil {
		return fromPayload
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

func quickSnapshotNoData(referenceText string, message string) gin.H {
	return gin.H{
		"timestamp":      nil,
		"local_time":     nil,
		"amount_ml":      nil,
		"duration_min":   nil,
		"type":           nil,
		"confidence":     nil,
		"reference_text": referenceText,
		"message":        message,
	}
}

func (a *App) quickLastFeeding(c *gin.Context) {
	user, ok := authUserFromContext(c)
	if !ok {
		writeError(c, http.StatusUnauthorized, "Unauthorized")
		return
	}
	babyID := c.Query("baby_id")
	tone := strings.TrimSpace(c.DefaultQuery("tone", "neutral"))
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

	var eventType string
	var startedAt time.Time
	var endedAt *time.Time
	var valueRaw []byte
	var metadataRaw []byte
	err = a.db.QueryRow(
		c.Request.Context(),
		`SELECT type, "startTime", "endTime", "valueJson", "metadataJson"
		 FROM "Event"
		 WHERE "babyId" = $1 AND status = 'CLOSED' AND type IN ('FORMULA', 'BREASTFEED')
		 ORDER BY "startTime" DESC
		 LIMIT 1`,
		baby.ID,
	).Scan(&eventType, &startedAt, &endedAt, &valueRaw, &metadataRaw)
	if errors.Is(err, pgx.ErrNoRows) {
		c.JSON(http.StatusOK, quickSnapshotNoData(
			"No confirmed feeding events are stored yet.",
			"No feeding records yet. Add one and I can answer immediately.",
		))
		return
	}
	if err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to load feeding events")
		return
	}

	startedUTC := startedAt.UTC()
	valueMap := parseJSONStringMap(valueRaw)
	metadataMap := parseJSONStringMap(metadataRaw)
	amountML := extractOptionalNumberFromMap(valueMap, "amount_ml", "ml", "volume_ml")
	durationMin := extractDurationMinutes(valueMap, startedUTC, endedAt)
	eventTypeValue := strings.ToUpper(strings.TrimSpace(eventType))

	c.JSON(http.StatusOK, gin.H{
		"timestamp":      formatNullableTimeRFC3339(&startedUTC),
		"local_time":     formatLocalTimeRFC3339(&startedUTC, localZone),
		"amount_ml":      amountML,
		"duration_min":   durationMin,
		"type":           stringPointer(eventTypeValue),
		"confidence":     extractConfidenceScore(valueMap, metadataMap),
		"reference_text": "Latest confirmed feeding event (FORMULA or BREASTFEED).",
		"message": toneWrap(
			tone,
			"Latest feeding ("+strings.ToLower(eventTypeValue)+") was logged at "+startedUTC.Format("15:04")+" UTC.",
			"The most recent feeding event type is "+eventTypeValue+" at "+startedUTC.Format("15:04")+" UTC.",
			"Last feeding: "+eventTypeValue+" at "+startedUTC.Format("15:04")+" UTC.",
		),
	})
}

func (a *App) quickRecentSleep(c *gin.Context) {
	user, ok := authUserFromContext(c)
	if !ok {
		writeError(c, http.StatusUnauthorized, "Unauthorized")
		return
	}
	babyID := c.Query("baby_id")
	tone := strings.TrimSpace(c.DefaultQuery("tone", "neutral"))
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

	var startedAt time.Time
	var endedAt *time.Time
	var valueRaw []byte
	var metadataRaw []byte
	err = a.db.QueryRow(
		c.Request.Context(),
		`SELECT "startTime", "endTime", "valueJson", "metadataJson"
		 FROM "Event"
		 WHERE "babyId" = $1 AND status = 'CLOSED' AND type = 'SLEEP'
		 ORDER BY "startTime" DESC
		 LIMIT 1`,
		baby.ID,
	).Scan(&startedAt, &endedAt, &valueRaw, &metadataRaw)
	if errors.Is(err, pgx.ErrNoRows) {
		c.JSON(http.StatusOK, quickSnapshotNoData(
			"No confirmed sleep events are stored yet.",
			"No sleep records yet. Add one and I can summarize sleep timing.",
		))
		return
	}
	if err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to load sleep events")
		return
	}

	startedUTC := startedAt.UTC()
	valueMap := parseJSONStringMap(valueRaw)
	metadataMap := parseJSONStringMap(metadataRaw)

	c.JSON(http.StatusOK, gin.H{
		"timestamp":      formatNullableTimeRFC3339(&startedUTC),
		"local_time":     formatLocalTimeRFC3339(&startedUTC, localZone),
		"amount_ml":      nil,
		"duration_min":   extractDurationMinutes(valueMap, startedUTC, endedAt),
		"type":           stringPointer("SLEEP"),
		"confidence":     extractConfidenceScore(valueMap, metadataMap),
		"reference_text": "Latest confirmed sleep event for this baby.",
		"message": toneWrap(
			tone,
			"Most recent sleep was logged at "+startedUTC.Format("15:04")+" UTC.",
			"The latest recorded sleep event time is "+startedUTC.Format("15:04")+" UTC.",
			"Recent sleep: "+startedUTC.Format("15:04")+" UTC.",
		),
	})
}

func (a *App) quickLastDiaper(c *gin.Context) {
	user, ok := authUserFromContext(c)
	if !ok {
		writeError(c, http.StatusUnauthorized, "Unauthorized")
		return
	}
	babyID := c.Query("baby_id")
	tone := strings.TrimSpace(c.DefaultQuery("tone", "neutral"))
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

	var eventType string
	var startedAt time.Time
	var valueRaw []byte
	var metadataRaw []byte
	err = a.db.QueryRow(
		c.Request.Context(),
		`SELECT type, "startTime", "valueJson", "metadataJson"
		 FROM "Event"
		 WHERE "babyId" = $1 AND status = 'CLOSED' AND type IN ('PEE', 'POO')
		 ORDER BY "startTime" DESC
		 LIMIT 1`,
		baby.ID,
	).Scan(&eventType, &startedAt, &valueRaw, &metadataRaw)
	if errors.Is(err, pgx.ErrNoRows) {
		c.JSON(http.StatusOK, quickSnapshotNoData(
			"No confirmed diaper events are stored yet.",
			"No diaper records yet. Add one and I can answer immediately.",
		))
		return
	}
	if err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to load diaper events")
		return
	}

	startedUTC := startedAt.UTC()
	valueMap := parseJSONStringMap(valueRaw)
	metadataMap := parseJSONStringMap(metadataRaw)
	eventTypeValue := strings.ToUpper(strings.TrimSpace(eventType))

	c.JSON(http.StatusOK, gin.H{
		"timestamp":      formatNullableTimeRFC3339(&startedUTC),
		"local_time":     formatLocalTimeRFC3339(&startedUTC, localZone),
		"amount_ml":      nil,
		"duration_min":   nil,
		"type":           stringPointer(eventTypeValue),
		"confidence":     extractConfidenceScore(valueMap, metadataMap),
		"reference_text": "Latest confirmed diaper event (PEE or POO).",
		"message": toneWrap(
			tone,
			"Latest diaper event ("+strings.ToLower(eventTypeValue)+") was logged at "+startedUTC.Format("15:04")+" UTC.",
			"The most recent diaper event type is "+eventTypeValue+" at "+startedUTC.Format("15:04")+" UTC.",
			"Last diaper: "+eventTypeValue+" at "+startedUTC.Format("15:04")+" UTC.",
		),
	})
}

func (a *App) quickLastMedication(c *gin.Context) {
	user, ok := authUserFromContext(c)
	if !ok {
		writeError(c, http.StatusUnauthorized, "Unauthorized")
		return
	}
	babyID := c.Query("baby_id")
	tone := strings.TrimSpace(c.DefaultQuery("tone", "neutral"))
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

	var startedAt time.Time
	var endedAt *time.Time
	var valueRaw []byte
	var metadataRaw []byte
	err = a.db.QueryRow(
		c.Request.Context(),
		`SELECT "startTime", "endTime", "valueJson", "metadataJson"
		 FROM "Event"
		 WHERE "babyId" = $1 AND status = 'CLOSED' AND type = 'MEDICATION'
		 ORDER BY "startTime" DESC
		 LIMIT 1`,
		baby.ID,
	).Scan(&startedAt, &endedAt, &valueRaw, &metadataRaw)
	if errors.Is(err, pgx.ErrNoRows) {
		c.JSON(http.StatusOK, quickSnapshotNoData(
			"No confirmed medication events are stored yet.",
			"No medication records yet. Add one and I can answer immediately.",
		))
		return
	}
	if err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to load medication events")
		return
	}

	startedUTC := startedAt.UTC()
	valueMap := parseJSONStringMap(valueRaw)
	metadataMap := parseJSONStringMap(metadataRaw)

	c.JSON(http.StatusOK, gin.H{
		"timestamp":      formatNullableTimeRFC3339(&startedUTC),
		"local_time":     formatLocalTimeRFC3339(&startedUTC, localZone),
		"amount_ml":      nil,
		"duration_min":   extractDurationMinutes(valueMap, startedUTC, endedAt),
		"type":           stringPointer("MEDICATION"),
		"confidence":     extractConfidenceScore(valueMap, metadataMap),
		"reference_text": "Latest confirmed medication event for this baby.",
		"message": toneWrap(
			tone,
			"Latest medication event was logged at "+startedUTC.Format("15:04")+" UTC.",
			"The latest recorded medication event time is "+startedUTC.Format("15:04")+" UTC.",
			"Last medication: "+startedUTC.Format("15:04")+" UTC.",
		),
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
		 WHERE "babyId" = $1 AND status = 'CLOSED' AND type = 'POO'
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
		 WHERE "babyId" = $1 AND status = 'CLOSED' AND type IN ('FORMULA', 'BREASTFEED')
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
		 WHERE "babyId" = $1 AND status = 'CLOSED' AND "startTime" >= $2 AND "startTime" < $3`,
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
	localStart, localEnd, rangeDays, rangeLabel, err := quickRangeWindow(localNow, rangeKey)
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
		   AND status = 'CLOSED'
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
	var lastWeaningTime *time.Time
	medicationCount := 0
	var lastMedicationTime *time.Time
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
			}

		case "MEMO":
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
		   AND status = 'OPEN'
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
		value := parseJSONStringMap(valueRaw)
		metadata := parseJSONStringMap(metadataRaw)
		switch eventType {
		case "FORMULA":
			if openFormulaEventID == nil {
				eventIDCopy := eventID
				startCopy := startTime.UTC()
				openFormulaEventID = &eventIDCopy
				openFormulaStartTime = &startCopy
				openFormulaValue = value
				memoText := extractMemoText(value)
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
				openBreastfeedValue = value
				memoText := extractMemoText(value)
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
				openSleepValue = value
				memoText := extractMemoText(value)
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
				openDiaperValue = value
				memoText := extractMemoText(value)
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
				openMedicationValue = value
				memoText := extractMemoText(value)
				if memoText != "" {
					openMedicationMemo = &memoText
				}
			}
		case "MEMO":
			if !isWeaningMemo(value, metadata) {
				continue
			}
			if openWeaningEventID == nil {
				eventIDCopy := eventID
				startCopy := startTime.UTC()
				openWeaningEventID = &eventIDCopy
				openWeaningStartTime = &startCopy
				openWeaningValue = value
				memoText := extractMemoText(value)
				if memoText != "" {
					openWeaningMemo = &memoText
				}
			}
		}
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

	rangeEndDate := localEnd.Add(-24 * time.Hour).Format("2006-01-02")
	if rangeEndDate < localStart.Format("2006-01-02") {
		rangeEndDate = localStart.Format("2006-01-02")
	}

	c.JSON(http.StatusOK, gin.H{
		"date":                            localNow.Format("2006-01-02"),
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
		"feeding_graph_mode":              graphMode,
		"feeding_graph_labels":            graphLabels,
		"feeding_graph_points":            graphPoints,
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

func quickRangeWindow(localNow time.Time, rangeKey string) (time.Time, time.Time, int, string, error) {
	location := localNow.Location()
	year, month, day := localNow.Date()
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

func quickAvgPerDay(total int, days int) float64 {
	if days <= 0 {
		return 0
	}
	return math.Round((float64(total)/float64(days))*10) / 10
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

func containsAnyKeyword(text string, keywords []string) bool {
	for _, keyword := range keywords {
		if strings.Contains(text, keyword) {
			return true
		}
	}
	return false
}

func aiQuestionSignals(question string) map[string]bool {
	return map[string]bool{
		"asksLast": containsAnyKeyword(question, []string{
			"last", "latest", "recent", "마지막", "최근", "최신",
		}),
		"asksPoo": containsAnyKeyword(question, []string{
			"poo", "poop", "stool", "대변", "응가", "똥",
		}),
		"asksFeed": containsAnyKeyword(question, []string{
			"feeding", "feed", "formula", "breastfeed", "수유", "분유", "모유",
		}),
		"asksSleep": containsAnyKeyword(question, []string{
			"sleep", "nap", "수면", "잠",
		}),
		"asksDiaper": containsAnyKeyword(question, []string{
			"diaper", "pee", "poo", "poop", "기저귀", "소변", "대변",
		}),
		"asksMedication": containsAnyKeyword(question, []string{
			"medication", "medicine", "dose", "투약", "약", "복용",
		}),
		"asksTodaySummary": containsAnyKeyword(question, []string{
			"today summary", "daily summary", "today", "오늘 요약", "오늘", "요약",
		}),
		"asksNextEta": containsAnyKeyword(question, []string{
			"eta", "next", "when", "다음", "언제", "예정",
		}),
	}
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

	signals := aiQuestionSignals(question)

	if payload.UsePersonalData && signals["asksTodaySummary"] {
		start := startOfUTCDay(time.Now().UTC())
		end := start.Add(24 * time.Hour)
		rows, err := a.db.Query(
			c.Request.Context(),
			`SELECT type, "startTime", "endTime", "valueJson"
			 FROM "Event"
			 WHERE "babyId" = $1 AND status = 'CLOSED' AND "startTime" >= $2 AND "startTime" < $3`,
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

		answer := "Today's summary: feedings " + strconv.Itoa(counts["FORMULA"]+counts["BREASTFEED"]) +
			", formula " + strconv.Itoa(int(formulaTotal)) + " ml, sleep " + strconv.Itoa(sleepMinutes) +
			" min, diaper pee " + strconv.Itoa(counts["PEE"]) + ", poo " + strconv.Itoa(counts["POO"]) + "."
		c.JSON(http.StatusOK, gin.H{
			"answer":            answer,
			"labels":            labels,
			"tone":              payload.Tone,
			"use_personal_data": payload.UsePersonalData,
		})
		return
	}

	if payload.UsePersonalData && signals["asksFeed"] && signals["asksLast"] && !signals["asksNextEta"] {
		var eventType string
		var startedAt time.Time
		var valueRaw []byte
		err := a.db.QueryRow(
			c.Request.Context(),
			`SELECT type, "startTime", "valueJson"
			 FROM "Event"
			 WHERE "babyId" = $1 AND status = 'CLOSED' AND type IN ('FORMULA', 'BREASTFEED')
			 ORDER BY "startTime" DESC LIMIT 1`,
			baby.ID,
		).Scan(&eventType, &startedAt, &valueRaw)
		if errors.Is(err, pgx.ErrNoRows) {
			c.JSON(http.StatusOK, gin.H{
				"answer":            "No feeding records found yet.",
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
		valueMap := parseJSONStringMap(valueRaw)
		amountML := extractOptionalNumberFromMap(valueMap, "ml", "amount_ml", "volume_ml")
		answer := "Latest feeding event is " + strings.ToUpper(eventType) + " at " + startedAt.UTC().Format(time.RFC3339) + "."
		if amountML != nil {
			answer += " Amount: " + strconv.Itoa(int(*amountML+0.5)) + " ml."
		}
		c.JSON(http.StatusOK, gin.H{
			"answer":            answer,
			"labels":            labels,
			"tone":              payload.Tone,
			"use_personal_data": payload.UsePersonalData,
		})
		return
	}

	if payload.UsePersonalData && signals["asksSleep"] && signals["asksLast"] {
		var startedAt time.Time
		var endedAt *time.Time
		var valueRaw []byte
		err := a.db.QueryRow(
			c.Request.Context(),
			`SELECT "startTime", "endTime", "valueJson"
			 FROM "Event"
			 WHERE "babyId" = $1 AND status = 'CLOSED' AND type = 'SLEEP'
			 ORDER BY "startTime" DESC LIMIT 1`,
			baby.ID,
		).Scan(&startedAt, &endedAt, &valueRaw)
		if errors.Is(err, pgx.ErrNoRows) {
			c.JSON(http.StatusOK, gin.H{
				"answer":            "No sleep records found yet.",
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
		valueMap := parseJSONStringMap(valueRaw)
		duration := extractDurationMinutes(valueMap, startedAt.UTC(), endedAt)
		answer := "Latest sleep event started at " + startedAt.UTC().Format(time.RFC3339) + "."
		if duration != nil {
			answer += " Duration: " + strconv.Itoa(int(*duration+0.5)) + " minutes."
		}
		c.JSON(http.StatusOK, gin.H{
			"answer":            answer,
			"labels":            labels,
			"tone":              payload.Tone,
			"use_personal_data": payload.UsePersonalData,
		})
		return
	}

	if payload.UsePersonalData && signals["asksDiaper"] && signals["asksLast"] && !signals["asksPoo"] {
		var eventType string
		var startedAt time.Time
		err := a.db.QueryRow(
			c.Request.Context(),
			`SELECT type, "startTime"
			 FROM "Event"
			 WHERE "babyId" = $1 AND status = 'CLOSED' AND type IN ('PEE', 'POO')
			 ORDER BY "startTime" DESC LIMIT 1`,
			baby.ID,
		).Scan(&eventType, &startedAt)
		if errors.Is(err, pgx.ErrNoRows) {
			c.JSON(http.StatusOK, gin.H{
				"answer":            "No diaper records found yet.",
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
			"answer":            "Latest diaper event is " + strings.ToUpper(eventType) + " at " + startedAt.UTC().Format(time.RFC3339) + ".",
			"labels":            labels,
			"tone":              payload.Tone,
			"use_personal_data": payload.UsePersonalData,
		})
		return
	}

	if payload.UsePersonalData && signals["asksMedication"] && signals["asksLast"] {
		var startedAt time.Time
		var endedAt *time.Time
		var valueRaw []byte
		err := a.db.QueryRow(
			c.Request.Context(),
			`SELECT "startTime", "endTime", "valueJson"
			 FROM "Event"
			 WHERE "babyId" = $1 AND status = 'CLOSED' AND type = 'MEDICATION'
			 ORDER BY "startTime" DESC LIMIT 1`,
			baby.ID,
		).Scan(&startedAt, &endedAt, &valueRaw)
		if errors.Is(err, pgx.ErrNoRows) {
			c.JSON(http.StatusOK, gin.H{
				"answer":            "No medication records found yet.",
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
		valueMap := parseJSONStringMap(valueRaw)
		duration := extractDurationMinutes(valueMap, startedAt.UTC(), endedAt)
		answer := "Latest medication event is at " + startedAt.UTC().Format(time.RFC3339) + "."
		if duration != nil {
			answer += " Duration: " + strconv.Itoa(int(*duration+0.5)) + " minutes."
		}
		c.JSON(http.StatusOK, gin.H{
			"answer":            answer,
			"labels":            labels,
			"tone":              payload.Tone,
			"use_personal_data": payload.UsePersonalData,
		})
		return
	}

	if payload.UsePersonalData && (signals["asksPoo"] || (signals["asksDiaper"] && signals["asksLast"])) {
		var last time.Time
		err := a.db.QueryRow(
			c.Request.Context(),
			`SELECT "startTime" FROM "Event"
			 WHERE "babyId" = $1 AND status = 'CLOSED' AND type = 'POO'
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

	if payload.UsePersonalData && (signals["asksFeed"] || signals["asksNextEta"]) {
		rows, err := a.db.Query(
			c.Request.Context(),
			`SELECT "startTime" FROM "Event"
			 WHERE "babyId" = $1 AND status = 'CLOSED' AND type IN ('FORMULA', 'BREASTFEED')
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
		lastFeedingTime, latestErr := a.latestFeedingTime(c.Request.Context(), baby.ID)
		if latestErr != nil {
			writeError(c, http.StatusInternalServerError, "Failed to load latest feeding event")
			return
		}
		profile, _, profileErr := a.resolveBabyProfile(c.Request.Context(), user.ID, baby.ID, readRoles)
		if profileErr != nil {
			writeError(c, http.StatusInternalServerError, "Failed to resolve baby profile")
			return
		}
		recommendation := calculateFeedingRecommendation(profile, lastFeedingTime, time.Now().UTC())

		answer := "Need at least two feeding logs to estimate next feeding."
		if result.ETAMinutes != nil {
			answer = "Estimated next feeding in about " + strconv.Itoa(*result.ETAMinutes) + " minutes."
		}
		if recommendation.RecommendedFormulaPerFeedML != nil {
			intervalH := recommendation.RecommendedIntervalMin / 60
			intervalM := recommendation.RecommendedIntervalMin % 60
			answer += " Suggested profile-based plan: about " +
				strconv.Itoa(*recommendation.RecommendedFormulaPerFeedML) +
				" ml every " + strconv.Itoa(intervalH) + "h " + strconv.Itoa(intervalM) + "m."
		}
		if display := formulaDisplayName(profile); display != "" {
			answer += " Formula profile: " + display + "."
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
		"answer":            "I can answer about last feeding, recent sleep, diaper timing, medication timing, feeding ETA, and daily summaries once logs are available.",
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
		 WHERE "babyId" = $1 AND status = 'CLOSED' AND "startTime" >= $2 AND "startTime" < $3`,
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
		 WHERE "babyId" = $1 AND status = 'CLOSED' AND "startTime" >= $2 AND "startTime" < $3`,
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
