package server

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"net/http"
	"sort"
	"strings"
	"time"

	"github.com/gin-contrib/cors"
	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"

	"babyai/apps/backend/internal/config"
)

const (
	roleOwner        = "OWNER"
	roleParent       = "PARENT"
	roleFamilyViewer = "FAMILY_VIEWER"
	roleCaregiver    = "CAREGIVER"
)

var (
	readRoles = map[string]struct{}{
		roleOwner:        {},
		roleParent:       {},
		roleCaregiver:    {},
		roleFamilyViewer: {},
	}
	writeRoles = map[string]struct{}{
		roleOwner:     {},
		roleParent:    {},
		roleCaregiver: {},
	}
	billingRoles = map[string]struct{}{
		roleOwner:  {},
		roleParent: {},
	}
)

type dbQuerier interface {
	Exec(context.Context, string, ...any) (pgconn.CommandTag, error)
	Query(context.Context, string, ...any) (pgx.Rows, error)
	QueryRow(context.Context, string, ...any) pgx.Row
}

type App struct {
	cfg config.Config
	db  *pgxpool.Pool
	ai  AIClient
}

type AuthUser struct {
	ID          string
	Provider    string
	ProviderUID *string
	Phone       *string
	Name        string
}

func New(cfg config.Config, db *pgxpool.Pool) *App {
	var aiClient AIClient
	if strings.EqualFold(cfg.AppEnv, "test") {
		aiClient = MockAIClient{Model: cfg.OpenAIModel}
	} else {
		aiClient = NewOpenAIResponsesClient(cfg)
	}
	return &App{cfg: cfg, db: db, ai: aiClient}
}

func (a *App) Router() *gin.Engine {
	router := gin.New()
	router.Use(gin.Logger(), gin.Recovery())
	router.Use(cors.New(cors.Config{
		AllowOrigins:     a.cfg.CORSAllowOrigins,
		AllowMethods:     []string{"GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"},
		AllowHeaders:     []string{"Authorization", "Content-Type"},
		ExposeHeaders:    []string{"Content-Length"},
		AllowCredentials: true,
		MaxAge:           12 * time.Hour,
	}))

	router.GET("/health", a.health)
	router.GET("/dev/local-token", a.issueLocalDevToken)
	router.POST("/dev/local-token", a.issueLocalDevToken)

	api := router.Group(a.cfg.APIPrefix)
	api.Use(a.authMiddleware())

	api.POST("/onboarding/parent", a.onboardingParent)
	api.POST("/events/voice", a.parseVoiceEvent)
	api.POST("/events/confirm", a.confirmEvents)
	api.POST("/events/manual", a.createManualEvent)
	api.POST("/events/start", a.startManualEvent)
	api.PATCH("/events/:event_id", a.updateManualEvent)
	api.PATCH("/events/:event_id/complete", a.completeManualEvent)
	api.PATCH("/events/:event_id/cancel", a.cancelManualEvent)
	api.GET("/events/open", a.listOpenEvents)
	api.GET("/settings/me", a.getMySettings)
	api.PATCH("/settings/me", a.upsertMySettings)
	api.GET("/data/export.csv", a.exportBabyDataCSV)
	api.GET("/babies/profile", a.getBabyProfile)
	api.PATCH("/babies/profile", a.upsertBabyProfile)
	api.GET("/quick/last-poo-time", a.quickLastPooTime)
	api.GET("/quick/next-feeding-eta", a.quickNextFeedingETA)
	api.GET("/quick/today-summary", a.quickTodaySummary)
	api.GET("/quick/landing-snapshot", a.quickLandingSnapshot)
	api.POST("/ai/query", a.aiQuery)
	api.POST("/chat/sessions", a.createChatSession)
	api.GET("/chat/sessions", a.listChatSessions)
	api.POST("/chat/sessions/:session_id/messages", a.createChatMessage)
	api.GET("/chat/sessions/:session_id/messages", a.getChatMessages)
	api.POST("/chat/query", a.chatQuery)
	api.GET("/reports/daily", a.getDailyReport)
	api.GET("/reports/weekly", a.getWeeklyReport)
	api.POST("/photos/upload-url", a.createPhotoUploadURL)
	api.POST("/photos/complete", a.completePhotoUpload)
	api.GET("/subscription/me", a.getMySubscription)
	api.POST("/subscription/checkout", a.checkoutSubscription)
	api.POST("/assistants/siri/GetLastPooTime", a.siriLastPoo)
	api.POST("/assistants/siri/GetNextFeedingEta", a.siriNextFeeding)
	api.POST("/assistants/siri/GetTodaySummary", a.siriTodaySummary)
	api.POST("/assistants/siri/:intent_name", a.siriDynamic)
	api.POST("/assistants/bixby/query", a.bixbyQuery)

	return router
}

