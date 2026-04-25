package store

import (
	"context"
	"fmt"
)

func HealthCheck(ctx context.Context, path string) error {
	db, err := OpenDB(path)
	if err != nil {
		return fmt.Errorf("open db: %w", err)
	}
	defer db.Close()

	if err := db.PingContext(ctx); err != nil {
		return fmt.Errorf("ping db: %w", err)
	}

	var value int
	if err := db.QueryRowContext(ctx, `SELECT 1`).Scan(&value); err != nil {
		return fmt.Errorf("query db: %w", err)
	}
	if value != 1 {
		return fmt.Errorf("unexpected health query result: %d", value)
	}
	return nil
}
