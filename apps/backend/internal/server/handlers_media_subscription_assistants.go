package server

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

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

func (a *App) uploadPhotoFromDevice(c *gin.Context) {
	user, ok := authUserFromContext(c)
	if !ok {
		writeError(c, http.StatusUnauthorized, "Unauthorized")
		return
	}

	albumID, householdID, statusCode, err := a.resolveAlbumForPhotoUpload(
		c.Request.Context(),
		user.ID,
		c.PostForm("album_id"),
		c.PostForm("baby_id"),
	)
	if err != nil {
		writeError(c, statusCode, err.Error())
		return
	}

	fileHeader, err := c.FormFile("file")
	if err != nil {
		writeError(c, http.StatusBadRequest, "file is required")
		return
	}
	if fileHeader.Size <= 0 {
		writeError(c, http.StatusBadRequest, "empty file is not allowed")
		return
	}

	downloadable := false
	if strings.EqualFold(strings.TrimSpace(c.PostForm("downloadable")), "true") ||
		strings.TrimSpace(c.PostForm("downloadable")) == "1" {
		downloadable = true
	}

	ext := strings.ToLower(filepath.Ext(strings.TrimSpace(fileHeader.Filename)))
	if ext == "" || len(ext) > 8 {
		ext = ".jpg"
	}
	now := time.Now().UTC()
	objectKey := fmt.Sprintf("photos/%04d/%02d/%s%s", now.Year(), int(now.Month()), uuid.NewString(), ext)
	diskPath := filepath.Join("uploads", filepath.FromSlash(objectKey))
	if err := os.MkdirAll(filepath.Dir(diskPath), 0o755); err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to prepare upload folder")
		return
	}
	if err := c.SaveUploadedFile(fileHeader, diskPath); err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to save uploaded file")
		return
	}

	publicPath := "/uploads/" + objectKey
	variants := map[string]string{
		"thumb":   publicPath,
		"preview": publicPath,
		"origin":  publicPath,
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
		albumID,
		user.ID,
		mustMarshalJSON(variants),
		downloadable,
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
		gin.H{"album_id": albumID, "downloadable": downloadable},
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
		"album_id":     albumID,
		"downloadable": downloadable,
		"object_key":   objectKey,
		"photo_url":    requestOrigin(c) + publicPath,
		"variants":     variants,
	})
}

func (a *App) listRecentPhotos(c *gin.Context) {
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

	limit := 48
	if rawLimit := strings.TrimSpace(c.Query("limit")); rawLimit != "" {
		parsed, err := strconv.Atoi(rawLimit)
		if err != nil || parsed <= 0 {
			writeError(c, http.StatusBadRequest, "limit must be a positive integer")
			return
		}
		if parsed > 200 {
			parsed = 200
		}
		limit = parsed
	}

	rows, err := a.db.Query(
		c.Request.Context(),
		`SELECT p.id, a.id, a.title, p.downloadable, p."createdAt", p."variantsJson"
		 FROM "PhotoAsset" p
		 JOIN "Album" a ON a.id = p."albumId"
		 WHERE a."babyId" = $1
		 ORDER BY p."createdAt" DESC
		 LIMIT $2`,
		baby.ID,
		limit,
	)
	if err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to load photos")
		return
	}
	defer rows.Close()

	origin := requestOrigin(c)
	photos := make([]gin.H, 0, limit)
	for rows.Next() {
		var photoID string
		var albumID string
		var albumTitle string
		var downloadable bool
		var createdAt time.Time
		var variantsRaw []byte
		if err := rows.Scan(
			&photoID,
			&albumID,
			&albumTitle,
			&downloadable,
			&createdAt,
			&variantsRaw,
		); err != nil {
			writeError(c, http.StatusInternalServerError, "Failed to parse photo rows")
			return
		}

		variants := parseJSONStringMap(variantsRaw)
		previewURL := strings.TrimSpace(toString(variants["preview"]))
		originURL := strings.TrimSpace(toString(variants["origin"]))
		if previewURL == "" {
			previewURL = originURL
		}
		if strings.HasPrefix(previewURL, "/") {
			previewURL = origin + previewURL
		}
		if strings.HasPrefix(originURL, "/") {
			originURL = origin + originURL
		}

		photos = append(photos, gin.H{
			"photo_id":      photoID,
			"album_id":      albumID,
			"album_title":   albumTitle,
			"downloadable":  downloadable,
			"created_at":    createdAt.UTC().Format(time.RFC3339),
			"preview_url":   previewURL,
			"original_url":  originURL,
			"variants_json": variants,
		})
	}

	c.JSON(http.StatusOK, gin.H{
		"baby_id":        baby.ID,
		"count":          len(photos),
		"photos":         photos,
		"reference_text": "Latest uploaded photos for this baby.",
	})
}

