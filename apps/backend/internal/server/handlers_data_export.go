package server

import (
	"bytes"
	"encoding/csv"
	"errors"
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
)

func sanitizeCSVFilename(input string) string {
	trimmed := strings.TrimSpace(input)
	if trimmed == "" {
		return "baby"
	}
	var b strings.Builder
	for _, r := range trimmed {
		if (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9') {
			b.WriteRune(r)
			continue
		}
		if r == '-' || r == '_' {
			b.WriteRune(r)
			continue
		}
		b.WriteRune('_')
	}
	sanitized := strings.Trim(b.String(), "_")
	if sanitized == "" {
		return "baby"
	}
	return sanitized
}

func timeOrEmpty(value *time.Time) string {
	if value == nil {
		return ""
	}
	return value.UTC().Format(time.RFC3339)
}

func (a *App) exportBabyDataCSV(c *gin.Context) {
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

	rows, err := a.db.Query(
		c.Request.Context(),
		`SELECT
			id,
			type::text,
			"startTime",
			"endTime",
			COALESCE("valueJson", '{}'::jsonb)::text,
			COALESCE("metadataJson", '{}'::jsonb)::text,
			source::text,
			"createdBy",
			"createdAt"
		FROM "Event"
		WHERE "babyId" = $1
		ORDER BY "startTime" ASC, "createdAt" ASC`,
		baby.ID,
	)
	if err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to load events")
		return
	}
	defer rows.Close()

	var out bytes.Buffer
	writer := csv.NewWriter(&out)
	if err := writer.Write([]string{
		"event_id",
		"baby_id",
		"type",
		"start_time_utc",
		"end_time_utc",
		"value_json",
		"metadata_json",
		"source",
		"created_by",
		"created_at_utc",
	}); err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to build CSV header")
		return
	}

	for rows.Next() {
		var (
			eventID      string
			eventType    string
			startTime    time.Time
			endTime      *time.Time
			valueJSON    string
			metadataJSON string
			source       string
			createdBy    string
			createdAt    time.Time
		)
		if err := rows.Scan(
			&eventID,
			&eventType,
			&startTime,
			&endTime,
			&valueJSON,
			&metadataJSON,
			&source,
			&createdBy,
			&createdAt,
		); err != nil {
			writeError(c, http.StatusInternalServerError, "Failed to parse events")
			return
		}
		if err := writer.Write([]string{
			eventID,
			baby.ID,
			eventType,
			startTime.UTC().Format(time.RFC3339),
			timeOrEmpty(endTime),
			valueJSON,
			metadataJSON,
			source,
			createdBy,
			createdAt.UTC().Format(time.RFC3339),
		}); err != nil {
			writeError(c, http.StatusInternalServerError, "Failed to write CSV rows")
			return
		}
	}
	if err := rows.Err(); err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to read events")
		return
	}

	writer.Flush()
	if err := writer.Error(); err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to flush CSV")
		return
	}

	filename := fmt.Sprintf(
		"babyai_export_%s_%s.csv",
		sanitizeCSVFilename(baby.ID),
		time.Now().UTC().Format("20060102_150405"),
	)

	c.Header("Content-Type", "text/csv; charset=utf-8")
	c.Header("Content-Disposition", fmt.Sprintf("attachment; filename=\"%s\"", filename))
	c.String(http.StatusOK, out.String())
}

func ensureCSVContainsHeader(raw string) error {
	if strings.TrimSpace(raw) == "" {
		return errors.New("empty csv")
	}
	if !strings.Contains(raw, "event_id,baby_id,type,start_time_utc,end_time_utc") {
		return errors.New("missing csv header")
	}
	return nil
}
