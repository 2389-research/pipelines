#!/bin/sh
# ABOUTME: Reproduce the RewriteOutput failure mode + assert the new taxonomy-driven
# ABOUTME: prompt actually fixes it. Usage: dr/scripts/test_rewrite_output.sh [fixture-name]
#
# How it works:
#   1. Copies fixture/.ai into a temp workspace
#   2. Fixture has .validate-output-attempts.txt = 2 pre-seeded so the FIRST
#      validate_output call increments to 3 → routes directly to RewriteOutput
#      (skipping the write_sprint_docs retry phase that costs 10+ min)
#   3. Runs spec_to_sprints.dip (check_resume → resume-validate → validate_output
#      → RewriteOutput → validate_output → ideally 'valid' → commit_output → Exit)
#   4. Asserts the final state is valid by running validate_output's checks again
#
# Iteration loop: edit dr/docs/validation_error_taxonomy.md or RewriteOutput's
# prompt, re-run this script. ~2-5 min per iteration (RewriteOutput is one LLM call).
set -eu

DR_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURE="${1:-rewrite-output-stuck}"
FIXTURE_DIR="$DR_ROOT/tests/fixtures/$FIXTURE"
PIPELINE="$DR_ROOT/spec_to_sprints.dip"
TIMEOUT_MIN=15

if [ ! -d "$FIXTURE_DIR/.ai" ]; then
  echo "fixture not found: $FIXTURE_DIR/.ai" >&2
  echo "available:" >&2
  ls "$DR_ROOT/tests/fixtures" 2>/dev/null >&2
  exit 1
fi

WORK=$(mktemp -d -t rewrite-output-test-XXXXXX)
trap 'echo "(workspace preserved at $WORK)" >&2' EXIT

echo "→ fixture:    $FIXTURE"
echo "→ workspace:  $WORK"
echo "→ pipeline:   $PIPELINE"
echo "→ timeout:    ${TIMEOUT_MIN}m"
echo

cp -R "$FIXTURE_DIR/.ai" "$WORK/.ai"
# Copy spec.md if the fixture has one (find_spec needs it; otherwise pipeline routes to no_spec_exit)
[ -f "$FIXTURE_DIR/spec.md" ] && cp "$FIXTURE_DIR/spec.md" "$WORK/spec.md"
cd "$WORK"

# Run with --auto-approve so the EscalateOutput gate (if reached) takes its default.
# A 15-min timeout is the test's true ceiling — RewriteOutput plus validate retries
# should complete in 3-5min; longer means we're stuck.
echo "→ running tracker (--auto-approve, ${TIMEOUT_MIN}m timeout)..."
echo
if ! timeout "${TIMEOUT_MIN}m" tracker --no-tui --auto-approve "$PIPELINE" 2>&1 | tail -30; then
  status=$?
  echo
  if [ $status -eq 124 ]; then
    echo "✗ TEST FAILED: pipeline timed out after ${TIMEOUT_MIN}m"
    echo "  likely stuck — RewriteOutput didn't fix things and EscalateOutput is blocking"
  else
    echo "✗ TEST FAILED: tracker exited $status"
  fi
  exit 1
fi

echo
echo "→ verifying final state with validate_output's own checks..."

# Re-run validate_output's body inline to check the workspace is now clean.
errors=""
# Mirror validate_output's canonical-file filter: only check SPRINT-NNN.{yaml,md},
# skip plan-brief / review-brief / recovery-analysis / etc.
is_canonical() {
  case "$(basename "$1" .${2})" in
    SPRINT-[0-9A-Z]) return 0 ;;
    SPRINT-[0-9][0-9A-Z]) return 0 ;;
    SPRINT-[0-9][0-9][0-9A-Z]) return 0 ;;
    *) return 1 ;;
  esac
}
for f in .ai/sprints/SPRINT-*.yaml; do
  [ -f "$f" ] || continue
  is_canonical "$f" yaml || continue
  base=$(basename "$f")
  for field in id title status; do
    yq -e ".${field}" "$f" >/dev/null 2>&1 || errors="${errors} missing-${field}-${base}"
  done
  for field in lang runner test lint build; do
    yq -e ".stack.${field}" "$f" >/dev/null 2>&1 || errors="${errors} missing-stack-${field}-${base}"
  done
  yq -e '.validation.commands' "$f" >/dev/null 2>&1 || errors="${errors} missing-validation-${base}"
  yq -e '.dod' "$f" >/dev/null 2>&1 || errors="${errors} missing-dod-${base}"
done
for f in .ai/sprints/SPRINT-*.md; do
  [ -f "$f" ] || continue
  is_canonical "$f" md || continue
  base=$(basename "$f")
  for section in "## Scope" "## Requirements" "## Dependencies" "## Expected Artifacts" "## DoD" "## Validation"; do
    if ! grep -q "$section" "$f"; then
      tag=$(printf '%s' "$section" | sed 's/## //' | tr ' ' '-' | tr '[:upper:]' '[:lower:]')
      errors="${errors} missing-${tag}-${base}"
    fi
  done
done

if [ -n "$errors" ]; then
  echo "✗ TEST FAILED: validate_output checks still flag errors:"
  echo "$errors" | tr ' ' '\n' | grep -v '^$' | head -20 | sed 's/^/    /'
  total=$(echo "$errors" | tr ' ' '\n' | grep -v '^$' | wc -l | tr -d ' ')
  echo "  ($total total error tokens)"
  exit 1
fi

# Override trap to clean up only on success
trap 'rm -rf "$WORK"' EXIT
echo
echo "✓ TEST PASSED — all validate_output checks pass"
