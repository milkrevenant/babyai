package server

import (
	"context"
	"net/http"
	"strings"
	"testing"
	"time"
)

func TestOnboardingParentCreatesHouseholdAndBaby(t *testing.T) {
	resetDatabase(t)
	userID := seedUser(t, "")

	rec := performRequest(
		t,
		newTestRouter(t),
		http.MethodPost,
		"/api/v1/onboarding/parent",
		signToken(t, userID, nil),
		map[string]any{
			"provider":          "google",
			"baby_name":         "Mina",
			"baby_birth_date":   "2024-01-02",
			"required_consents": []string{"terms", "privacy"},
		},
		nil,
	)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d body=%s", rec.Code, rec.Body.String())
	}

	body := decodeJSONMap(t, rec)
	if body["status"] != "created" {
		t.Fatalf("expected status created, got %v", body["status"])
	}
	householdID, ok := body["household_id"].(string)
	if !ok || strings.TrimSpace(householdID) == "" {
		t.Fatalf("expected household_id in response, got %v", body["household_id"])
	}
	babyID, ok := body["baby_id"].(string)
	if !ok || strings.TrimSpace(babyID) == "" {
		t.Fatalf("expected baby_id in response, got %v", body["baby_id"])
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	var ownerID string
	if err := testPool.QueryRow(
		ctx,
		`SELECT "ownerUserId" FROM "Household" WHERE id = $1`,
		householdID,
	).Scan(&ownerID); err != nil {
		t.Fatalf("query created household: %v", err)
	}
	if ownerID != userID {
		t.Fatalf("expected owner user %q, got %q", userID, ownerID)
	}

	var storedBabyID string
	if err := testPool.QueryRow(
		ctx,
		`SELECT id FROM "Baby" WHERE id = $1`,
		babyID,
	).Scan(&storedBabyID); err != nil {
		t.Fatalf("query created baby: %v", err)
	}
}

func TestOnboardingParentRejectsInvalidConsent(t *testing.T) {
	resetDatabase(t)
	userID := seedUser(t, "")

	rec := performRequest(
		t,
		newTestRouter(t),
		http.MethodPost,
		"/api/v1/onboarding/parent",
		signToken(t, userID, nil),
		map[string]any{
			"provider":          "phone",
			"baby_name":         "Mina",
			"baby_birth_date":   "2024-01-02",
			"required_consents": []string{"terms", "not-valid"},
		},
		nil,
	)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d body=%s", rec.Code, rec.Body.String())
	}
	if detail := responseDetail(t, rec); detail != "Invalid consent value" {
		t.Fatalf("unexpected detail: %q", detail)
	}
}

func TestCreatePhotoUploadURLReturnsUploadData(t *testing.T) {
	resetDatabase(t)
	fixture := seedOwnerFixture(t)
	albumID := seedAlbum(t, "", fixture.HouseholdID, fixture.BabyID)

	rec := performRequest(
		t,
		newTestRouter(t),
		http.MethodPost,
		"/api/v1/photos/upload-url?album_id="+albumID,
		signToken(t, fixture.UserID, nil),
		nil,
		nil,
	)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d body=%s", rec.Code, rec.Body.String())
	}
	body := decodeJSONMap(t, rec)
	if body["album_id"] != albumID {
		t.Fatalf("expected album_id=%q, got %v", albumID, body["album_id"])
	}
	uploadURL, _ := body["upload_url"].(string)
	if !strings.HasPrefix(uploadURL, "https://storage.example.com/upload/") {
		t.Fatalf("unexpected upload_url: %q", uploadURL)
	}
}

func TestCreatePhotoUploadURLRejectsUserWithoutWriteRole(t *testing.T) {
	resetDatabase(t)
	fixture := seedOwnerFixture(t)
	albumID := seedAlbum(t, "", fixture.HouseholdID, fixture.BabyID)
	viewerID := seedUser(t, "")
	seedHouseholdMember(t, "", fixture.HouseholdID, viewerID, "FAMILY_VIEWER", "ACTIVE")

	rec := performRequest(
		t,
		newTestRouter(t),
		http.MethodPost,
		"/api/v1/photos/upload-url?album_id="+albumID,
		signToken(t, viewerID, nil),
		nil,
		nil,
	)
	if rec.Code != http.StatusForbidden {
		t.Fatalf("expected 403, got %d body=%s", rec.Code, rec.Body.String())
	}
	if detail := responseDetail(t, rec); detail != "Insufficient role for this action" {
		t.Fatalf("unexpected detail: %q", detail)
	}
}

