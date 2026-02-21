package main

import (
	"context"
	"errors"
	"log"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"babyai/apps/backend/internal/config"
	"babyai/apps/backend/internal/db"
	"babyai/apps/backend/internal/server"
)

func main() {
	cfg := config.Load()
	if err := cfg.Validate(); err != nil {
		log.Fatalf("invalid config: %v", err)
	}

	ctx := context.Background()
	pool, err := db.Connect(ctx, cfg.DatabaseURL)
	if err != nil {
		log.Fatalf("database connect failed: %v", err)
	}
	defer pool.Close()

	if err := pool.Ping(ctx); err != nil {
		log.Fatalf("database ping failed: %v", err)
	}
	if err := server.ValidateRuntimeSchema(ctx, pool); err != nil {
		log.Fatalf("database schema mismatch: %v", err)
	}
	if strings.EqualFold(strings.TrimSpace(os.Getenv("AUTO_ENABLE_PG_STAT_STATEMENTS")), "true") {
		if _, err := pool.Exec(ctx, `CREATE EXTENSION IF NOT EXISTS pg_stat_statements`); err != nil {
			// Best-effort only: some managed DB roles cannot create extensions,
			// or shared_preload_libraries may not include pg_stat_statements yet.
			log.Printf("optional extension pg_stat_statements not enabled: %v", err)
		}
	}

	app := server.New(cfg, pool)
	httpServer := &http.Server{
		Addr:              ":" + cfg.AppPort,
		Handler:           app.Router(),
		ReadHeaderTimeout: 10 * time.Second,
	}

	go func() {
		log.Printf("babyai api listening on http://localhost:%s", cfg.AppPort)
		if err := httpServer.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Fatalf("server failed: %v", err)
		}
	}()

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)
	<-stop

	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := httpServer.Shutdown(shutdownCtx); err != nil {
		log.Printf("graceful shutdown failed: %v", err)
	}
}
