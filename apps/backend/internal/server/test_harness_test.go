package server

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"

	"babyai/apps/backend/internal/config"
	"babyai/apps/backend/internal/db"
)

var (
	testPool              *pgxpool.Pool
	baseTestConfig        config.Config
	integrationDBReady    bool
	integrationSkipReason string
)

func TestMain(m *testing.M) {
	gin.SetMode(gin.TestMode)
	baseTestConfig = newTestConfig()

	testDatabaseURL := strings.TrimSpace(os.Getenv("TEST_DATABASE_URL"))
	if testDatabaseURL == "" {
		integrationSkipReason = "integration tests skipped: TEST_DATABASE_URL is not set"
		fmt.Fprintln(os.Stderr, integrationSkipReason)
		os.Exit(m.Run())
	}
	testDatabaseURL = withSimpleProtocol(testDatabaseURL)

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	pool, err := db.Connect(ctx, testDatabaseURL)
	cancel()
	if err != nil {
		fmt.Fprintf(os.Stderr, "integration test setup failed: cannot connect TEST_DATABASE_URL: %v\n", err)
		os.Exit(1)
	}

	ctx, cancel = context.WithTimeout(context.Background(), 5*time.Second)
	err = pool.Ping(ctx)
	cancel()
	if err != nil {
		pool.Close()
		fmt.Fprintf(os.Stderr, "integration test setup failed: database ping failed: %v\n", err)
		os.Exit(1)
	}

	if err := verifyRequiredTables(pool); err != nil {
		pool.Close()
		fmt.Fprintf(os.Stderr, "integration test setup failed: %v\n", err)
		os.Exit(1)
	}

	testPool = pool
	integrationDBReady = true

	exitCode := m.Run()
	testPool.Close()
	os.Exit(exitCode)
}

func withSimpleProtocol(rawURL string) string {
	parsed, err := url.Parse(strings.TrimSpace(rawURL))
	if err != nil {
		return rawURL
	}
	queries := parsed.Query()
	queries.Set("default_query_exec_mode", "simple_protocol")
	parsed.RawQuery = queries.Encode()
	return parsed.String()
}

func newTestConfig() config.Config {
	cfg := config.Config{
		AppEnv:             "test",
		AppName:            "BabyAI API Test",
		APIPrefix:          "/api/v1",
		AppPort:            "0",
		DatabaseURL:        "test",
		RedisURL:           "redis://localhost:6379/0",
		DefaultTone:        "neutral",
		JWTSecret:          "test-secret-1234567890",
		JWTAlgorithm:       "HS256",
		JWTAudience:        "",
		JWTIssuer:          "",
		AuthAutoCreateUser: false,
		CORSAllowOrigins: []string{
			"http://localhost:5173",
			"http://127.0.0.1:5173",
			"http://localhost:3000",
		},
	}

	if v := strings.TrimSpace(os.Getenv("TEST_JWT_SECRET")); v != "" {
		cfg.JWTSecret = v
	}
	if v := strings.TrimSpace(os.Getenv("TEST_JWT_AUDIENCE")); v != "" {
		cfg.JWTAudience = v
	}
	if v := strings.TrimSpace(os.Getenv("TEST_JWT_ISSUER")); v != "" {
		cfg.JWTIssuer = v
	}
	return cfg
}

