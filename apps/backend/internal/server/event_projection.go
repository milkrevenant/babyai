package server

import (
	"context"
	"math"
	"sort"
	"strings"
	"time"

	"github.com/google/uuid"
)

func sleepTypeFromRule(start time.Time, end *time.Time) string {
	hour := start.UTC().Hour()
	if hour >= 18 || hour < 6 {
		return "night"
	}
	if end != nil {
		durationHours := end.UTC().Sub(start.UTC()).Hours()
		if durationHours >= 4 {
			return "unknown"
		}
	}
	return "nap"
}

func (a *App) projectEventToPRDTables(
	ctx context.Context,
	q dbQuerier,
	childID string,
	eventType string,
	startAt time.Time,
	endAt *time.Time,
	value map[string]any,
) error {
	if value == nil {
		value = map[string]any{}
	}

	startUTC := startAt.UTC()
	var endRef any
	if endAt == nil {
		endRef = nil
	} else {
		endUTC := endAt.UTC()
		endRef = endUTC
	}

	switch strings.ToUpper(strings.TrimSpace(eventType)) {
	case "SLEEP":
		if err := a.closeOpenSleepEvents(ctx, q, childID, startUTC); err != nil {
			return err
		}
		sleepType := sleepTypeFromRule(startUTC, endAt)
		_, err := q.Exec(
			ctx,
			`INSERT INTO "SleepEvent" (
				id, "childId", "startAt", "endAt", note,
				"endIsEstimated", "estimationMethod", "estimationConfidence",
				"sleepType", "sleepTypeSource", "qualityScore", "wakeCount",
				"createdAt", "updatedAt"
			) VALUES ($1, $2, $3, $4, NULL, FALSE, NULL, NULL, $5, 'auto', NULL, NULL, NOW(), NOW())`,
			uuid.NewString(),
			childID,
			startUTC,
			endRef,
			sleepType,
		)
		return err

	case "FORMULA", "BREASTFEED":
		if err := a.closeOpenIntakeEvents(ctx, q, childID, strings.ToLower(eventType), startUTC); err != nil {
			return err
		}
		intakeType := strings.ToLower(eventType)
		var amountML any
		ml := int(math.Round(extractNumberFromMap(value, "ml", "amount_ml", "volume_ml")))
		if ml > 0 {
			amountML = ml
		} else {
			amountML = nil
		}
		amountText := strings.TrimSpace(toString(value["amount_text"]))
		if amountText == "" {
			amountText = strings.TrimSpace(toString(value["amount"]))
		}
		var amountTextRef any
		if amountText == "" {
			amountTextRef = nil
		} else {
			amountTextRef = amountText
		}
		side := strings.ToLower(strings.TrimSpace(toString(value["side"])))
		var sideRef any
		if side == "" {
			sideRef = nil
		} else {
			sideRef = side
		}

		_, err := q.Exec(
			ctx,
			`INSERT INTO "IntakeEvent" (
				id, "childId", "startAt", "endAt", note,
				"endIsEstimated", "estimationMethod", "estimationConfidence",
				"intakeType", "amountMl", "amountText", side,
				"createdAt", "updatedAt"
			) VALUES ($1, $2, $3, $4, NULL, FALSE, NULL, NULL, $5, $6, $7, $8, NOW(), NOW())`,
			uuid.NewString(),
			childID,
			startUTC,
			endRef,
			intakeType,
			amountML,
			amountTextRef,
			sideRef,
		)
		return err

	case "SYMPTOM":
		tempC := extractNumberFromMap(value, "temp_c", "temperature_c", "temp")
		if tempC <= 0 {
			return nil
		}
		method := strings.ToLower(strings.TrimSpace(toString(value["method"])))
		methodSource := "user"
		if method == "" {
			method = "ear"
			methodSource = "default"
		}
		_, err := q.Exec(
			ctx,
			`INSERT INTO "TemperatureEvent" (
				id, "childId", "measuredAt", "tempC", method, "methodSource", note, "createdAt", "updatedAt"
			) VALUES ($1, $2, $3, $4, $5, $6, NULL, NOW(), NOW())`,
			uuid.NewString(),
			childID,
			startUTC,
			tempC,
			method,
			methodSource,
		)
		return err

	case "PEE", "POO":
		pee := strings.ToUpper(eventType) == "PEE"
		poo := strings.ToUpper(eventType) == "POO"
		pooType := strings.ToLower(strings.TrimSpace(toString(value["poo_type"])))
		color := strings.ToLower(strings.TrimSpace(toString(value["color"])))
		texture := strings.ToLower(strings.TrimSpace(toString(value["texture"])))
		var pooTypeRef, colorRef, textureRef any
		if pooType != "" {
			pooTypeRef = pooType
		}
		if color != "" {
			colorRef = color
		}
		if texture != "" {
			textureRef = texture
		}
		_, err := q.Exec(
			ctx,
			`INSERT INTO "DiaperEvent" (
				id, "childId", at, pee, poo, "pooType", color, texture, note, "createdAt", "updatedAt"
			) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, NULL, NOW(), NOW())`,
			uuid.NewString(),
			childID,
			startUTC,
			pee,
			poo,
			pooTypeRef,
			colorRef,
			textureRef,
		)
		return err

	case "MEDICATION":
		medName := strings.TrimSpace(toString(value["name"]))
		if medName == "" {
			medName = strings.TrimSpace(toString(value["med_name"]))
		}
		if medName == "" {
			medName = "unspecified"
		}
		doseText := strings.TrimSpace(toString(value["dose_text"]))
		if doseText == "" {
			doseText = strings.TrimSpace(toString(value["dose"]))
		}
		route := strings.ToLower(strings.TrimSpace(toString(value["route"])))
		isPrescribed, hasPrescribed := toBool(value["is_prescribed"])
		var doseRef, routeRef, prescribedRef any
		if doseText != "" {
			doseRef = doseText
		}
		if route != "" {
			routeRef = route
		}
		if hasPrescribed {
			prescribedRef = isPrescribed
		}
		_, err := q.Exec(
			ctx,
			`INSERT INTO "MedicationEvent" (
				id, "childId", at, "medName", "doseText", route, "isPrescribed", note, "createdAt", "updatedAt"
			) VALUES ($1, $2, $3, $4, $5, $6, $7, NULL, NOW(), NOW())`,
			uuid.NewString(),
			childID,
			startUTC,
			medName,
			doseRef,
			routeRef,
			prescribedRef,
		)
		return err

	case "MEMO":
		content := strings.TrimSpace(toString(value["memo"]))
		if content == "" {
			content = strings.TrimSpace(toString(value["note"]))
		}
		if content == "" {
			content = strings.TrimSpace(toString(value["text"]))
		}
		if content == "" {
			content = "memo"
		}
		_, err := q.Exec(
			ctx,
			`INSERT INTO "NoteEvent" (
				id, "childId", at, content, "tagsJson", "createdAt", "updatedAt"
			) VALUES ($1, $2, $3, $4, NULL, NOW(), NOW())`,
			uuid.NewString(),
			childID,
			startUTC,
			content,
		)
		return err
	}

	return nil
}

