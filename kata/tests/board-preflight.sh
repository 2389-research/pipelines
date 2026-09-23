#!/bin/sh
# ABOUTME: Checks board-preflight.sh: parent-env guard, git-root check, managed excludes, ledger, and run-id seed.
# ABOUTME: Runs the script directly in throwaway Git repos; the board integration test exercises it under tracker.
set -eu

pipeline_dir=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd -P)
preflight="$pipeline_dir/scripts/board-preflight.sh"
test_root=$(mktemp -d)
test_root=$(cd "$test_root" && pwd -P)
trap 'rm -rf "$test_root"' EXIT
trap 'exit 130' HUP INT TERM
command -v jq >/dev/null

KATA_ISOLATE_ROOT="$test_root/isolate"
export KATA_ISOLATE_ROOT
# shellcheck source=/dev/null
. "$pipeline_dir/tests/isolate.sh"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  [ ! -f "$test_root/out" ] || { printf -- '--- output ---\n' >&2; cat "$test_root/out" >&2; }
  exit 1
}

count=0
# Builds a fresh clean repo and points a fresh parent run at it. Sets repo, run_dir, run_id, and the
# TRACKER_* the board parent gives its nodes, all in this shell so a case can override before running.
fresh() {
  count=$((count + 1))
  repo="$test_root/repo$count"
  git init -q -b main "$repo"
  repo=$(cd "$repo" && pwd -P)
  ( cd "$repo" && git commit -q --allow-empty -m "root" )
  run_id="board-parent-$count"
  run_dir="$repo/.tracker/runs/$run_id"
  export TRACKER_WORKDIR="$repo" TRACKER_RUN_DIR="$run_dir" TRACKER_RUN_ID="$run_id"
}

run_preflight() {
  status=0
  sh "$preflight" "$pipeline_dir" >"$test_root/out" 2>&1 || status=$?
}

# --- happy path -----------------------------------------------------------
fresh
run_preflight
[ "$status" -eq 0 ] || fail "happy path exited $status"
grep -Fx 'preflight-ok' "$test_root/out" >/dev/null || fail 'happy path did not print preflight-ok'
ledger="$run_dir/board/state.json"
[ -f "$ledger" ] || fail 'ledger was not created'
jq -e --arg ws "$repo" '.workspace == $ws and (.runs | length) == 0 and .finished == false and (.pipeline | endswith("board-item.dip"))' \
  "$ledger" >/dev/null || { cat "$ledger" >&2; fail 'ledger has the wrong shape'; }
exclude="$repo/.git/info/exclude"
grep -Fx '/.tracker/' "$exclude" >/dev/null || fail 'exclude is missing /.tracker/'
grep -Fx '# BEGIN kata board managed excludes' "$exclude" >/dev/null || fail 'exclude is missing the begin marker'
grep -Fx '# END kata board managed excludes' "$exclude" >/dev/null || fail 'exclude is missing the end marker'
for entry in /ClaimNext/ /Implement/ /ReviewCorrectness/ /Handoff/ /Exit/ \
  /selected.json /verification.txt /completion.md /review-correctness.approved /review-scope.approved \
  /handoff.md /handoff-comment.md /handoff.json /question.md /continue-implement.json; do
  grep -Fx "$entry" "$exclude" >/dev/null || fail "exclude is missing $entry"
done
# Every board-item.dip node and every body artifact is listed exactly once.
nodes=$(awk '$1 ~ /^(tool|agent|parallel|fan_in|human|subgraph)$/ {print $2}' "$pipeline_dir/board-item.dip" | wc -l | tr -d ' ')
block_dirs=$(sed -n '/# BEGIN kata board managed excludes/,/# END kata board managed excludes/p' "$exclude" | grep -c '/$' || true)
[ "$block_dirs" -eq "$nodes" ] || fail "exclude lists $block_dirs node dirs, expected $nodes"
runidfile="$repo/.tracker/kata-board-run-id"
[ -f "$runidfile" ] || fail 'run-id file was not seeded'
seeded=$(cat "$runidfile")
case "$seeded" in "$run_id"-??????) ;; *) fail "run-id '$seeded' lacks the parent prefix and six hex chars" ;; esac
[ -z "$(cd "$repo" && git status --porcelain --untracked-files=normal)" ] || \
  fail 'working tree is not clean after preflight (excludes do not cover the board paths)'