func verifyRequiredTables(pool *pgxpool.Pool) error {
	required := []string{
		"User",
		"Household",
		"HouseholdMember",
		"Baby",
		"Event",
		"VoiceClip",
		"Report",
		"Album",
		"PhotoAsset",
		"Subscription",
		"Consent",
		"AuditLog",
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	missing := make([]string, 0)
	for _, table := range required {
		var exists bool
		if err := pool.QueryRow(
			ctx,
			`SELECT EXISTS (
				SELECT 1
				FROM information_schema.tables
				WHERE table_schema = 'public' AND table_name = $1
			)`,
			table,
		).Scan(&exists); err != nil {
			return fmt.Errorf("failed to validate schema table %q: %w", table, err)
		}
		if !exists {
			missing = append(missing, table)
		}
	}

	if len(missing) > 0 {
		return fmt.Errorf(
			"missing required tables: %s. Run `npm run prisma:push` with TEST_DATABASE_URL before running integration tests",
			strings.Join(missing, ", "),
		)
	}
	return nil
}

func requireIntegration(t *testing.T) {
	t.Helper()
	if !integrationDBReady {
		if integrationSkipReason == "" {
			integrationSkipReason = "integration tests skipped: TEST_DATABASE_URL is not configured"
		}
		t.Skip(integrationSkipReason)
	}
}

func newTestRouter(t *testing.T) *gin.Engine {
	t.Helper()
	return newTestRouterWithConfig(t, baseTestConfig)
}

func newTestRouterWithConfig(t *testing.T, cfg config.Config) *gin.Engine {
	t.Helper()
	requireIntegration(t)
	return New(cfg, testPool).Router()
}

func resetDatabase(t *testing.T) {
	t.Helper()
	requireIntegration(t)

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	_, err := testPool.Exec(
		ctx,
		`TRUNCATE TABLE
			"AuditLog",
			"PhotoAsset",
			"Album",
			"Subscription",
			"Invite",
			"Report",
			"VoiceClip",
			"Event",
			"Baby",
			"HouseholdMember",
			"Household",
			"Consent",
			"AiToneProfile",
			"PersonaProfile",
			"User"
		RESTART IDENTITY CASCADE`,
	)
	if err != nil {
		t.Fatalf("reset database: %v", err)
	}
}

type accessFixture struct {
	UserID      string
	HouseholdID string
	BabyID      string
}

func seedOwnerFixture(t *testing.T) accessFixture {
	t.Helper()
	userID := seedUser(t, "")
	householdID := seedHousehold(t, "", userID)
	babyID := seedBaby(t, "", householdID, "test-baby", time.Now().UTC().AddDate(-1, 0, 0))
	return accessFixture{
		UserID:      userID,
		HouseholdID: householdID,
		BabyID:      babyID,
	}
}

func seedUser(t *testing.T, userID string) string {
	t.Helper()
	requireIntegration(t)
	if strings.TrimSpace(userID) == "" {
		userID = testID()
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	name := "user-" + userID[:8]
	_, err := testPool.Exec(
		ctx,
		`INSERT INTO "User" (id, provider, "providerUid", phone, name, "createdAt")
		 VALUES ($1, 'phone', NULL, NULL, $2, NOW())`,
		userID,
		name,
	)
	if err != nil {
		t.Fatalf("seed user: %v", err)
	}
	return userID
}

func seedHousehold(t *testing.T, householdID, ownerUserID string) string {
	t.Helper()
	requireIntegration(t)
	if strings.TrimSpace(householdID) == "" {
		householdID = testID()
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	_, err := testPool.Exec(
		ctx,
		`INSERT INTO "Household" (id, "ownerUserId", "createdAt")
		 VALUES ($1, $2, NOW())`,
		householdID,
		ownerUserID,
	)
	if err != nil {
		t.Fatalf("seed household: %v", err)
	}
	return householdID
}

func seedHouseholdMember(t *testing.T, membershipID, householdID, userID, role, status string) string {
	t.Helper()
	requireIntegration(t)
	if strings.TrimSpace(membershipID) == "" {
		membershipID = testID()
	}
	if strings.TrimSpace(status) == "" {
		status = "ACTIVE"
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	_, err := testPool.Exec(
		ctx,
		`INSERT INTO "HouseholdMember" (id, "householdId", "userId", role, status, "createdAt")
		 VALUES ($1, $2, $3, $4, $5, NOW())`,
		membershipID,
		householdID,
		userID,
		role,
		status,
	)
	if err != nil {
		t.Fatalf("seed household member: %v", err)
	}
	return membershipID
}

func seedBaby(t *testing.T, babyID, householdID, name string, birthDate time.Time) string {
	t.Helper()
	requireIntegration(t)
	if strings.TrimSpace(babyID) == "" {
		babyID = testID()
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	_, err := testPool.Exec(
		ctx,
		`INSERT INTO "Baby" (id, "householdId", name, "birthDate", "createdAt")
		 VALUES ($1, $2, $3, $4, NOW())`,
		babyID,
		householdID,
		name,
		birthDate.UTC(),
	)
	if err != nil {
		t.Fatalf("seed baby: %v", err)
	}
	return babyID
}

func seedVoiceClip(t *testing.T, clipID, householdID, babyID, status string) string {
	t.Helper()
	requireIntegration(t)
	if strings.TrimSpace(clipID) == "" {
		clipID = testID()
	}
	if strings.TrimSpace(status) == "" {
		status = "PARSED"
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	_, err := testPool.Exec(
		ctx,
		`INSERT INTO "VoiceClip" (
			id, "householdId", "babyId", "audioUrl", transcript, "parsedEventsJson", "confidenceJson", status, "createdAt"
		) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, NOW())`,
		clipID,
		householdID,
		babyID,
		"uploads/voice/"+testID()+".m4a",
		"seed transcript",
		mustJSONBytes(t, []map[string]any{}),
		mustJSONBytes(t, map[string]any{}),
		status,
	)
	if err != nil {
		t.Fatalf("seed voice clip: %v", err)
	}
	return clipID
}

func seedEvent(
	t *testing.T,
	eventID, babyID, eventType string,
	start time.Time,
	end *time.Time,
	value map[string]any,
	createdBy string,
) string {
	t.Helper()
	requireIntegration(t)
	if strings.TrimSpace(eventID) == "" {
		eventID = testID()
	}
	if value == nil {
		value = map[string]any{}
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	_, err := testPool.Exec(
		ctx,
		`INSERT INTO "Event" (
			id, "babyId", type, "startTime", "endTime", "valueJson", "metadataJson", source, "createdBy", "createdAt"
		) VALUES ($1, $2, $3, $4, $5, $6, NULL, 'MANUAL', $7, NOW())`,
		eventID,
		babyID,
		eventType,
		start.UTC(),
		end,
		mustJSONBytes(t, value),
		createdBy,
	)
	if err != nil {
		t.Fatalf("seed event: %v", err)
	}
	return eventID
}

func seedAlbum(t *testing.T, albumID, householdID, babyID string) string {
	t.Helper()
	requireIntegration(t)
	if strings.TrimSpace(albumID) == "" {
		albumID = testID()
	}

	var babyRef any
	if strings.TrimSpace(babyID) == "" {
		babyRef = nil
	} else {
		babyRef = babyID
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	_, err := testPool.Exec(
		ctx,
		`INSERT INTO "Album" (id, "householdId", "babyId", title, "monthKey", "createdAt")
		 VALUES ($1, $2, $3, $4, $5, NOW())`,
		albumID,
		householdID,
		babyRef,
		"seed album",
		time.Now().UTC().Format("2006-01"),
	)
	if err != nil {
		t.Fatalf("seed album: %v", err)
	}
	return albumID
}

func seedSubscription(t *testing.T, subscriptionID, householdID, plan, status string) string {
	t.Helper()
	requireIntegration(t)
	if strings.TrimSpace(subscriptionID) == "" {
		subscriptionID = testID()
	}
	if strings.TrimSpace(plan) == "" {
		plan = "AI_ONLY"
	}
	if strings.TrimSpace(status) == "" {
		status = "TRIALING"
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	_, err := testPool.Exec(
		ctx,
		`INSERT INTO "Subscription" (id, "householdId", plan, status, "createdAt")
		 VALUES ($1, $2, $3, $4, NOW())`,
		subscriptionID,
		householdID,
		plan,
		status,
	)
	if err != nil {
		t.Fatalf("seed subscription: %v", err)
	}
	return subscriptionID
}

func seedReport(
	t *testing.T,
	reportID, householdID, babyID, periodType string,
	start, end time.Time,
	metrics map[string]any,
	summary string,
) string {
	t.Helper()
	requireIntegration(t)
	if strings.TrimSpace(reportID) == "" {
		reportID = testID()
	}
	if metrics == nil {
		metrics = map[string]any{}
	}
	if strings.TrimSpace(summary) == "" {
		summary = "seed summary"
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	_, err := testPool.Exec(
		ctx,
		`INSERT INTO "Report" (
			id, "householdId", "babyId", "periodType", "periodStart", "periodEnd", "metricsJson", "summaryText", "modelVersion", "createdAt"
		) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, 'test-v1', NOW())`,
		reportID,
		householdID,
		babyID,
		periodType,
		start.UTC(),
		end.UTC(),
		mustJSONBytes(t, metrics),
		summary,
	)
	if err != nil {
		t.Fatalf("seed report: %v", err)
	}
	return reportID
}

func signToken(t *testing.T, sub string, overrides map[string]any) string {
	t.Helper()
	return signTokenWithConfig(t, baseTestConfig, sub, overrides)
}

func signTokenWithConfig(t *testing.T, cfg config.Config, sub string, overrides map[string]any) string {
	t.Helper()

	claims := jwt.MapClaims{
		"exp": time.Now().UTC().Add(1 * time.Hour).Unix(),
		"iat": time.Now().UTC().Add(-1 * time.Minute).Unix(),
	}
	if strings.TrimSpace(sub) != "" {
		claims["sub"] = sub
	}
	if strings.TrimSpace(cfg.JWTAudience) != "" {
		claims["aud"] = cfg.JWTAudience
	}
	if strings.TrimSpace(cfg.JWTIssuer) != "" {
		claims["iss"] = cfg.JWTIssuer
	}
	for key, value := range overrides {
		if value == nil {
			delete(claims, key)
			continue
		}
		claims[key] = value
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	signed, err := token.SignedString([]byte(cfg.JWTSecret))
	if err != nil {
		t.Fatalf("sign token: %v", err)
	}
	return signed
}

func performRequest(
	t *testing.T,
	router http.Handler,
	method, targetPath, token string,
	body any,
	headers map[string]string,
) *httptest.ResponseRecorder {
	t.Helper()

	var payload []byte
	if body != nil {
		var err error
		payload, err = json.Marshal(body)
		if err != nil {
			t.Fatalf("marshal request body: %v", err)
		}
	}

	send := func() *httptest.ResponseRecorder {
		req := httptest.NewRequest(method, targetPath, bytes.NewReader(payload))
		if body != nil {
			req.Header.Set("Content-Type", "application/json")
		}
		if strings.TrimSpace(token) != "" {
			req.Header.Set("Authorization", "Bearer "+token)
		}
		for key, value := range headers {
			req.Header.Set(key, value)
		}

		rec := httptest.NewRecorder()
		router.ServeHTTP(rec, req)
		return rec
	}

	rec := send()
	// Prisma Dev DB can briefly restart/hand off sockets; retry once on that specific transient.
	if rec.Code == http.StatusInternalServerError {
		bodyText := strings.ToLower(rec.Body.String())
		if strings.Contains(bodyText, "failed to connect to `user=postgres database=template1`") ||
			strings.Contains(bodyText, "connectex") ||
			strings.Contains(bodyText, "unexpected eof") {
			time.Sleep(250 * time.Millisecond)
			rec = send()
		}
	}
	return rec
}

func decodeJSONMap(t *testing.T, rec *httptest.ResponseRecorder) map[string]any {
	t.Helper()
	var payload map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &payload); err != nil {
		t.Fatalf("decode response JSON: %v; body=%s", err, rec.Body.String())
	}
	return payload
}

func decodeStringList(t *testing.T, raw any) []string {
	t.Helper()
	values, ok := raw.([]any)
	if !ok {
		t.Fatalf("expected []any, got %T", raw)
	}
	result := make([]string, 0, len(values))
	for _, item := range values {
		s, ok := item.(string)
		if !ok {
			t.Fatalf("expected string list item, got %T", item)
		}
		result = append(result, s)
	}
	return result
}

func responseDetail(t *testing.T, rec *httptest.ResponseRecorder) string {
	t.Helper()
	body := decodeJSONMap(t, rec)
	detail, _ := body["detail"].(string)
	return detail
}

func mustJSONBytes(t *testing.T, payload any) string {
	t.Helper()
	encoded, err := json.Marshal(payload)
	if err != nil {
		t.Fatalf("marshal JSON bytes: %v", err)
	}
	return string(encoded)
}

func testID() string {
	return uuid.NewString()
}