func (a *App) closeOpenSleepEvents(ctx context.Context, q dbQuerier, childID string, nextStart time.Time) error {
	rows, err := q.Query(
		ctx,
		`SELECT id, "startAt", "sleepType"
		 FROM "SleepEvent"
		 WHERE "childId" = $1
		   AND "endAt" IS NULL
		   AND "startAt" < $2
		 ORDER BY "startAt" ASC`,
		childID,
		nextStart,
	)
	if err != nil {
		return err
	}

	type openSleepEvent struct {
		id        string
		startAt   time.Time
		sleepType string
	}
	openEvents := make([]openSleepEvent, 0)
	for rows.Next() {
		event := openSleepEvent{}
		if err := rows.Scan(&event.id, &event.startAt, &event.sleepType); err != nil {
			rows.Close()
			return err
		}
		openEvents = append(openEvents, event)
	}
	if err := rows.Err(); err != nil {
		rows.Close()
		return err
	}
	rows.Close()

	for _, event := range openEvents {
		durationMin, method, confidence, err := a.estimateSleepDurationMinutes(ctx, q, childID, event.sleepType)
		if err != nil {
			return err
		}
		estimatedEnd := event.startAt.UTC().Add(time.Duration(durationMin) * time.Minute)
		if estimatedEnd.After(nextStart.UTC()) {
			estimatedEnd = nextStart.UTC()
		}
		if !estimatedEnd.After(event.startAt.UTC()) {
			estimatedEnd = event.startAt.UTC().Add(1 * time.Minute)
		}
		if _, err := q.Exec(
			ctx,
			`UPDATE "SleepEvent"
			 SET "endAt" = $2,
			     "endIsEstimated" = TRUE,
			     "estimationMethod" = $3,
			     "estimationConfidence" = $4,
			     "updatedAt" = NOW()
			 WHERE id = $1`,
			event.id,
			estimatedEnd,
			method,
			confidence,
		); err != nil {
			return err
		}
	}
	return nil
}

