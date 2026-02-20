package server

import (
	"net/http"
	"testing"
	"time"
)

func TestBabyProfileUpsertAndGet(t *testing.T) {
	resetDatabase(t)
	fixture := seedOwnerFixture(t)
	seedEvent(t, "", fixture.BabyID, "FORMULA", time.Now().UTC().Add(-2*time.Hour), nil, map[string]any{"ml": 120}, fixture.UserID)

	patchRec := performRequest(
		t,
		newTestRouter(t),
		http.MethodPatch,
		"/api/v1/babies/profile",
		signToken(t, fixture.UserID, nil),
		map[string]any{
			"baby_id":                 fixture.BabyID,
			"baby_sex":                "female",
			"baby_weight_kg":          6.6,
			"feeding_method":          "mixed",
			"formula_brand":           "SampleBrand",
			"formula_product":         "Stage 1",
			"formula_type":            "thickened",
			"formula_contains_starch": true,
		},
		nil,
	)
	if patchRec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d body=%s", patchRec.Code, patchRec.Body.String())
	}
	patchBody := decodeJSONMap(t, patchRec)
	if patchBody["formula_type"] != "thickened" {
		t.Fatalf("expected formula_type=thickened, got %v", patchBody["formula_type"])
	}
	if patchBody["feeding_method"] != "mixed" {
		t.Fatalf("expected feeding_method=mixed, got %v", patchBody["feeding_method"])
	}
	if patchBody["recommended_feed_interval_min"] == nil {
		t.Fatalf("expected recommended_feed_interval_min")
	}

	getRec := performRequest(
		t,
		newTestRouter(t),
		http.MethodGet,
		"/api/v1/babies/profile?baby_id="+fixture.BabyID,
		signToken(t, fixture.UserID, nil),
		nil,
		nil,
	)
	if getRec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d body=%s", getRec.Code, getRec.Body.String())
	}
	getBody := decodeJSONMap(t, getRec)
	if getBody["formula_display_name"] == "" {
		t.Fatalf("expected non-empty formula_display_name")
	}
	if getBody["formula_catalog"] == nil {
		t.Fatalf("expected formula_catalog in response")
	}
}
