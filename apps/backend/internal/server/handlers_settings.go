package server

import (
	"context"
	"errors"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

var defaultBottomMenuEnabled = map[string]bool{
	"chat":       true,
	"statistics": true,
	"photos":     true,
	"market":     false,
	"community":  false,
}

var defaultHomeTiles = map[string]bool{
	"formula":    true,
	"breastfeed": false,
	"weaning":    false,
	"diaper":     true,
	"sleep":      true,
	"medication": false,
	"memo":       false,
}

func (a *App) getMySettings(c *gin.Context) {
	user, ok := authUserFromContext(c)
	if !ok {
		writeError(c, http.StatusUnauthorized, "Unauthorized")
		return
	}

	persona, err := loadPersonaSettings(c.Request.Context(), a.db, user.ID)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			c.JSON(http.StatusOK, buildSettingsResponse(nil))
			return
		}
		writeError(c, http.StatusInternalServerError, "Failed to load settings")
		return
	}

	c.JSON(http.StatusOK, buildSettingsResponse(persona))
}

func (a *App) upsertMySettings(c *gin.Context) {
	user, ok := authUserFromContext(c)
	if !ok {
		writeError(c, http.StatusUnauthorized, "Unauthorized")
		return
	}

	var payload updateMySettingsRequest
	if !mustJSON(c, &payload) {
		return
	}

	persona := map[string]any{}
	loaded, err := loadPersonaSettings(c.Request.Context(), a.db, user.ID)
	if err == nil {
		persona = loaded
	} else if !errors.Is(err, pgx.ErrNoRows) {
		writeError(c, http.StatusInternalServerError, "Failed to load settings")
		return
	}

	appSettings, _ := persona["app_settings"].(map[string]any)
	if appSettings == nil {
		appSettings = map[string]any{}
	}

	if payload.ThemeMode != nil {
		themeMode, valid := normalizeThemeMode(*payload.ThemeMode)
		if !valid {
			writeError(c, http.StatusBadRequest, "theme_mode must be one of: system, dark, light")
			return
		}
		appSettings["theme_mode"] = themeMode
	}

	if payload.Language != nil {
		language, valid := normalizeLanguage(*payload.Language)
		if !valid {
			writeError(c, http.StatusBadRequest, "language must be one of: ko, en, es")
			return
		}
		appSettings["language"] = language
	}

	if payload.MainFont != nil {
		font, valid := normalizeMainFont(*payload.MainFont)
		if !valid {
			writeError(c, http.StatusBadRequest, "main_font must be one of: notoSans, systemSans")
			return
		}
		appSettings["main_font"] = font
	}

	if payload.HighlightFont != nil {
		font, valid := normalizeHighlightFont(*payload.HighlightFont)
		if !valid {
			writeError(c, http.StatusBadRequest, "highlight_font must be one of: ibmPlexSans, notoSans")
			return
		}
		appSettings["highlight_font"] = font
	}

	if payload.AccentTone != nil {
		tone, valid := normalizeAccentTone(*payload.AccentTone)
		if !valid {
			writeError(c, http.StatusBadRequest, "accent_tone must be one of: gold, teal, coral, indigo")
			return
		}
		appSettings["accent_tone"] = tone
	}

	if payload.ChildCareProfile != nil {
		profile, valid := normalizeChildCareProfile(*payload.ChildCareProfile)
		if !valid {
			writeError(c, http.StatusBadRequest, "child_care_profile must be one of: breastfeeding, formula, weaning")
			return
		}
		appSettings["child_care_profile"] = profile
	}

	if payload.BottomMenu != nil {
		merged := resolveBottomMenuEnabled(persona)
		for key, value := range payload.BottomMenu {
			if _, known := defaultBottomMenuEnabled[key]; known {
				merged[key] = value
			}
		}
		appSettings["bottom_menu_enabled"] = merged
	}

	if payload.HomeTiles != nil {
		merged := resolveHomeTiles(persona)
		for key, value := range payload.HomeTiles {
			if _, known := defaultHomeTiles[key]; known {
				merged[key] = value
			}
		}
		appSettings["home_tiles"] = merged
	}

	persona["app_settings"] = appSettings

	if _, err := a.db.Exec(
		c.Request.Context(),
		`INSERT INTO "PersonaProfile" (id, "userId", "personaJson", "updatedAt")
		 VALUES ($1, $2, $3, NOW())
		 ON CONFLICT ("userId")
		 DO UPDATE SET "personaJson" = EXCLUDED."personaJson", "updatedAt" = NOW()`,
		uuid.NewString(),
		user.ID,
		mustMarshalJSON(persona),
	); err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to save settings")
		return
	}

	c.JSON(http.StatusOK, buildSettingsResponse(persona))
}

func loadPersonaSettings(ctx context.Context, q dbQuerier, userID string) (map[string]any, error) {
	var personaRaw []byte
	err := q.QueryRow(
		ctx,
		`SELECT "personaJson" FROM "PersonaProfile" WHERE "userId" = $1 LIMIT 1`,
		userID,
	).Scan(&personaRaw)
	if err != nil {
		return nil, err
	}
	return parseJSONStringMap(personaRaw), nil
}