func (a *App) closeOpenIntakeEvents(ctx context.Context, q dbQuerier, childID, intakeType string, nextStart time.Time) error {
	rows, err := q.Query(
		ctx,
		`SELECT id, "startAt"
		 FROM "IntakeEvent"
		 WHERE "childId" = $1
		   AND "intakeType" = $2
		   AND "endAt" IS NULL
		   AND "startAt" < $3
		 ORDER BY "startAt" ASC`,
		childID,
		intakeType,
		nextStart,
	)
	if err != nil {
		return err
	}

	type openIntakeEvent struct {
		id      string
		startAt time.Time
	}
	openEvents := make([]openIntakeEvent, 0)
	for rows.Next() {
		event := openIntakeEvent{}
		if err := rows.Scan(&event.id, &event.startAt); err != nil {
			rows.Close()
			return err
		}
		openEvents = append(openEvents, event)
	}
	if err := rows.Err(); err != nil {
		rows.Close()
		return err
	}
	rows.Close()

	for _, event := range openEvents {
		durationMin, method, confidence, err := a.estimateIntakeDurationMinutes(ctx, q, childID, intakeType)
		if err != nil {
			return err
		}
		estimatedEnd := event.startAt.UTC().Add(time.Duration(durationMin) * time.Minute)
		if estimatedEnd.After(nextStart.UTC()) {
			estimatedEnd = nextStart.UTC()
		}
		if !estimatedEnd.After(event.startAt.UTC()) {
			estimatedEnd = event.startAt.UTC().Add(1 * time.Minute)
		}
		if _, err := q.Exec(
			ctx,
			`UPDATE "IntakeEvent"
			 SET "endAt" = $2,
			     "endIsEstimated" = TRUE,
			     "estimationMethod" = $3,
			     "estimationConfidence" = $4,
			     "updatedAt" = NOW()
			 WHERE id = $1`,
			event.id,
			estimatedEnd,
			method,
			confidence,
		); err != nil {
			return err
		}
	}
	return nil
}

func (a *App) estimateSleepDurationMinutes(ctx context.Context, q dbQuerier, childID, sleepType string) (int, string, int, error) {
	median14, err := loadSleepMedianMinutes(ctx, q, childID, sleepType, 14)
	if err != nil {
		return 0, "", 0, err
	}
	if median14 > 0 {
		return clampSleepDuration(sleepType, median14), "avg_duration_last_14d", 80, nil
	}

	median7, err := loadSleepMedianMinutes(ctx, q, childID, sleepType, 7)
	if err != nil {
		return 0, "", 0, err
	}
	if median7 > 0 {
		return clampSleepDuration(sleepType, median7), "avg_duration_last_7d", 70, nil
	}

	switch sleepType {
	case "night":
		return 480, "fallback_default_8h", 50, nil
	case "nap":
		return 45, "fallback_default_45m", 50, nil
	default:
		return 120, "fallback_default_2h", 45, nil
	}
}

