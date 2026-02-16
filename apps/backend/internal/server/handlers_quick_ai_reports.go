package server

import (
	"errors"
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
