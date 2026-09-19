#!/bin/sh
# ABOUTME: Exercises the actual conversational workflow with a configured model provider.
# ABOUTME: Uses disposable workspaces and checks files, approval routes, memory, and resume.
set -eu

case ${1:-} in
  --help|-h)
    printf '%s\n' 'Usage: sh tracker-claw/tests/live.sh' \
      'Runs real model calls (billable) in temporary directories; keeps logs for inspection.' \
      'Requires tracker, jq, and provider credentials configured with tracker setup.'
    exit 0 ;;
  '') ;;
  *) printf 'Unexpected argument. Use --help for usage.\n' >&2; exit 2 ;;
esac

PIPELINE_DIR=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd -P)
test -f "$PIPELINE_DIR/agent.dip" || {
  printf 'Missing workflow: %s/agent.dip\n' "$PIPELINE_DIR" >&2
  exit 1
}
command -v tracker >/dev/null
command -v jq >/dev/null
LIVE_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/tracker-claw-live.XXXXXX")
export XDG_STATE_HOME="$LIVE_ROOT/state"
printf 'Live test artifacts: %s\n' "$LIVE_ROOT"

fail() {
  printf 'FAIL: %s\nInspect %s\n' "$1" "$LIVE_ROOT" >&2
  exit 1
}

run_case() {
  case_name=$1
  shift
  mkdir -p "$LIVE_ROOT/$case_name"
  tracker --no-tui --git off --max-wall-time 10m --max-tokens 50000 \
    -w "$LIVE_ROOT/$case_name" "$@" "$PIPELINE_DIR/agent.dip" \
    >"$LIVE_ROOT/$case_name.log" 2>&1
}

checkpoint() {
  find "$LIVE_ROOT/$1/.tracker/runs" -name checkpoint.json -type f
}

starts() {
  jq -s --arg node "$2" '[.[] | select(.type == "stage_started" and .node_id == $node)] | length' \
    "$LIVE_ROOT/$1"/.tracker/runs/*/activity.jsonl
}

# The proposal must have no tools: neither rejection nor EOF may create a file.
printf '%s\n' 'Create denied.txt containing DENIED and verify it. Do not create any other files.' Stop |
  run_case rejected "$@" || fail 'rejected request did not finish cleanly'
test ! -e "$LIVE_ROOT/rejected/denied.txt" || fail 'rejection wrote a file'
test "$(starts rejected Execute)" = 0 || fail 'rejection entered Execute'
printf 'PASS: rejection never executes\n'

printf '%s\n' 'Create denied.txt containing DENIED and verify it. Do not create any other files.' |
  run_case eof "$@" || fail 'approval EOF did not select Stop'
test ! -e "$LIVE_ROOT/eof/denied.txt" || fail 'EOF wrote a file'
test "$(starts eof Execute)" = 0 || fail 'EOF entered Execute'
printf 'PASS: missing approval stops\n'

# Revise the target, execute once, then require memory on a distinct next task.
printf '%s\n' \
  'Create first.txt with the exact line ORBIT-7492. This token is my session code. Verify the file contents. Do not create other files or use git.' \
  Revise \
  'Change the target to approved.txt; keep the exact session code ORBIT-7492. Do not create first.txt. Verify approved.txt and report the session code for future tasks.' \
  Approve 'Next task' \
  'Create recalled.txt containing only the session code from the preceding completed task. Use session memory to recover that code. Verify the contents. Do not change approved.txt or use git.' \
  Approve Stop |
  run_case conversation "$@" || fail 'revised multi-task conversation failed'
test ! -e "$LIVE_ROOT/conversation/first.txt" || fail 'superseded proposal executed'
test "$(cat "$LIVE_ROOT/conversation/approved.txt")" = ORBIT-7492 || fail 'revised task result differs'
test "$(cat "$LIVE_ROOT/conversation/recalled.txt")" = ORBIT-7492 || fail 'next task lost memory'
test "$(starts conversation Execute)" = 2 || fail 'expected exactly two approved executions'
test "$(starts conversation RevisePlan)" = 1 || fail 'revision did not reach RevisePlan'
grep -F 'ORBIT-7492' "$LIVE_ROOT/conversation"/.tracker/runs/*/Propose/prompt.md >/dev/null ||
  fail 'second proposal did not receive the remembered code'
printf 'PASS: revision, two approvals, actual writes, and session memory\n'

# An invalid choice leaves a checkpoint at Approval. Resume must not re-plan.
if printf '%s\n' 'Create resumed.txt with the exact line RESUMED. Verify it. Do not create other files or use git.' invalid-choice |
  run_case resume "$@"; then
  fail 'invalid approval unexpectedly succeeded'
fi
resume_cp=$(checkpoint resume)
test -n "$resume_cp" || fail 'invalid approval produced no checkpoint'
jq -e '.current_node == "Approval"' "$resume_cp" >/dev/null || fail 'checkpoint is not at Approval'
test ! -e "$LIVE_ROOT/resume/resumed.txt" || fail 'invalid approval executed'
run_id=$(jq -r '.run_id' "$resume_cp")
mv "$LIVE_ROOT/resume.log" "$LIVE_ROOT/resume-invalid-choice.log"
printf '%s\n' Approve Stop |
  run_case resume "$@" --resume "$run_id" || fail 'gate resume failed'
test "$(cat "$LIVE_ROOT/resume/resumed.txt")" = RESUMED || fail 'resumed execution did not write result'
test "$(starts resume Propose)" = 1 || fail 'gate resume repeated planning'
test "$(starts resume Execute)" = 1 || fail 'gate resume repeated execution'
printf 'PASS: approval checkpoint resume without repeating work\n'

# An unavailable input is a task failure, not permission to invent or repair it.
if printf '%s\n' \
  'Read required-input.txt and report its contents. If it is missing, the task is blocked: report failure without creating it or any other file. Do not use git.' \
  Approve Stop |
  run_case blocked "$@"; then
  fail 'stopping after a failed task reported a successful run'
fi
test ! -e "$LIVE_ROOT/blocked/required-input.txt" || fail 'blocked task invented missing input'
test "$(starts blocked Execute)" = 1 || fail 'blocked execution retried automatically'
test "$(starts blocked Review)" = 1 || fail 'blocked task skipped human review'
jq -e '.context["response.Execute"] | test("STATUS: fail")' "$(checkpoint blocked)" >/dev/null ||
  fail 'blocked task was not reported as failed'
printf 'PASS: task failure reaches review without automatic retry\n'
printf 'All live scenarios passed. Artifacts: %s\n' "$LIVE_ROOT"
