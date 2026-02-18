package config

import (
	"errors"
	"os"
	"strconv"
	"strings"

	"github.com/joho/godotenv"
)

type Config struct {
	AppEnv             string
	AppName            string
	APIPrefix          string
	AppPort            string
	DatabaseURL        string
	RedisURL           string
	DefaultTone        string
	JWTSecret          string
	JWTAlgorithm       string
	JWTAudience        string
	JWTIssuer          string
	AuthAutoCreateUser bool
	CORSAllowOrigins   []string
	OpenAIAPIKey       string
	OpenAIModel        string
	OpenAIBaseURL      string
	AIMaxOutputTokens  int
	AITimeoutSeconds   int
}

func Load() Config {
	_ = godotenv.Load(".env")

	return Config{
		AppEnv:             getEnv("APP_ENV", "local"),
		AppName:            getEnv("APP_NAME", "BabyAI API"),
		APIPrefix:          getEnv("API_PREFIX", "/api/v1"),
		AppPort:            getEnv("APP_PORT", "8000"),
		DatabaseURL:        getEnv("DATABASE_URL", "postgresql://babyai:babyai@localhost:5432/babyai"),
		RedisURL:           getEnv("REDIS_URL", "redis://localhost:6379/0"),
		DefaultTone:        getEnv("DEFAULT_TONE", "neutral"),
		JWTSecret:          getEnv("JWT_SECRET", ""),
		JWTAlgorithm:       getEnv("JWT_ALGORITHM", "HS256"),
		JWTAudience:        getEnv("JWT_AUDIENCE", ""),
		JWTIssuer:          getEnv("JWT_ISSUER", ""),
		AuthAutoCreateUser: getEnvBool("AUTH_AUTOCREATE_USER", false),
		CORSAllowOrigins: getEnvCSV(
			"CORS_ALLOW_ORIGINS",
			[]string{"http://localhost:5173", "http://127.0.0.1:5173", "http://localhost:3000"},
		),
		OpenAIAPIKey:      getEnv("OPENAI_API_KEY", ""),
		OpenAIModel:       getEnv("OPENAI_MODEL", "gpt-5-mini"),
		OpenAIBaseURL:     getEnv("OPENAI_BASE_URL", "https://api.openai.com/v1"),
		AIMaxOutputTokens: getEnvInt("AI_MAX_OUTPUT_TOKENS", 600),
		AITimeoutSeconds:  getEnvInt("AI_TIMEOUT_SECONDS", 20),
	}
}

func (c Config) Validate() error {
	if strings.TrimSpace(c.DatabaseURL) == "" {
		return errors.New("DATABASE_URL is required")
	}
	secret := strings.TrimSpace(c.JWTSecret)
	if secret == "" {
		return errors.New("JWT_SECRET is required")
	}
	if secret == "change-me-in-production" {
		return errors.New("JWT_SECRET must not use insecure default value")
	}
	if len(secret) < 16 {
		return errors.New("JWT_SECRET is too short; use at least 16 characters")
	}
	if strings.TrimSpace(c.JWTAlgorithm) == "" {
		return errors.New("JWT_ALGORITHM is required")
	}
	return nil
}

func getEnv(key, fallback string) string {
	if value, ok := os.LookupEnv(key); ok && value != "" {
		return value
	}
	return fallback
}

func getEnvCSV(key string, fallback []string) []string {
	raw, ok := os.LookupEnv(key)
	if !ok || strings.TrimSpace(raw) == "" {
		return fallback
	}

	parts := strings.Split(raw, ",")
	result := make([]string, 0, len(parts))
	for _, item := range parts {
		trimmed := strings.TrimSpace(item)
		if trimmed != "" {
			result = append(result, trimmed)
		}
	}
	if len(result) == 0 {
		return fallback
	}
	return result
}

func getEnvBool(key string, fallback bool) bool {
	value, ok := os.LookupEnv(key)
	if !ok || value == "" {
		return fallback
	}
	parsed, err := strconv.ParseBool(value)
	if err != nil {
		return fallback
	}
	return parsed
}

func getEnvInt(key string, fallback int) int {
	value, ok := os.LookupEnv(key)
	if !ok || strings.TrimSpace(value) == "" {
		return fallback
	}
	parsed, err := strconv.Atoi(strings.TrimSpace(value))
	if err != nil {
		return fallback
	}
	return parsed
}
