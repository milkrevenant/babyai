package server

import (
	"errors"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

func (a *App) getMySettings(c *gin.Context) {
	user, ok := authUserFromContext(c)
	if !ok {
		writeError(c, http.StatusUnauthorized, "Unauthorized")
		return
	}

	var personaRaw []byte
	err := a.db.QueryRow(
		c.Request.Context(),
		`SELECT "personaJson" FROM "PersonaProfile" WHERE "userId" = $1 LIMIT 1`,
		user.ID,
	).Scan(&personaRaw)
	if errors.Is(err, pgx.ErrNoRows) {
		c.JSON(http.StatusOK, gin.H{
			"theme_mode": "system",
		})
		return
	}
	if err != nil {
		writeError(c, http.StatusInternalServerError, "Failed to load settings")
		return
	}

	persona := parseJSONStringMap(personaRaw)
	c.JSON(http.StatusOK, gin.H{
		"theme_mode": resolveThemeMode(persona),
	})
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

	themeMode, valid := normalizeThemeMode(payload.ThemeMode)
	if !valid {
		writeError(c, http.StatusBadRequest, "theme_mode must be one of: system, dark, light")
		return
	}

	persona := map[string]any{}
	var personaRaw []byte
	err := a.db.QueryRow(
		c.Request.Context(),
		`SELECT "personaJson" FROM "PersonaProfile" WHERE "userId" = $1 LIMIT 1`,
		user.ID,
	).Scan(&personaRaw)
	if err == nil {
		persona = parseJSONStringMap(personaRaw)
	} else if !errors.Is(err, pgx.ErrNoRows) {
		writeError(c, http.StatusInternalServerError, "Failed to load settings")
		return
	}

	appSettings := map[string]any{}
	if rawAppSettings, ok := persona["app_settings"]; ok {
		if parsed, ok := rawAppSettings.(map[string]any); ok {
			appSettings = parsed
		}
	}
	appSettings["theme_mode"] = themeMode
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

	c.JSON(http.StatusOK, gin.H{
		"theme_mode": themeMode,
	})
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

func normalizeThemeMode(input string) (string, bool) {
	mode := strings.ToLower(strings.TrimSpace(input))
	switch mode {
	case "system", "dark", "light":
		return mode, true
	default:
		return "", false
	}
}