printf 'ok - preflight seeds the ledger, managed excludes, and run-id on a clean board\n'

# --- idempotent on sweep-again -------------------------------------------
run_preflight
[ "$status" -eq 0 ] || fail "second preflight exited $status"
begins=$(grep -Fc '# BEGIN kata board managed excludes' "$exclude" || true)
[ "$begins" -eq 1 ] || fail "second preflight duplicated the exclude block ($begins begin markers)"
[ "$(cat "$runidfile")" = "$seeded" ] || fail 'second preflight rotated a run-id it already owns'
printf 'ok - a second preflight is idempotent and keeps its own run-id\n'

# --- ledger re-entry reset ------------------------------------------------
jq '.finished = true | .stop_reason = "three consecutive failed children" | .stop_child = "x"' "$ledger" >"$ledger.t" && mv "$ledger.t" "$ledger"
run_preflight
[ "$status" -eq 0 ] || fail "re-entry preflight exited $status"
jq -e '.finished == false and (has("stop_reason") | not) and (has("stop_child") | not)' "$ledger" >/dev/null || \
  { cat "$ledger" >&2; fail 're-entry did not reset finished and clear the stop fields'; }
printf 'ok - preflight resets finished and clears stop fields when it re-enters\n'

# --- stale run-id from another parent is replaced -------------------------
printf 'someotherparent-aaaaaa\n' >"$runidfile"
run_preflight
[ "$status" -eq 0 ] || fail "stale run-id preflight exited $status"
repaired=$(cat "$runidfile")
case "$repaired" in "$run_id"-??????) ;; *) fail "preflight kept a foreign run-id '$repaired'" ;; esac
printf 'ok - preflight replaces a run-id left by another parent run\n'

# --- missing parent env stops with no marker -----------------------------
fresh
unset TRACKER_RUN_DIR
run_preflight
[ "$status" -ne 0 ] || fail 'preflight passed with TRACKER_RUN_DIR unset'
grep -Fx 'preflight-ok' "$test_root/out" >/dev/null && fail 'preflight printed its marker despite a missing env'
export TRACKER_RUN_DIR="$run_dir"
printf 'ok - preflight stops without a marker when the parent env is missing\n'

# --- collision with a body artifact --------------------------------------
fresh
: >"$repo/completion.md"
run_preflight
[ "$status" -ne 0 ] || fail 'preflight passed with a colliding completion.md'
grep -F 'completion.md' "$test_root/out" >/dev/null || fail 'collision message does not name the path'
grep -Fx 'preflight-ok' "$test_root/out" >/dev/null && fail 'preflight printed its marker despite a collision'
printf 'ok - preflight refuses to run when a body artifact path already exists\n'

# --- collision with a node directory -------------------------------------
fresh
mkdir "$repo/Implement"
run_preflight
[ "$status" -ne 0 ] || fail 'preflight passed with a colliding Implement/ directory'
grep -F 'Implement' "$test_root/out" >/dev/null || fail 'collision message does not name the node directory'
printf 'ok - preflight refuses to run when a node directory path already exists\n'

# --- workspace is not the Git root ---------------------------------------
fresh
mkdir "$repo/sub"
export TRACKER_WORKDIR="$repo/sub"
run_preflight
[ "$status" -ne 0 ] || fail 'preflight passed when the workspace was not the Git root'
grep -Fx 'preflight-ok' "$test_root/out" >/dev/null && fail 'preflight printed its marker off the Git root'
printf 'ok - preflight refuses to run when the workspace is not the Git root\n'

printf 'ok - board-preflight.sh\n'