func TestCompletePhotoUploadPersistsPhotoAsset(t *testing.T) {
	resetDatabase(t)
	fixture := seedOwnerFixture(t)
	albumID := seedAlbum(t, "", fixture.HouseholdID, fixture.BabyID)

	rec := performRequest(
		t,
		newTestRouter(t),
		http.MethodPost,
		"/api/v1/photos/complete",
		signToken(t, fixture.UserID, nil),
		map[string]any{
			"album_id":     albumID,
			"object_key":   "photos/2026/02/test.jpg",
			"downloadable": true,
		},
		nil,
	)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d body=%s", rec.Code, rec.Body.String())
	}
	body := decodeJSONMap(t, rec)
	if body["status"] != "uploaded" {
		t.Fatalf("expected status uploaded, got %v", body["status"])
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	var count int
	if err := testPool.QueryRow(
		ctx,
		`SELECT COUNT(*) FROM "PhotoAsset" WHERE "albumId" = $1`,
		albumID,
	).Scan(&count); err != nil {
		t.Fatalf("query photo assets: %v", err)
	}
	if count != 1 {
		t.Fatalf("expected 1 photo asset row, got %d", count)
	}
}

func TestGetMySubscriptionReturnsNoneWhenMissing(t *testing.T) {
	resetDatabase(t)
	fixture := seedOwnerFixture(t)

	rec := performRequest(
		t,
		newTestRouter(t),
		http.MethodGet,
		"/api/v1/subscription/me?household_id="+fixture.HouseholdID,
		signToken(t, fixture.UserID, nil),
		nil,
		nil,
	)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d body=%s", rec.Code, rec.Body.String())
	}
	body := decodeJSONMap(t, rec)
	if body["status"] != "none" {
		t.Fatalf("expected status none, got %v", body["status"])
	}
	if body["plan"] != nil {
		t.Fatalf("expected plan=nil, got %v", body["plan"])
	}
}

func TestCheckoutSubscriptionRejectsInvalidPlan(t *testing.T) {
	resetDatabase(t)
	fixture := seedOwnerFixture(t)

	rec := performRequest(
		t,
		newTestRouter(t),
		http.MethodPost,
		"/api/v1/subscription/checkout",
		signToken(t, fixture.UserID, nil),
		map[string]any{
			"household_id": fixture.HouseholdID,
			"plan":         "NOT_A_PLAN",
		},
		nil,
	)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d body=%s", rec.Code, rec.Body.String())
	}
	if detail := responseDetail(t, rec); detail != "Invalid subscription plan" {
		t.Fatalf("unexpected detail: %q", detail)
	}
}

func TestCheckoutSubscriptionCreatesTrialingSubscription(t *testing.T) {
	resetDatabase(t)
	fixture := seedOwnerFixture(t)

	checkout := performRequest(
		t,
		newTestRouter(t),
		http.MethodPost,
		"/api/v1/subscription/checkout",
		signToken(t, fixture.UserID, nil),
		map[string]any{
			"household_id": fixture.HouseholdID,
			"plan":         "AI_ONLY",
		},
		nil,
	)
	if checkout.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d body=%s", checkout.Code, checkout.Body.String())
	}
	checkoutBody := decodeJSONMap(t, checkout)
	if checkoutBody["status"] != "pending_payment" {
		t.Fatalf("expected pending_payment status, got %v", checkoutBody["status"])
	}

	current := performRequest(
		t,
		newTestRouter(t),
		http.MethodGet,
		"/api/v1/subscription/me?household_id="+fixture.HouseholdID,
		signToken(t, fixture.UserID, nil),
		nil,
		nil,
	)
	if current.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d body=%s", current.Code, current.Body.String())
	}
	currentBody := decodeJSONMap(t, current)
	if currentBody["plan"] != "AI_ONLY" {
		t.Fatalf("expected plan AI_ONLY, got %v", currentBody["plan"])
	}
	if currentBody["status"] != "trialing" {
		t.Fatalf("expected status trialing, got %v", currentBody["status"])
	}
}

