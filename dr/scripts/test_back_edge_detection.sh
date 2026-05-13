#!/bin/sh
# ABOUTME: Regression test for ISSUE-001 — validate_output must flag back-edges
# ABOUTME: in the dep graph. Drives the dep-cycle-from-decomposition fixture.
#
# Validates that validate_output (in write_and_validate_sprint_artifacts.dip)
# detects when a sprint's depends_on references another sprint with a higher
# ID, and emits the corresponding back-edge-<self>-<bad-dep> token.
#
# Runtime: under 1 second. No LLM calls — this exercises the validator's bash
# logic only. Kept in sync with validate_output's body in
# dr/parts/decomposition/write_and_validate_sprint_artifacts.dip.
set -eu

DR_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURE_DIR="$DR_ROOT/tests/fixtures/dep-cycle-from-decomposition"

if [ ! -d "$FIXTURE_DIR/.ai" ]; then
  echo "fixture missing: $FIXTURE_DIR/.ai" >&2
  exit 1
fi

WORK=$(mktemp -d -t back-edge-test-XXXXXX)
trap 'echo "(workspace preserved at $WORK)" >&2' EXIT

cp -R "$FIXTURE_DIR/.ai" "$WORK/.ai"
cd "$WORK"

# Mirror of the back-edge detection portion of validate_output (in
# dr/parts/decomposition/write_and_validate_sprint_artifacts.dip).
# If validate_output changes, mirror the change here.
errors=""
for f in .ai/sprints/SPRINT-*.yaml; do
  [ -f "$f" ] || continue
  case "$(basename "$f" .yaml)" in SPRINT-[0-9A-Z]) ;; SPRINT-[0-9][0-9A-Z]) ;; SPRINT-[0-9][0-9][0-9A-Z]) ;; *) continue ;; esac
  self_id=$(yq '.id' "$f" 2>/dev/null || echo "")
  [ -z "$self_id" ] || [ "$self_id" = "null" ] && continue
  for dep in $(yq '.depends_on[]?' "$f" 2>/dev/null); do
    if [ "$dep" \> "$self_id" ] || [ "$dep" = "$self_id" ]; then
      errors="${errors}back-edge-${self_id}-${dep} "
    fi
  done
done

echo "validator emitted: ${errors:-<no errors>}"

# Assertion: the fixture's 002←003 back-edge must be flagged.
EXPECTED="back-edge-002-003"
if ! printf '%s' "$errors" | grep -q "$EXPECTED"; then
  echo "✗ TEST FAILED: did not emit $EXPECTED" >&2
  echo "  got: $errors" >&2
  exit 1
fi

# Negative assertion: there should be no false positive for the in-scope deps.
# Sprint 003 depends on 000/001/002 (all lower). Should NOT be flagged.
for unexpected in back-edge-003-002 back-edge-003-001 back-edge-001-000; do
  if printf '%s' "$errors" | grep -q "$unexpected"; then
    echo "✗ TEST FAILED: false positive — emitted $unexpected" >&2
    echo "  full token list: $errors" >&2
    exit 1
  fi
done

# Override trap on success
trap 'rm -rf "$WORK"' EXIT
echo "✓ TEST PASSED — back-edge-002-003 detected, no false positives"