func (a *App) health(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{
		"status":  "ok",
		"service": "babyai-api",
	})
}

func (a *App) issueLocalDevToken(c *gin.Context) {
	if !strings.EqualFold(strings.TrimSpace(a.cfg.AppEnv), "local") {
		writeError(c, http.StatusNotFound, "Not found")
		return
	}

	secret := strings.TrimSpace(a.cfg.JWTSecret)
	if secret == "" {
		writeError(c, http.StatusInternalServerError, "JWT_SECRET is not configured")
		return
	}

	sub := strings.TrimSpace(c.Query("sub"))
	if sub == "" {
		sub = uuid.NewString()
	}
	if _, err := uuid.Parse(sub); err != nil {
		writeError(c, http.StatusBadRequest, "sub must be UUID format")
		return
	}

	name := strings.TrimSpace(c.DefaultQuery("name", "Local Dev User"))
	if name == "" {
		name = "Local Dev User"
	}
	provider := providerFromClaim(c.DefaultQuery("provider", "google"))

	if _, err := a.db.Exec(
		c.Request.Context(),
		`INSERT INTO "User" (id, provider, "providerUid", phone, name, "createdAt")
		 VALUES ($1, $2, NULL, NULL, $3, NOW())
		 ON CONFLICT (id)
		 DO UPDATE SET provider = EXCLUDED.provider, name = EXCLUDED.name`,
		sub,
		provider,
		name,
	); err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to prepare local user")
		return
	}

	method := jwt.GetSigningMethod(strings.TrimSpace(a.cfg.JWTAlgorithm))
	if method == nil {
		writeError(c, http.StatusInternalServerError, "Unsupported JWT algorithm")
		return
	}

	claims := jwt.MapClaims{
		"sub":      sub,
		"provider": provider,
		"name":     name,
		"iat":      time.Now().UTC().Unix(),
		"exp":      time.Now().UTC().Add(30 * 24 * time.Hour).Unix(),
	}
	if audience := strings.TrimSpace(a.cfg.JWTAudience); audience != "" {
		claims["aud"] = audience
	}
	if issuer := strings.TrimSpace(a.cfg.JWTIssuer); issuer != "" {
		claims["iss"] = issuer
	}

	token := jwt.NewWithClaims(method, claims)
	signed, err := token.SignedString([]byte(secret))
	if err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to sign local token")
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"token":          signed,
		"sub":            sub,
		"name":           name,
		"provider":       provider,
		"reference_text": "Local development token generated from backend JWT settings.",
	})
}

