package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"log"
	"os"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

type seedEvent struct {
	Type      string
	StartHM   string
	EndHM     string
	ValueJSON map[string]any
}

func main() {
	var (
		mode      string
		babyID    string
		userID    string
		date      string
		tag       string
		timezone  string
		database  string
		applyDate string
	)

	flag.StringVar(&mode, "mode", "seed", "seed or cleanup")
	flag.StringVar(&babyID, "baby-id", "", "target baby id (default: latest created baby)")
	flag.StringVar(&userID, "user-id", "", "createdBy user id (default: household owner)")
	flag.StringVar(&date, "date", "", "local date in YYYY-MM-DD (default: today in timezone)")
	flag.StringVar(&tag, "tag", "dummy_timeline_v1", "seed tag used for insert/delete")
	flag.StringVar(&timezone, "tz", "Asia/Seoul", "IANA timezone for local schedule")
	flag.StringVar(&database, "db", "", "DATABASE_URL override")
	flag.StringVar(&applyDate, "date-local", "", "alias of -date")
	flag.Parse()

	if applyDate != "" && date == "" {
		date = applyDate
	}

	ctx := context.Background()
	dbURL := strings.TrimSpace(database)
	if dbURL == "" {
		dbURL = strings.TrimSpace(os.Getenv("DATABASE_URL"))
	}
	if dbURL == "" {
		dbURL = "postgres://babyai:babyai@localhost:5432/babyai"
	}

	conn, err := pgx.Connect(ctx, dbURL)
	if err != nil {
		log.Fatalf("connect db: %v", err)
	}
	defer conn.Close(ctx)

	targetBabyID, householdID, err := resolveTargetBaby(ctx, conn, babyID)
	if err != nil {
		log.Fatalf("resolve baby: %v", err)
	}

	targetUserID := strings.TrimSpace(userID)
	if targetUserID == "" {
		targetUserID, err = resolveOwnerUser(ctx, conn, householdID)
		if err != nil {
			log.Fatalf("resolve owner user: %v", err)
		}
	}

	switch strings.ToLower(strings.TrimSpace(mode)) {
	case "cleanup", "delete", "remove":
		deleted, err := cleanupSeed(ctx, conn, targetBabyID, tag)
		if err != nil {
			log.Fatalf("cleanup: %v", err)
		}
		fmt.Printf("cleanup complete baby_id=%s tag=%s deleted=%d\n", targetBabyID, tag, deleted)
		return
	case "seed":
		// continue
	default:
		log.Fatalf("unsupported mode %q (use seed or cleanup)", mode)
	}

	location, err := time.LoadLocation(strings.TrimSpace(timezone))
	if err != nil {
		log.Fatalf("load timezone: %v", err)
	}

	localDate := strings.TrimSpace(date)
	if localDate == "" {
		localDate = time.Now().In(location).Format("2006-01-02")
	}
	if _, err := time.ParseInLocation("2006-01-02", localDate, location); err != nil {
		log.Fatalf("invalid date %q: %v", localDate, err)
	}

	events := []seedEvent{
		{
			Type:      "SLEEP",
			StartHM:   "00:57",
			EndHM:     "02:35",
			ValueJSON: map[string]any{"sleep_type": "night"},
		},
		{
			Type:      "SLEEP",
			StartHM:   "02:38",
			EndHM:     "06:13",
			ValueJSON: map[string]any{"sleep_type": "night"},
		},
		{
			Type:      "FORMULA",
			StartHM:   "06:36",
			EndHM:     "",
			ValueJSON: map[string]any{"ml": 145},
		},
		{
			Type:      "SLEEP",
			StartHM:   "07:45",
			EndHM:     "08:47",
			ValueJSON: map[string]any{"sleep_type": "nap"},
		},
		{
			Type:      "FORMULA",
			StartHM:   "09:22",
			EndHM:     "",
			ValueJSON: map[string]any{"ml": 125},
		},
		{
			Type:      "SLEEP",
			StartHM:   "10:23",
			EndHM:     "11:07",
			ValueJSON: map[string]any{"sleep_type": "nap"},
		},
		{
			Type:      "FORMULA",
			StartHM:   "11:29",
			EndHM:     "",
			ValueJSON: map[string]any{"ml": 130},
		},
		{
			Type:      "SLEEP",
			StartHM:   "12:51",
			EndHM:     "13:21",
			ValueJSON: map[string]any{"sleep_type": "nap"},
		},
		{
			Type:      "FORMULA",
			StartHM:   "13:37",
			EndHM:     "",
			ValueJSON: map[string]any{"ml": 90},
		},
		{
			Type:      "SLEEP",
			StartHM:   "14:58",
			EndHM:     "15:21",
			ValueJSON: map[string]any{"sleep_type": "nap"},
		},
		{
			Type:      "FORMULA",
			StartHM:   "15:55",
			EndHM:     "",
			ValueJSON: map[string]any{"ml": 150},
		},
		{
			Type:      "MEMO",
			StartHM:   "15:58",
			EndHM:     "",
			ValueJSON: map[string]any{"memo": "Dummy timeline seeded for UI verification."},
		},
	}

	tx, err := conn.Begin(ctx)
	if err != nil {
		log.Fatalf("begin tx: %v", err)
	}
	defer tx.Rollback(ctx)

	// Keep seed idempotent for repeated runs.
	deleted, err := cleanupSeedWithTx(ctx, tx, targetBabyID, tag)
	if err != nil {
		log.Fatalf("cleanup existing seed rows: %v", err)
	}

	inserted := 0
	for index, entry := range events {
		startUTC, err := parseLocalDateTime(localDate, entry.StartHM, location)
		if err != nil {
			log.Fatalf("parse start time (%s %s): %v", localDate, entry.StartHM, err)
		}
		var endAny any
		if strings.TrimSpace(entry.EndHM) == "" {
			endAny = nil
		} else {
			endUTC, parseErr := parseLocalDateTime(localDate, entry.EndHM, location)
			if parseErr != nil {
				log.Fatalf("parse end time (%s %s): %v", localDate, entry.EndHM, parseErr)
			}
			if endUTC.Before(startUTC) {
				log.Fatalf("invalid range %s %s-%s", entry.Type, entry.StartHM, entry.EndHM)
			}
			endAny = endUTC
		}

		valueRaw, err := mustJSON(entry.ValueJSON)
		if err != nil {
			log.Fatalf("marshal value json: %v", err)
		}
		metadataRaw, err := mustJSON(map[string]any{
			"seed_tag":         tag,
			"seed_name":        "dummy_timeline",
			"seed_timezone":    timezone,
			"seed_local_date":  localDate,
			"seed_event_index": index + 1,
		})
		if err != nil {
			log.Fatalf("marshal metadata json: %v", err)
		}

		if _, err := tx.Exec(
			ctx,
			`INSERT INTO "Event" (
				id, "babyId", type, "startTime", "endTime", "valueJson", "metadataJson", source, "createdBy", "createdAt"
			) VALUES ($1, $2, $3, $4, $5, $6, $7, 'MANUAL', $8, NOW())`,
			uuid.NewString(),
			targetBabyID,
			strings.ToUpper(strings.TrimSpace(entry.Type)),
			startUTC,
			endAny,
			valueRaw,
			metadataRaw,
			targetUserID,
		); err != nil {
			log.Fatalf("insert event (%s %s): %v", entry.Type, entry.StartHM, err)
		}
		inserted++
	}

	if err := tx.Commit(ctx); err != nil {
		log.Fatalf("commit: %v", err)
	}

	fmt.Printf(
		"seed complete baby_id=%s user_id=%s date=%s tz=%s tag=%s inserted=%d replaced=%d\n",
		targetBabyID,
		targetUserID,
		localDate,
		timezone,
		tag,
		inserted,
		deleted,
	)
}

