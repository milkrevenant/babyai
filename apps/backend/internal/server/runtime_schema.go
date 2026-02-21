package server

import (
	"context"
	"fmt"
	"strings"

	"github.com/jackc/pgx/v5/pgxpool"
)

func ValidateRuntimeSchema(ctx context.Context, pool *pgxpool.Pool) error {
	if pool == nil {
		return fmt.Errorf("database pool is nil")
	}

	requiredColumns := []struct {
		table  string
		column string
	}{
		{table: "Event", column: "state"},
		{table: "ChatSession", column: "memorySummary"},
		{table: "ChatSession", column: "memorySummarizedCount"},
		{table: "ChatSession", column: "memorySummaryUpdatedAt"},
	}

	for _, item := range requiredColumns {
		ok, err := columnExists(ctx, pool, item.table, item.column)
		if err != nil {
			return fmt.Errorf(
				"failed checking schema for %s.%s: %w",
				item.table,
				item.column,
				err,
			)
		}
		if !ok {
			return fmt.Errorf(
				"required column %s.%s is missing; run prisma migrate deploy",
				item.table,
				item.column,
			)
		}
	}

	return nil
}

func columnExists(ctx context.Context, pool *pgxpool.Pool, tableName, columnName string) (bool, error) {
	table := strings.TrimSpace(tableName)
	column := strings.TrimSpace(columnName)
	if table == "" || column == "" {
		return false, fmt.Errorf("table/column must not be empty")
	}
	var exists bool
	err := pool.QueryRow(
		ctx,
		`SELECT EXISTS (
		   SELECT 1
		   FROM information_schema.columns
		   WHERE table_schema = current_schema()
		     AND lower(table_name) = lower($1)
		     AND lower(column_name) = lower($2)
		 )`,
		table,
		column,
	).Scan(&exists)
	if err != nil {
		return false, err
	}
	return exists, nil
}
