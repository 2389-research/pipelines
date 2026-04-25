package integration

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

var agentBin string

func TestMain(m *testing.M) {
	tmp, err := os.MkdirTemp("", "agent-smoke-*")
	if err != nil {
		fmt.Fprintln(os.Stderr, "mkdirtemp:", err)
		os.Exit(1)
	}
	defer os.RemoveAll(tmp)

	agentBin = filepath.Join(tmp, "agent")
	cmd := exec.Command("go", "build", "-o", agentBin, filepath.Join("..", "..", "cmd", "agent"))
	if out, err := cmd.CombinedOutput(); err != nil {
		fmt.Fprintf(os.Stderr, "go build failed: %v\n%s\n", err, out)
		os.Exit(1)
	}

	os.Exit(m.Run())
}

func TestSmoke(t *testing.T) {
	t.Run("version exits 0 and prints non-empty output", func(t *testing.T) {
		out, err := exec.Command(agentBin, "version").Output()
		if err != nil {
			t.Fatalf("agent version: %v", err)
		}
		if strings.TrimSpace(string(out)) == "" {
			t.Fatal("expected non-empty version output")
		}
	})

	t.Run("doctor exits 0 and output contains go version", func(t *testing.T) {
		out, err := exec.Command(agentBin, "doctor").Output()
		if err != nil {
			t.Fatalf("agent doctor: %v", err)
		}
		if !strings.Contains(string(out), "go:") {
			t.Fatalf("expected 'go:' in doctor output, got: %s", out)
		}
	})
}