func resolveTargetBaby(ctx context.Context, conn *pgx.Conn, explicitBabyID string) (babyID string, householdID string, err error) {
	explicitBabyID = strings.TrimSpace(explicitBabyID)
	if explicitBabyID != "" {
		err = conn.QueryRow(
			ctx,
			`SELECT id, "householdId" FROM "Baby" WHERE id = $1`,
			explicitBabyID,
		).Scan(&babyID, &householdID)
		if err != nil {
			if errors.Is(err, pgx.ErrNoRows) {
				return "", "", fmt.Errorf("baby not found: %s", explicitBabyID)
			}
			return "", "", err
		}
		return babyID, householdID, nil
	}

	err = conn.QueryRow(
		ctx,
		`SELECT id, "householdId" FROM "Baby" ORDER BY "createdAt" DESC LIMIT 1`,
	).Scan(&babyID, &householdID)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return "", "", errors.New("no babies found")
		}
		return "", "", err
	}
	return babyID, householdID, nil
}

func resolveOwnerUser(ctx context.Context, conn *pgx.Conn, householdID string) (string, error) {
	var userID string
	err := conn.QueryRow(
		ctx,
		`SELECT "ownerUserId" FROM "Household" WHERE id = $1`,
		householdID,
	).Scan(&userID)
	if err == nil {
		return userID, nil
	}
	if !errors.Is(err, pgx.ErrNoRows) {
		return "", err
	}

	// Fallback for malformed local data: use latest user.
	err = conn.QueryRow(
		ctx,
		`SELECT id FROM "User" ORDER BY "createdAt" DESC LIMIT 1`,
	).Scan(&userID)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return "", errors.New("no users found to use as createdBy")
		}
		return "", err
	}
	return userID, nil
}

func parseLocalDateTime(localDate, hourMinute string, location *time.Location) (time.Time, error) {
	parsed, err := time.ParseInLocation(
		"2006-01-02 15:04",
		localDate+" "+strings.TrimSpace(hourMinute),
		location,
	)
	if err != nil {
		return time.Time{}, err
	}
	return parsed.UTC(), nil
}

func cleanupSeed(ctx context.Context, conn *pgx.Conn, babyID, tag string) (int64, error) {
	tx, err := conn.Begin(ctx)
	if err != nil {
		return 0, err
	}
	defer tx.Rollback(ctx)

	deleted, err := cleanupSeedWithTx(ctx, tx, babyID, tag)
	if err != nil {
		return 0, err
	}
	if err := tx.Commit(ctx); err != nil {
		return 0, err
	}
	return deleted, nil
}

func cleanupSeedWithTx(ctx context.Context, tx pgx.Tx, babyID, tag string) (int64, error) {
	result, err := tx.Exec(
		ctx,
		`DELETE FROM "Event"
		 WHERE "babyId" = $1
		   AND COALESCE("metadataJson"->>'seed_tag', '') = $2`,
		babyID,
		tag,
	)
	if err != nil {
		return 0, err
	}
	return result.RowsAffected(), nil
}

func mustJSON(value map[string]any) ([]byte, error) {
	if value == nil {
		value = map[string]any{}
	}
	return json.Marshal(value)
}