func TestCheckoutSubscriptionBuildsFormulaPreanalysisMetadata(t *testing.T) {
	resetDatabase(t)
	fixture := seedOwnerFixture(t)

	updateProfile := performRequest(
		t,
		newTestRouter(t),
		http.MethodPatch,
		"/api/v1/babies/profile",
		signToken(t, fixture.UserID, nil),
		map[string]any{
			"baby_id":         fixture.BabyID,
			"feeding_method":  "formula",
			"formula_brand":   "Maeil",
			"formula_product": "Absolute Sensitive",
		},
		nil,
	)
	if updateProfile.Code != http.StatusOK {
		t.Fatalf("expected profile update 200, got %d body=%s", updateProfile.Code, updateProfile.Body.String())
	}

	checkout := performRequest(
		t,
		newTestRouter(t),
		http.MethodPost,
		"/api/v1/subscription/checkout",
		signToken(t, fixture.UserID, nil),
		map[string]any{
			"household_id": fixture.HouseholdID,
			"plan":         "AI_ONLY",
		},
		nil,
	)
	if checkout.Code != http.StatusOK {
		t.Fatalf("expected checkout 200, got %d body=%s", checkout.Code, checkout.Body.String())
	}
	checkoutBody := decodeJSONMap(t, checkout)
	if enrichedAny, ok := checkoutBody["care_meta_enriched_baby"].(float64); !ok || int(enrichedAny) != 1 {
		t.Fatalf("expected care_meta_enriched_baby=1, got %v", checkoutBody["care_meta_enriched_baby"])
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	var personaRaw []byte
	if err := testPool.QueryRow(
		ctx,
		`SELECT "personaJson" FROM "PersonaProfile" WHERE "userId" = $1 LIMIT 1`,
		fixture.UserID,
	).Scan(&personaRaw); err != nil {
		t.Fatalf("query persona profile: %v", err)
	}
	persona := parseJSONStringMap(personaRaw)
	appSettings, ok := persona["app_settings"].(map[string]any)
	if !ok {
		t.Fatalf("expected app_settings in persona profile")
	}
	babyProfiles, ok := appSettings["baby_profiles"].(map[string]any)
	if !ok {
		t.Fatalf("expected app_settings.baby_profiles map")
	}
	profileAny, ok := babyProfiles[fixture.BabyID]
	if !ok {
		t.Fatalf("expected baby profile for %s", fixture.BabyID)
	}
	profileMap, ok := profileAny.(map[string]any)
	if !ok {
		t.Fatalf("expected baby profile object, got %T", profileAny)
	}
	careMeta, ok := profileMap["subscription_care_metadata"].(map[string]any)
	if !ok {
		t.Fatalf("expected subscription_care_metadata map, got %T", profileMap["subscription_care_metadata"])
	}
	formulaMeta, ok := careMeta["formula_preanalysis"].(map[string]any)
	if !ok {
		t.Fatalf("expected formula_preanalysis map, got %T", careMeta["formula_preanalysis"])
	}
	if formulaMeta["normalized_formula_type"] != "specialty" {
		t.Fatalf("expected normalized_formula_type=specialty, got %v", formulaMeta["normalized_formula_type"])
	}
	if formulaMeta["official_guide"] != subscriptionFormulaGuideURL {
		t.Fatalf("expected formula official_guide=%q, got %v", subscriptionFormulaGuideURL, formulaMeta["official_guide"])
	}
}

func TestCheckoutSubscriptionRejectsCaregiverBillingRole(t *testing.T) {
	resetDatabase(t)
	fixture := seedOwnerFixture(t)
	caregiverID := seedUser(t, "")
	seedHouseholdMember(t, "", fixture.HouseholdID, caregiverID, "CAREGIVER", "ACTIVE")

	rec := performRequest(
		t,
		newTestRouter(t),
		http.MethodPost,
		"/api/v1/subscription/checkout",
		signToken(t, caregiverID, nil),
		map[string]any{
			"household_id": fixture.HouseholdID,
			"plan":         "AI_PHOTO",
		},
		nil,
	)
	if rec.Code != http.StatusForbidden {
		t.Fatalf("expected 403, got %d body=%s", rec.Code, rec.Body.String())
	}
	if detail := responseDetail(t, rec); detail != "Insufficient role for this action" {
		t.Fatalf("unexpected detail: %q", detail)
	}
}

func TestSiriEndpointReturnsDialog(t *testing.T) {
	resetDatabase(t)
	fixture := seedOwnerFixture(t)

	rec := performRequest(
		t,
		newTestRouter(t),
		http.MethodPost,
		"/api/v1/assistants/siri/GetTodaySummary",
		signToken(t, fixture.UserID, nil),
		map[string]any{
			"baby_id": fixture.BabyID,
			"tone":    "brief",
		},
		nil,
	)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d body=%s", rec.Code, rec.Body.String())
	}
	body := decodeJSONMap(t, rec)
	dialog, _ := body["dialog"].(string)
	if !strings.Contains(dialog, "Today:") {
		t.Fatalf("unexpected dialog: %q", dialog)
	}
}

