package store

import (
	"context"
	"database/sql"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestOpenDB(t *testing.T) {
	t.Run("enables WAL mode", func(t *testing.T) {
		path := newTempDBPath(t)
		db, err := OpenDB(path)
		if err != nil {
			t.Fatalf("open db: %v", err)
		}
		defer func() { _ = db.Close() }()

		journalMode := queryPragmaString(t, db, "journal_mode")
		if journalMode != "wal" {
			t.Fatalf("expected journal_mode to be 'wal', got %q", journalMode)
		}
	})

	t.Run("enables foreign keys", func(t *testing.T) {
		path := newTempDBPath(t)
		db, err := OpenDB(path)
		if err != nil {
			t.Fatalf("open db: %v", err)
		}
		defer func() { _ = db.Close() }()

		foreignKeys := queryPragmaInt(t, db, "foreign_keys")
		if foreignKeys != 1 {
			t.Fatalf("expected foreign_keys to be 1, got %d", foreignKeys)
		}
	})

	t.Run("returns a usable handle", func(t *testing.T) {
		path := newTempDBPath(t)
		db, err := OpenDB(path)
		if err != nil {
			t.Fatalf("open db: %v", err)
		}
		defer func() { _ = db.Close() }()

		_, err = db.Exec(`CREATE TABLE health_probe (id INTEGER PRIMARY KEY)`)
		if err != nil {
			t.Fatalf("failed to create health_probe table: %v", err)
		}
	})
}

func TestHealthCheck(t *testing.T) {
	t.Run("returns nil for a valid database path", func(t *testing.T) {
		path := newTempDBPath(t)
		db, err := OpenDB(path)
		if err != nil {
			t.Fatalf("open db: %v", err)
		}
		if err := db.Close(); err != nil {
			t.Fatalf("close db: %v", err)
		}

		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		defer cancel()

		err = HealthCheck(ctx, path)
		if err != nil {
			t.Fatalf("expected nil error, got: %v", err)
		}
	})

	t.Run("returns an error for a missing parent directory", func(t *testing.T) {
		root := t.TempDir()
		path := filepath.Join(root, "does-not-exist", "agent.sqlite")

		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		defer cancel()

		err := HealthCheck(ctx, path)
		if err == nil {
			t.Fatal("expected error for missing parent directory, got nil")
		}
	})

	t.Run("returns an error for a corrupt sqlite file", func(t *testing.T) {
		dir := t.TempDir()
		corruptPath := filepath.Join(dir, "corrupt.sqlite")

		if err := os.WriteFile(corruptPath, []byte("not a sqlite database"), 0o600); err != nil {
			t.Fatalf("write corrupt file: %v", err)
		}

		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		defer cancel()

		err := HealthCheck(ctx, corruptPath)
		if err == nil {
			t.Fatal("expected error for corrupt sqlite file, got nil")
		}
	})
}

func newTempDBPath(t *testing.T) string {
	t.Helper()
	return filepath.Join(t.TempDir(), "agent.sqlite")
}

func queryPragmaString(t *testing.T, db *sql.DB, pragma string) string {
	t.Helper()
	var value string
	query := "PRAGMA " + pragma + ";"
	if err := db.QueryRow(query).Scan(&value); err != nil {
		t.Fatalf("query pragma %s: %v", pragma, err)
	}
	return value
}

func queryPragmaInt(t *testing.T, db *sql.DB, pragma string) int {
	t.Helper()
	var value int
	query := "PRAGMA " + pragma + ";"
	if err := db.QueryRow(query).Scan(&value); err != nil {
		t.Fatalf("query pragma %s: %v", pragma, err)
	}
	return value
}
