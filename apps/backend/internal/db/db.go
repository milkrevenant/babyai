package db

import (
	"context"
	"net/url"
	"strings"

	"github.com/jackc/pgx/v5/pgxpool"
)

var supportedPGQueryKeys = map[string]struct{}{
	"application_name":       {},
	"channel_binding":        {},
	"client_encoding":        {},
	"connect_timeout":        {},
	"gssencmode":             {},
	"keepalives":             {},
	"keepalives_count":       {},
	"keepalives_idle":        {},
	"keepalives_interval":    {},
	"krbsrvname":             {},
	"options":                {},
	"passfile":               {},
	"service":                {},
	"sslcert":                {},
	"sslcrl":                 {},
	"sslkey":                 {},
	"sslmode":                {},
	"sslpassword":            {},
	"sslrootcert":            {},
	"target_session_attrs":   {},
}

func Connect(ctx context.Context, rawURL string) (*pgxpool.Pool, error) {
	normalized := normalizeDatabaseURL(rawURL)
	cfg, err := pgxpool.ParseConfig(normalized)
	if err != nil {
		return nil, err
	}
	return pgxpool.NewWithConfig(ctx, cfg)
}

func normalizeDatabaseURL(rawURL string) string {
	normalized := strings.TrimSpace(rawURL)
	if strings.HasPrefix(normalized, "prisma+postgres://") {
		normalized = strings.Replace(normalized, "prisma+postgres://", "postgres://", 1)
	}
	if strings.HasPrefix(normalized, "postgresql+psycopg://") {
		normalized = strings.Replace(normalized, "postgresql+psycopg://", "postgres://", 1)
	}
	if strings.HasPrefix(normalized, "postgresql://") {
		normalized = strings.Replace(normalized, "postgresql://", "postgres://", 1)
	}

	parsed, err := url.Parse(normalized)
	if err != nil {
		return normalized
	}
	if parsed.Scheme != "postgres" && parsed.Scheme != "postgresql" {
		return normalized
	}

	queries := parsed.Query()
	filtered := make(url.Values)
	for key, values := range queries {
		if _, ok := supportedPGQueryKeys[key]; ok {
			for _, v := range values {
				filtered.Add(key, v)
			}
		}
	}
	parsed.RawQuery = filtered.Encode()
	return parsed.String()
}