func TestSiriDynamicEndpointHandlesUnsupportedIntent(t *testing.T) {
	resetDatabase(t)
	fixture := seedOwnerFixture(t)

	rec := performRequest(
		t,
		newTestRouter(t),
		http.MethodPost,
		"/api/v1/assistants/siri/UnknownIntent",
		signToken(t, fixture.UserID, nil),
		map[string]any{
			"baby_id": fixture.BabyID,
			"tone":    "friendly",
		},
		nil,
	)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d body=%s", rec.Code, rec.Body.String())
	}
	body := decodeJSONMap(t, rec)
	if body["dialog"] != "Unsupported intent." {
		t.Fatalf("unexpected dialog: %v", body["dialog"])
	}
}

func TestBixbyQueryFallsBackToTodaySummaryIntent(t *testing.T) {
	resetDatabase(t)
	fixture := seedOwnerFixture(t)

	rec := performRequest(
		t,
		newTestRouter(t),
		http.MethodPost,
		"/api/v1/assistants/bixby/query",
		signToken(t, fixture.UserID, nil),
		map[string]any{
			"capsule_action": "UnknownAction",
			"baby_id":        fixture.BabyID,
			"tone":           "neutral",
		},
		nil,
	)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d body=%s", rec.Code, rec.Body.String())
	}
	body := decodeJSONMap(t, rec)
	answer, _ := body["answer"].(string)
	if !strings.Contains(answer, "Today:") {
		t.Fatalf("unexpected bixby answer: %q", answer)
	}
	if resultMoment, ok := body["resultMoment"].(bool); !ok || !resultMoment {
		t.Fatalf("expected resultMoment=true, got %v", body["resultMoment"])
	}
}

func TestBixbyQueryRejectsMissingRequiredFields(t *testing.T) {
	resetDatabase(t)
	fixture := seedOwnerFixture(t)

	rec := performRequest(
		t,
		newTestRouter(t),
		http.MethodPost,
		"/api/v1/assistants/bixby/query",
		signToken(t, fixture.UserID, nil),
		map[string]any{
			"baby_id": fixture.BabyID,
		},
		nil,
	)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d body=%s", rec.Code, rec.Body.String())
	}
	if detail := responseDetail(t, rec); detail != "capsule_action and baby_id are required" {
		t.Fatalf("unexpected detail: %q", detail)
	}
}

func TestGetMySubscriptionReturnsExistingPlan(t *testing.T) {
	resetDatabase(t)
	fixture := seedOwnerFixture(t)
	seedSubscription(t, "", fixture.HouseholdID, "AI_PHOTO", "ACTIVE")

	rec := performRequest(
		t,
		newTestRouter(t),
		http.MethodGet,
		"/api/v1/subscription/me?household_id="+fixture.HouseholdID,
		signToken(t, fixture.UserID, nil),
		nil,
		nil,
	)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d body=%s", rec.Code, rec.Body.String())
	}
	body := decodeJSONMap(t, rec)
	if body["plan"] != "AI_PHOTO" {
		t.Fatalf("expected plan AI_PHOTO, got %v", body["plan"])
	}
	if body["status"] != "active" {
		t.Fatalf("expected status active, got %v", body["status"])
	}
}
