#!/bin/sh
# ABOUTME: Run parts/recover_sprint.dip against a fixture inside a temp workspace.
# ABOUTME: Usage: scripts/test_recover_sprint.sh [fixture-name]   (default: recover-scope-failure)
set -eu

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURE="${1:-recover-scope-failure}"
FIXTURE_DIR="$REPO_ROOT/tests/fixtures/$FIXTURE"
TEST_PIPELINE="$REPO_ROOT/tests/recover_sprint_test.dip"

if [ ! -d "$FIXTURE_DIR" ]; then
  echo "fixture not found: $FIXTURE_DIR" >&2
  echo "available:" >&2
  ls "$REPO_ROOT/tests/fixtures" 2>/dev/null >&2
  exit 1
fi

WORK=$(mktemp -d -t recover-sprint-test-XXXXXX)
trap 'rm -rf "$WORK"' EXIT

echo "→ fixture:   $FIXTURE"
echo "→ workspace: $WORK"

cp -R "$FIXTURE_DIR/.ai" "$WORK/.ai"
cd "$WORK"

echo "→ running tracker $TEST_PIPELINE"
tracker --no-tui "$TEST_PIPELINE"
status=$?

if [ $status -eq 0 ]; then
  echo
  echo "✓ test passed ($FIXTURE)"
  echo "  artifacts:"
  ls -la .ai/sprints/SPRINT-*-recovery-analysis.md 2>/dev/null | awk '{print "    "$NF}' || true
  [ -f .ai/redecompose-request.yaml ] && echo "    .ai/redecompose-request.yaml" || true
  echo "    .ai/managers/recovery-journal.md"
else
  echo
  echo "✗ test failed (tracker exit=$status)" >&2
  echo "  workspace preserved at: $WORK" >&2
  trap - EXIT
  exit $status
fi