func (a *App) resolveAlbumForPhotoUpload(
	ctx context.Context,
	userID string,
	rawAlbumID string,
	rawBabyID string,
) (string, string, int, error) {
	albumID := strings.TrimSpace(rawAlbumID)
	babyID := strings.TrimSpace(rawBabyID)
	if albumID != "" {
		var householdID string
		err := a.db.QueryRow(
			ctx,
			`SELECT "householdId" FROM "Album" WHERE id = $1`,
			albumID,
		).Scan(&householdID)
		if errors.Is(err, pgx.ErrNoRows) {
			return "", "", http.StatusNotFound, errors.New("Album not found")
		}
		if err != nil {
			return "", "", http.StatusInternalServerError, errors.New("Failed to load album")
		}
		if _, statusCode, err := a.assertHouseholdAccess(ctx, userID, householdID, writeRoles); err != nil {
			return "", "", statusCode, err
		}
		return albumID, householdID, http.StatusOK, nil
	}

	if babyID == "" {
		return "", "", http.StatusBadRequest, errors.New("album_id or baby_id is required")
	}
	baby, statusCode, err := a.getBabyWithAccess(ctx, userID, babyID, writeRoles)
	if err != nil {
		return "", "", statusCode, err
	}

	resolvedAlbumID, err := a.resolveOrCreateMonthlyAlbum(ctx, baby.HouseholdID, baby.ID)
	if err != nil {
		return "", "", http.StatusInternalServerError, err
	}
	return resolvedAlbumID, baby.HouseholdID, http.StatusOK, nil
}

func (a *App) resolveOrCreateMonthlyAlbum(
	ctx context.Context,
	householdID string,
	babyID string,
) (string, error) {
	monthKey := time.Now().UTC().Format("2006-01")
	var albumID string
	err := a.db.QueryRow(
		ctx,
		`SELECT id
		 FROM "Album"
		 WHERE "householdId" = $1
		   AND "babyId" = $2
		   AND "monthKey" = $3
		 ORDER BY "createdAt" DESC
		 LIMIT 1`,
		householdID,
		babyID,
		monthKey,
	).Scan(&albumID)
	if err == nil {
		return albumID, nil
	}
	if !errors.Is(err, pgx.ErrNoRows) {
		return "", errors.New("Failed to load album")
	}

	albumID = uuid.NewString()
	title := fmt.Sprintf("%s photos", monthKey)
	if _, err := a.db.Exec(
		ctx,
		`INSERT INTO "Album" (id, "householdId", "babyId", title, "monthKey", "createdAt")
		 VALUES ($1, $2, $3, $4, $5, NOW())`,
		albumID,
		householdID,
		babyID,
		title,
		monthKey,
	); err != nil {
		return "", errors.New("Failed to create album")
	}
	return albumID, nil
}

func requestOrigin(c *gin.Context) string {
	scheme := "http"
	if c.Request.TLS != nil {
		scheme = "https"
	}
	if forwarded := strings.TrimSpace(c.GetHeader("X-Forwarded-Proto")); forwarded != "" {
		scheme = forwarded
	}
	host := strings.TrimSpace(c.Request.Host)
	if host == "" {
		host = "localhost:8000"
	}
	return scheme + "://" + host
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
		`SELECT plan, status FROM "Subscription" WHERE "householdId" = $1 LIMIT 1`,
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
		"plan":         plan,
		"status":       strings.ToLower(statusValue),
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
			 WHERE "babyId" = $1 AND status = 'CLOSED' AND type = 'POO'
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
		rows, err := a.db.Query(
			ctx,
			`SELECT "startTime" FROM "Event"
			 WHERE "babyId" = $1 AND status = 'CLOSED' AND type IN ('FORMULA', 'BREASTFEED')
			 ORDER BY "startTime" DESC LIMIT 10`,
			babyID,
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

		result := calculateNextFeedingETA(feedingTimes, time.Now().UTC())
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
			 WHERE "babyId" = $1 AND status = 'CLOSED' AND "startTime" >= $2 AND "startTime" < $3`,
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