func (a *App) authMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		authHeader := c.GetHeader("Authorization")
		if !strings.HasPrefix(strings.ToLower(authHeader), "bearer ") {
			writeError(c, http.StatusUnauthorized, "Bearer token required")
			return
		}
		tokenString := strings.TrimSpace(authHeader[len("Bearer "):])
		if tokenString == "" {
			writeError(c, http.StatusUnauthorized, "Bearer token required")
			return
		}

		token, err := jwt.Parse(tokenString, func(token *jwt.Token) (any, error) {
			if token.Method == nil || token.Method.Alg() != a.cfg.JWTAlgorithm {
				return nil, fmt.Errorf("unexpected signing method: %v", token.Header["alg"])
			}
			return []byte(a.cfg.JWTSecret), nil
		})
		if err != nil || !token.Valid {
			writeError(c, http.StatusUnauthorized, "Invalid bearer token")
			return
		}

		claims, ok := token.Claims.(jwt.MapClaims)
		if !ok {
			writeError(c, http.StatusUnauthorized, "Invalid token payload")
			return
		}
		if a.cfg.JWTAudience != "" && !claimHasAudience(claims["aud"], a.cfg.JWTAudience) {
			writeError(c, http.StatusUnauthorized, "Invalid token audience")
			return
		}
		if a.cfg.JWTIssuer != "" {
			issuer, _ := claims["iss"].(string)
			if issuer != a.cfg.JWTIssuer {
				writeError(c, http.StatusUnauthorized, "Invalid token issuer")
				return
			}
		}
		sub, _ := claims["sub"].(string)
		sub = strings.TrimSpace(sub)
		if sub == "" {
			writeError(c, http.StatusUnauthorized, "Token subject missing")
			return
		}

		user, err := a.getOrCreateUser(c.Request.Context(), sub, claims)
		if err != nil {
			writeError(c, http.StatusUnauthorized, err.Error())
			return
		}

		c.Set("authUser", user)
		c.Next()
	}
}

func claimHasAudience(value any, audience string) bool {
	switch v := value.(type) {
	case string:
		return v == audience
	case []any:
		for _, item := range v {
			if s, ok := item.(string); ok && s == audience {
				return true
			}
		}
	case []string:
		for _, item := range v {
			if item == audience {
				return true
			}
		}
	}
	return false
}

func providerFromClaim(raw any) string {
	if s, ok := raw.(string); ok {
		switch s {
		case "apple", "google", "phone":
			return s
		}
	}
	return "phone"
}

func toOptionalString(raw any) *string {
	if s, ok := raw.(string); ok {
		trimmed := strings.TrimSpace(s)
		if trimmed != "" {
			return &trimmed
		}
	}
	return nil
}

func (a *App) getOrCreateUser(ctx context.Context, userID string, claims jwt.MapClaims) (AuthUser, error) {
	user := AuthUser{}
	var providerUID *string
	var phone *string

	err := a.db.QueryRow(
		ctx,
		`SELECT id, provider, "providerUid", phone, name FROM "User" WHERE id = $1`,
		userID,
	).Scan(&user.ID, &user.Provider, &providerUID, &phone, &user.Name)
	if err == nil {
		user.ProviderUID = providerUID
		user.Phone = phone
		return user, nil
	}
	if !errors.Is(err, pgx.ErrNoRows) {
		return AuthUser{}, err
	}
	if !a.cfg.AuthAutoCreateUser {
		return AuthUser{}, errors.New("User not found")
	}

	provider := providerFromClaim(claims["provider"])
	providerUID = toOptionalString(claims["provider_uid"])
	phone = toOptionalString(claims["phone"])

	name := ""
	if rawName, ok := claims["name"].(string); ok {
		name = strings.TrimSpace(rawName)
	}
	if name == "" {
		name = fmt.Sprintf("user-%s", truncate(userID, 8))
	}

	if _, err := a.db.Exec(
		ctx,
		`INSERT INTO "User" (id, provider, "providerUid", phone, name, "createdAt")
		 VALUES ($1, $2, $3, $4, $5, NOW())`,
		userID,
		provider,
		providerUID,
		phone,
		name,
	); err != nil {
		return AuthUser{}, err
	}

	return AuthUser{
		ID:          userID,
		Provider:    provider,
		ProviderUID: providerUID,
		Phone:       phone,
		Name:        name,
	}, nil
}

func truncate(value string, limit int) string {
	if len(value) <= limit {
		return value
	}
	return value[:limit]
}

func authUserFromContext(c *gin.Context) (AuthUser, bool) {
	raw, ok := c.Get("authUser")
	if !ok {
		return AuthUser{}, false
	}
	user, ok := raw.(AuthUser)
	return user, ok
}

func writeError(c *gin.Context, status int, detail string) {
	c.AbortWithStatusJSON(status, gin.H{"detail": detail})
}