func buildSettingsResponse(persona map[string]any) gin.H {
	return gin.H{
		"theme_mode":          resolveThemeMode(persona),
		"language":            resolveLanguage(persona),
		"main_font":           resolveMainFont(persona),
		"highlight_font":      resolveHighlightFont(persona),
		"accent_tone":         resolveAccentTone(persona),
		"bottom_menu_enabled": resolveBottomMenuEnabled(persona),
		"child_care_profile":  resolveChildCareProfile(persona),
		"home_tiles":          resolveHomeTiles(persona),
	}
}

func resolveThemeMode(persona map[string]any) string {
	if persona == nil {
		return "system"
	}

	if appSettings, ok := persona["app_settings"].(map[string]any); ok {
		if themeMode, valid := normalizeThemeMode(toString(appSettings["theme_mode"])); valid {
			return themeMode
		}
	}

	if themeMode, valid := normalizeThemeMode(toString(persona["theme_mode"])); valid {
		return themeMode
	}

	return "system"
}

func resolveLanguage(persona map[string]any) string {
	if appSettings, ok := persona["app_settings"].(map[string]any); ok {
		if value, valid := normalizeLanguage(toString(appSettings["language"])); valid {
			return value
		}
	}
	return "ko"
}

func resolveMainFont(persona map[string]any) string {
	if appSettings, ok := persona["app_settings"].(map[string]any); ok {
		if value, valid := normalizeMainFont(toString(appSettings["main_font"])); valid {
			return value
		}
	}
	return "notoSans"
}

func resolveHighlightFont(persona map[string]any) string {
	if appSettings, ok := persona["app_settings"].(map[string]any); ok {
		if value, valid := normalizeHighlightFont(toString(appSettings["highlight_font"])); valid {
			return value
		}
	}
	return "ibmPlexSans"
}

func resolveAccentTone(persona map[string]any) string {
	if appSettings, ok := persona["app_settings"].(map[string]any); ok {
		if value, valid := normalizeAccentTone(toString(appSettings["accent_tone"])); valid {
			return value
		}
	}
	return "gold"
}

func resolveChildCareProfile(persona map[string]any) string {
	if appSettings, ok := persona["app_settings"].(map[string]any); ok {
		if value, valid := normalizeChildCareProfile(toString(appSettings["child_care_profile"])); valid {
			return value
		}
	}
	return "formula"
}

func resolveBottomMenuEnabled(persona map[string]any) map[string]bool {
	resolved := copyBoolMap(defaultBottomMenuEnabled)
	if appSettings, ok := persona["app_settings"].(map[string]any); ok {
		if raw, ok := appSettings["bottom_menu_enabled"].(map[string]any); ok {
			for key := range defaultBottomMenuEnabled {
				if parsed, ok := toBool(raw[key]); ok {
					resolved[key] = parsed
				}
			}
		}
	}
	return resolved
}

func resolveHomeTiles(persona map[string]any) map[string]bool {
	resolved := copyBoolMap(defaultHomeTiles)
	if appSettings, ok := persona["app_settings"].(map[string]any); ok {
		if raw, ok := appSettings["home_tiles"].(map[string]any); ok {
			for key := range defaultHomeTiles {
				if parsed, ok := toBool(raw[key]); ok {
					resolved[key] = parsed
				}
			}
		}
	}
	return resolved
}

func copyBoolMap(input map[string]bool) map[string]bool {
	result := make(map[string]bool, len(input))
	for key, value := range input {
		result[key] = value
	}
	return result
}

func toBool(input any) (bool, bool) {
	switch value := input.(type) {
	case bool:
		return value, true
	case string:
		lowered := strings.ToLower(strings.TrimSpace(value))
		switch lowered {
		case "true", "1":
			return true, true
		case "false", "0":
			return false, true
		}
	case float64:
		if value == 1 {
			return true, true
		}
		if value == 0 {
			return false, true
		}
	}
	return false, false
}

func normalizeThemeMode(input string) (string, bool) {
	mode := strings.ToLower(strings.TrimSpace(input))
	switch mode {
	case "system", "dark", "light":
		return mode, true
	default:
		return "", false
	}
}

func normalizeLanguage(input string) (string, bool) {
	language := strings.ToLower(strings.TrimSpace(input))
	switch language {
	case "ko", "en", "es":
		return language, true
	default:
		return "", false
	}
}

func normalizeMainFont(input string) (string, bool) {
	value := strings.TrimSpace(input)
	switch value {
	case "notoSans", "systemSans":
		return value, true
	default:
		return "", false
	}
}

func normalizeHighlightFont(input string) (string, bool) {
	value := strings.TrimSpace(input)
	switch value {
	case "ibmPlexSans", "notoSans":
		return value, true
	default:
		return "", false
	}
}

func normalizeAccentTone(input string) (string, bool) {
	value := strings.ToLower(strings.TrimSpace(input))
	switch value {
	case "gold", "teal", "coral", "indigo":
		return value, true
	default:
		return "", false
	}
}

func normalizeChildCareProfile(input string) (string, bool) {
	value := strings.ToLower(strings.TrimSpace(input))
	switch value {
	case "breastfeeding", "formula", "weaning":
		return value, true
	default:
		return "", false
	}
}
