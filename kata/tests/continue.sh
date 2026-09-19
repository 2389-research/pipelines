#!/bin/sh
# ABOUTME: Checks the one-time warm continue: override file, marker, exhaustion, and the real tracker restart loop.
# ABOUTME: Runs the script directly, then drives a tool-only fixture graph through the actual tracker binary.
set -eu

pipeline_dir=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd -P)
script="$pipeline_dir/scripts/continue-implement.sh"
test_root=$(mktemp -d)
test_root=$(cd "$test_root" && pwd -P)
trap 'rm -rf "$test_root"' EXIT
trap 'exit 130' HUP INT TERM
KATA_ISOLATE_ROOT="$test_root/isolate"
export KATA_ISOLATE_ROOT
# shellcheck source=/dev/null
. "$pipeline_dir/tests/isolate.sh"
command -v tracker >/dev/null
command -v jq >/dev/null

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  [ ! -f "$test_root/output" ] || cat "$test_root/output" >&2
  exit 1
}

# Unit: the first call grants the continue, the second call is exhausted.
workdir="$test_root/unit"
run_dir="$workdir/.tracker/runs/test"
mkdir -p "$run_dir"
TRACKER_RUN_DIR="$run_dir" TRACKER_WORKDIR="$workdir" TRACKER_RUN_ID=test sh "$script" >"$test_root/output" 2>&1 ||
  fail 'first continue call failed'
grep -Fx 'continue-ok' "$test_root/output" >/dev/null || fail 'first continue call did not print continue-ok'
[ "$(cat "$workdir/.tracker/turn_overrides/Implement")" = 450 ] || fail 'override file does not hold 450'
jq -e '.attempt == 1 and .max_turns == 450 and .run_id == "test"' "$run_dir/continue-implement.json" >/dev/null ||
  fail 'continue marker has the wrong shape'
if TRACKER_RUN_DIR="$run_dir" TRACKER_WORKDIR="$workdir" TRACKER_RUN_ID=test sh "$script" >"$test_root/output" 2>&1; then
  fail 'second continue call succeeded'
fi
grep -Fx 'continue-exhausted' "$test_root/output" >/dev/null || fail 'second continue call did not print continue-exhausted'
[ "$(cat "$workdir/.tracker/turn_overrides/Implement")" = 450 ] || fail 'second call changed the override'
if (unset TRACKER_RUN_DIR; TRACKER_WORKDIR="$workdir" sh "$script") >"$test_root/output" 2>&1; then
  fail 'missing TRACKER_RUN_DIR was accepted'
fi
printf 'ok - continue grants one override of 450 turns and then reports exhaustion\n'

# Integration: the real tracker restarts Implement after a granted continue and hands off after exhaustion.
workflow="$test_root/workflow"
mkdir -p "$workflow/scripts"
cp "$script" "$workflow/scripts/continue-implement.sh"
cat >"$workflow/continue.dip" <<'DIP'
# ABOUTME: Tool-only stand-in for complete.dip's worker loop: claim, implement, one continue, handoff.
# ABOUTME: Exercises the restart edge through the real tracker without models or kata.
workflow ContinueFixture
  goal: "Restart the worker once after a granted continue."
  start: ClaimNext
  exit: Exit

  tool ClaimNext
    command:
      true

  tool Implement
    command_file: implement.sh

  tool ContinueImplement
    command_file: scripts/continue-implement.sh

  tool Handoff
    command_file: handoff.sh

  tool Exit
    command:
      true

  edges
    ClaimNext -> Implement
    Implement -> Exit  when ctx.outcome = success
    Implement -> ContinueImplement  when ctx.outcome = fail
    ContinueImplement -> Implement  when ctx.outcome = success  restart: true
    ContinueImplement -> Handoff  when ctx.outcome = fail
    Handoff -> Exit
DIP
cat >"$workflow/implement.sh" <<'SH'
#!/bin/sh
# ABOUTME: Fails until the visit count reaches the configured success point.
# ABOUTME: Records each visit so the test can count worker restarts.
set -eu
fixture="$TRACKER_WORKDIR/.tracker/continue-fixture"
printf '%s\n' "$TRACKER_RUN_ID" >>"$fixture/visits"
visits=$(wc -l <"$fixture/visits" | tr -d ' ')
[ "$visits" -ge "$(cat "$fixture/succeed-at")" ]
SH
cat >"$workflow/handoff.sh" <<'SH'
#!/bin/sh
# ABOUTME: Stand-in handoff that reports and fails like the real one.
# ABOUTME: Keeps the fixture graph's failure route observable.
printf 'handoff-ok\n'
exit 1
SH

run_fixture() {
  workdir="$test_root/$1"
  git init -q -b main "$workdir"
  mkdir -p "$workdir/.tracker/continue-fixture"
  printf '%s\n' "$2" >"$workdir/.tracker/continue-fixture/succeed-at"
  status=0
  (cd "$workdir" && tracker --git off --workdir "$workdir" --json --no-tui "$workflow/continue.dip") \
    >"$test_root/output" 2>&1 || status=$?
  run_id=$(jq -Rr 'fromjson? | select(.source == "pipeline" and .type == "pipeline_started") | .run_id' "$test_root/output" | head -n 1)
  [ -n "$run_id" ] || fail "$1: no pipeline_started event"
  child="$workdir/.tracker/runs/$run_id"
  visits=$(wc -l <"$workdir/.tracker/continue-fixture/visits" | tr -d ' ')
  last=$(jq -Rr 'fromjson? | select(.source == "pipeline" and (.type | startswith("pipeline_"))) | .type' \
    "$child/activity.jsonl" | tail -n 1)
}

run_fixture granted 2
[ "$status" -eq 0 ] || fail 'granted: tracker exited non-zero'
[ "$visits" -eq 2 ] || fail "granted: worker ran $visits times, expected 2"
[ "$last" = pipeline_completed ] || fail "granted: last pipeline event is $last"
[ "$(cat "$workdir/.tracker/turn_overrides/Implement")" = 450 ] || fail 'granted: override missing after the run'
jq -e '.attempt == 1' "$child/continue-implement.json" >/dev/null || fail 'granted: continue marker missing'
jq -e '.outcome == "success" and (.context_updates.tool_stdout | split("\n") | any(. == "continue-ok"))' \
  "$child/ContinueImplement/status.json" >/dev/null || fail 'granted: ContinueImplement status is wrong'
printf 'ok - the real tracker restarts Implement once after a granted continue\n'

run_fixture exhausted 99
[ "$status" -ne 0 ] || fail 'exhausted: tracker exited zero'
[ "$visits" -eq 2 ] || fail "exhausted: worker ran $visits times, expected 2"
[ "$last" = pipeline_failed ] || fail "exhausted: last pipeline event is $last"
jq -e '.outcome == "fail" and (.context_updates.tool_stdout | split("\n") | any(. == "continue-exhausted"))' \
  "$child/ContinueImplement/status.json" >/dev/null || fail 'exhausted: ContinueImplement status is wrong'
jq -e '.context_updates.tool_stdout | split("\n") | any(. == "handoff-ok")' "$child/Handoff/status.json" >/dev/null ||
  fail 'exhausted: Handoff did not run'
printf 'ok - the real tracker hands off after the continue is exhausted\n'