func (a *App) estimateIntakeDurationMinutes(ctx context.Context, q dbQuerier, childID, intakeType string) (int, string, int, error) {
	median14, err := loadIntakeMedianMinutes(ctx, q, childID, intakeType, 14)
	if err != nil {
		return 0, "", 0, err
	}
	if median14 > 0 {
		return clampIntakeDuration(median14), "avg_duration_last_14d", 80, nil
	}

	median7, err := loadIntakeMedianMinutes(ctx, q, childID, intakeType, 7)
	if err != nil {
		return 0, "", 0, err
	}
	if median7 > 0 {
		return clampIntakeDuration(median7), "avg_duration_last_7d", 70, nil
	}

	return 15, "fallback_default_15m", 50, nil
}

func loadSleepMedianMinutes(ctx context.Context, q dbQuerier, childID, sleepType string, days int) (int, error) {
	rows, err := q.Query(
		ctx,
		`SELECT EXTRACT(EPOCH FROM ("endAt" - "startAt")) / 60.0
		 FROM "SleepEvent"
		 WHERE "childId" = $1
		   AND "sleepType" = $2
		   AND "startAt" >= NOW() - ($3 * INTERVAL '1 day')
		   AND "endAt" IS NOT NULL`,
		childID,
		sleepType,
		days,
	)
	if err != nil {
		return 0, err
	}
	defer rows.Close()

	values := make([]int, 0)
	for rows.Next() {
		var minutes float64
		if err := rows.Scan(&minutes); err != nil {
			return 0, err
		}
		if minutes > 0 {
			values = append(values, int(math.Round(minutes)))
		}
	}
	if len(values) == 0 {
		return 0, nil
	}
	sort.Ints(values)
	middle := len(values) / 2
	if len(values)%2 == 1 {
		return values[middle], nil
	}
	return int(math.Round(float64(values[middle-1]+values[middle]) / 2.0)), nil
}

func loadIntakeMedianMinutes(ctx context.Context, q dbQuerier, childID, intakeType string, days int) (int, error) {
	rows, err := q.Query(
		ctx,
		`SELECT EXTRACT(EPOCH FROM ("endAt" - "startAt")) / 60.0
		 FROM "IntakeEvent"
		 WHERE "childId" = $1
		   AND "intakeType" = $2
		   AND "startAt" >= NOW() - ($3 * INTERVAL '1 day')
		   AND "endAt" IS NOT NULL`,
		childID,
		intakeType,
		days,
	)
	if err != nil {
		return 0, err
	}
	defer rows.Close()

	values := make([]int, 0)
	for rows.Next() {
		var minutes float64
		if err := rows.Scan(&minutes); err != nil {
			return 0, err
		}
		if minutes > 0 {
			values = append(values, int(math.Round(minutes)))
		}
	}
	if len(values) == 0 {
		return 0, nil
	}
	sort.Ints(values)
	middle := len(values) / 2
	if len(values)%2 == 1 {
		return values[middle], nil
	}
	return int(math.Round(float64(values[middle-1]+values[middle]) / 2.0)), nil
}

func clampSleepDuration(sleepType string, durationMin int) int {
	switch sleepType {
	case "night":
		if durationMin < 120 {
			return 120
		}
		if durationMin > 840 {
			return 840
		}
		return durationMin
	case "nap":
		if durationMin < 10 {
			return 10
		}
		if durationMin > 180 {
			return 180
		}
		return durationMin
	default:
		if durationMin < 15 {
			return 15
		}
		if durationMin > 480 {
			return 480
		}
		return durationMin
	}
}

func clampIntakeDuration(durationMin int) int {
	if durationMin < 3 {
		return 3
	}
	if durationMin > 60 {
		return 60
	}
	return durationMin
}