func containsRole(allowed map[string]struct{}, role string) bool {
	_, ok := allowed[role]
	return ok
}

func (a *App) getHouseholdRole(ctx context.Context, userID, householdID string) (string, int, error) {
	var ownerUserID string
	err := a.db.QueryRow(
		ctx,
		`SELECT "ownerUserId" FROM "Household" WHERE id = $1`,
		householdID,
	).Scan(&ownerUserID)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", http.StatusNotFound, errors.New("Household not found")
	}
	if err != nil {
		return "", http.StatusInternalServerError, err
	}
	if ownerUserID == userID {
		return roleOwner, http.StatusOK, nil
	}

	var role string
	err = a.db.QueryRow(
		ctx,
		`SELECT role FROM "HouseholdMember"
		 WHERE "householdId" = $1 AND "userId" = $2 AND status = 'ACTIVE'
		 LIMIT 1`,
		householdID,
		userID,
	).Scan(&role)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", http.StatusForbidden, errors.New("Household access denied")
	}
	if err != nil {
		return "", http.StatusInternalServerError, err
	}
	return role, http.StatusOK, nil
}

func (a *App) assertHouseholdAccess(ctx context.Context, userID, householdID string, allowed map[string]struct{}) (string, int, error) {
	role, statusCode, err := a.getHouseholdRole(ctx, userID, householdID)
	if err != nil {
		return "", statusCode, err
	}
	if !containsRole(allowed, role) {
		return "", http.StatusForbidden, errors.New("Insufficient role for this action")
	}
	return role, http.StatusOK, nil
}

type babyRecord struct {
	ID          string
	HouseholdID string
}

func (a *App) getBabyWithAccess(ctx context.Context, userID, babyID string, allowed map[string]struct{}) (babyRecord, int, error) {
	record := babyRecord{}
	err := a.db.QueryRow(
		ctx,
		`SELECT id, "householdId" FROM "Baby" WHERE id = $1`,
		babyID,
	).Scan(&record.ID, &record.HouseholdID)
	if errors.Is(err, pgx.ErrNoRows) {
		return babyRecord{}, http.StatusNotFound, errors.New("Baby not found")
	}
	if err != nil {
		return babyRecord{}, http.StatusInternalServerError, err
	}

	if _, statusCode, err := a.assertHouseholdAccess(ctx, userID, record.HouseholdID, allowed); err != nil {
		return babyRecord{}, statusCode, err
	}
	return record, http.StatusOK, nil
}

func recordAuditLog(ctx context.Context, q dbQuerier, householdID, actorUserID, action, targetType string, targetID *string, payload any) error {
	id := uuid.NewString()
	var payloadJSON any
	if payload != nil {
		encoded, err := json.Marshal(payload)
		if err != nil {
			return err
		}
		payloadJSON = string(encoded)
	}

	var actor any
	if strings.TrimSpace(actorUserID) == "" {
		actor = nil
	} else {
		actor = actorUserID
	}
	return q.QueryRow(
		ctx,
		`INSERT INTO "AuditLog" (id, "householdId", "actorUserId", action, "targetType", "targetId", "payloadJson", "createdAt")
		 VALUES ($1, $2, $3, $4, $5, $6, $7, NOW())
		 RETURNING id`,
		id,
		householdID,
		actor,
		action,
		targetType,
		targetID,
		payloadJSON,
	).Scan(&id)
}

func mustJSON(c *gin.Context, payload any) bool {
	if err := c.ShouldBindJSON(payload); err != nil {
		writeError(c, http.StatusBadRequest, "Invalid request payload")
		return false
	}
	return true
}

func parseDate(value string) (time.Time, error) {
	t, err := time.Parse("2006-01-02", strings.TrimSpace(value))
	if err != nil {
		return time.Time{}, err
	}
	return time.Date(t.Year(), t.Month(), t.Day(), 0, 0, 0, 0, time.UTC), nil
}

func startOfUTCDay(t time.Time) time.Time {
	utc := t.UTC()
	return time.Date(utc.Year(), utc.Month(), utc.Day(), 0, 0, 0, 0, time.UTC)
}

