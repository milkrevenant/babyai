package db

import (
	"net/url"
	"testing"
)

func TestNormalizeDatabaseURLPreservesCloudSQLHostQuery(t *testing.T) {
	raw := "postgresql://user:pass@localhost:5432/app?host=%2Fcloudsql%2Fproj%3Aregion%3Ainstance&sslmode=disable&schema=public"
	got := normalizeDatabaseURL(raw)

	parsed, err := url.Parse(got)
	if err != nil {
		t.Fatalf("parse normalized url: %v", err)
	}
	query := parsed.Query()
	if query.Get("host") != "/cloudsql/proj:region:instance" {
		t.Fatalf("expected host query preserved, got %q", query.Get("host"))
	}
	if query.Get("sslmode") != "disable" {
		t.Fatalf("expected sslmode preserved, got %q", query.Get("sslmode"))
	}
	if query.Get("schema") != "" {
		t.Fatalf("expected unsupported query removed, got schema=%q", query.Get("schema"))
	}
}

func TestNormalizeDatabaseURLConvertsKnownSchemes(t *testing.T) {
	cases := []struct {
		name string
		raw  string
	}{
		{
			name: "prisma+postgres",
			raw:  "prisma+postgres://user:pass@localhost:5432/app",
		},
		{
			name: "postgresql+psycopg",
			raw:  "postgresql+psycopg://user:pass@localhost:5432/app",
		},
		{
			name: "postgresql",
			raw:  "postgresql://user:pass@localhost:5432/app",
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := normalizeDatabaseURL(tc.raw)
			parsed, err := url.Parse(got)
			if err != nil {
				t.Fatalf("parse normalized url: %v", err)
			}
			if parsed.Scheme != "postgres" {
				t.Fatalf("expected postgres scheme, got %q", parsed.Scheme)
			}
		})
	}
}