func extractNumberFromMap(data map[string]any, keys ...string) float64 {
	if data == nil {
		return 0
	}
	for _, key := range keys {
		raw, ok := data[key]
		if !ok {
			continue
		}
		switch v := raw.(type) {
		case float64:
			return v
		case float32:
			return float64(v)
		case int:
			return float64(v)
		case int64:
			return float64(v)
		case json.Number:
			f, err := v.Float64()
			if err == nil {
				return f
			}
		case string:
			var parsed float64
			_, err := fmt.Sscanf(v, "%f", &parsed)
			if err == nil {
				return parsed
			}
		}
	}
	return 0
}

func parseJSONStringMap(input []byte) map[string]any {
	if len(input) == 0 {
		return map[string]any{}
	}
	var result map[string]any
	if err := json.Unmarshal(input, &result); err != nil || result == nil {
		return map[string]any{}
	}
	return result
}

func parseJSONStringList(input []byte) []map[string]any {
	if len(input) == 0 {
		return nil
	}
	var result []map[string]any
	if err := json.Unmarshal(input, &result); err != nil {
		return nil
	}
	return result
}

type etaCalculation struct {
	ETAMinutes             *int
	AverageIntervalMinutes *int
	Unstable               bool
}

func calculateNextFeedingETA(feedings []time.Time, now time.Time) etaCalculation {
	normalizedNow := now.UTC()
	// Ignore future feedings so ETA is always anchored to "current" time.
	candidates := make([]time.Time, 0, len(feedings))
	for _, feedingAt := range feedings {
		ts := feedingAt.UTC()
		if ts.After(normalizedNow) {
			continue
		}
		candidates = append(candidates, ts)
	}
	if len(candidates) < 2 {
		return etaCalculation{Unstable: true}
	}
	ordered := make([]time.Time, len(candidates))
	copy(ordered, candidates)
	sort.Slice(ordered, func(i, j int) bool {
		return ordered[i].Before(ordered[j])
	})

	intervals := make([]float64, 0, len(ordered)-1)
	for idx := 1; idx < len(ordered); idx++ {
		gapMinutes := ordered[idx].Sub(ordered[idx-1]).Minutes()
		if gapMinutes <= 0 {
			continue
		}
		intervals = append(intervals, gapMinutes)
	}
	if len(intervals) == 0 {
		return etaCalculation{Unstable: true}
	}

	if len(intervals) >= 5 {
		sorted := make([]float64, len(intervals))
		copy(sorted, intervals)
		sort.Float64s(sorted)
		trimSize := len(sorted) / 10
		if trimSize < 1 {
			trimSize = 1
		}
		if trimSize*2 < len(sorted) {
			intervals = sorted[trimSize : len(sorted)-trimSize]
		} else {
			intervals = sorted
		}
	}

	total := 0.0
	for _, interval := range intervals {
		total += interval
	}
	avg := int(math.Round(total / float64(len(intervals))))
	if avg <= 0 {
		return etaCalculation{Unstable: true}
	}

	lastFeeding := ordered[len(ordered)-1]
	expected := lastFeeding.Add(time.Duration(avg) * time.Minute)
	// Keep projecting by average interval until expected is in the future.
	if expected.Before(normalizedNow) {
		overdueMinutes := normalizedNow.Sub(expected).Minutes()
		cycles := int(overdueMinutes/float64(avg)) + 1
		expected = expected.Add(time.Duration(cycles*avg) * time.Minute)
	}

	eta := int(math.Ceil(expected.Sub(normalizedNow).Minutes()))
	if eta < 0 {
		eta = 0
	}
	return etaCalculation{
		ETAMinutes:             &eta,
		AverageIntervalMinutes: &avg,
		Unstable:               false,
	}
}

func toneWrap(tone, friendly, formal string, brief ...string) string {
	if tone == "formal" {
		return formal
	}
	if tone == "brief" && len(brief) > 0 {
		return brief[0]
	}
	return friendly
}
