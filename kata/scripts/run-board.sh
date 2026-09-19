#!/bin/sh
# ABOUTME: Runs complete.dip once per kata with a durable ledger of isolated child runs.
# ABOUTME: Verifies each landing on trunk, records clean failures for review, and stops on integrity problems.
set -eu

if [ "${1:-}" = --help ]; then
  printf 'Usage: run-board.sh /path/to/complete.dip\nInvoked by board.dip with Tracker run identity. Logs and ledger are in the parent run directory under board/.\n'
  exit 0
fi
[ "$#" -eq 1 ] && [ -f "$1" ] || { printf 'expected the complete.dip source path\n' >&2; exit 1; }
[ -n "${TRACKER_RUN_DIR:-}" ] && [ -n "${TRACKER_RUN_ID:-}" ] && [ -n "${TRACKER_WORKDIR:-}" ] || {
  printf 'run-board.sh runs under tracker: TRACKER_RUN_DIR, TRACKER_RUN_ID, and TRACKER_WORKDIR must be set\n' >&2
  exit 1
}
command -v tracker >/dev/null
command -v kata >/dev/null
command -v jq >/dev/null
report=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd -P)/board-report
[ -x "$report" ] || { printf 'board report is missing or not executable: %s\n' "$report" >&2; exit 1; }
workspace=$(cd "$TRACKER_WORKDIR" && pwd -P)
pipeline=$(CDPATH='' cd -- "$(dirname "$1")" && printf '%s/%s' "$(pwd -P)" "$(basename "$1")")
cd "$workspace"
[ "$(git rev-parse --show-toplevel)" = "$workspace" ] || { printf 'target is not the Git root\n' >&2; exit 1; }
board="$TRACKER_RUN_DIR/board"
mkdir -p "$board/items"
lock="$board/lock"
if ! mkdir "$lock" 2>/dev/null; then
  owner=$(cat "$lock/pid" 2>/dev/null || true)
  case "$owner" in ''|*[!0-9]*) printf 'board lock has no valid owner; inspect %s\n' "$lock" >&2; exit 1 ;; esac
  if kill -0 "$owner" 2>/dev/null; then
    printf 'board controller is already running (PID %s)\n' "$owner" >&2
    exit 1
  fi
  rm "$lock/pid"
  rmdir "$lock"
  mkdir "$lock"
fi
printf '%s\n' "$$" >"$lock/pid"
child_pid=
# rm -rf keeps the exit status: rmdir would fail on a lock that still holds pid and replace the status with its own.
trap 'rm -rf "$lock"' EXIT
# The child Tracker handles SIGINT only. On SIGINT it cancels its running node, kills that node's process group,
# writes a checkpoint, and prints its resume hint; the wait lets it finish that before the pid file goes.
trap 'if [ -n "$child_pid" ]; then kill -INT "$child_pid" 2>/dev/null || true; wait "$child_pid" 2>/dev/null || true; rm -f "$item/child.pid"; fi; exit 130' HUP INT TERM
state="$board/state.json"
if [ ! -e "$state" ]; then
  jq -n --arg workspace "$workspace" --arg pipeline "$pipeline" \
    '{workspace:$workspace,pipeline:$pipeline,runs:[],finished:false}' >"$state.tmp"
  mv "$state.tmp" "$state"
fi
jq -e --arg workspace "$workspace" --arg pipeline "$pipeline" '
  .workspace == $workspace and .pipeline == $pipeline and
  (.finished | type == "boolean") and (.runs | type == "array") and
  (.stop_reason == null or (.stop_reason | type == "string")) and
  (.stop_child == null or (.stop_child | type == "string" and test("^[a-f0-9]{12}$"))) and
  all(.runs[]; (.run_id | type == "string" and test("^[a-f0-9]{12}$")) and
    (.kind == "completed" or .kind == "failed" or .kind == "empty") and
    (.kind == "empty" or (.issue_uid | type == "string" and length > 0))) and
  ([.runs[].run_id] | length == (unique | length))
' "$state" >/dev/null || { printf 'invalid board state or changed workspace/pipeline: %s\n' "$state" >&2; exit 1; }

write_state() {
  jq "$@" "$state" >"$state.tmp"
  mv "$state.tmp" "$state"
}
# This controller prints the review for the run's record; the Report node prints it again for the gate.
# A review the report refuses must not hide the marker: the ledger keeps the reason, and the Report node
# fails where Tracker reports it.
print_review() {
  "$report" "$TRACKER_RUN_ID" && return 0
  printf 'board report failed; run board-report %s from the target Git root\n' "$TRACKER_RUN_ID" >&2
  return 1
}
# Every stop after the ledger exists ends with the board-needs-human marker, so the parent run holds at the
# morning review instead of failing. The ledger keeps the reason, and the child id when a child needs inspection.
stop_board() {
  # $reason and $child are jq variables bound by --arg; ShellCheck cannot see the jq call behind write_state.
  # shellcheck disable=SC2016
  write_state --arg reason "$1" --arg child "${2:-}" '.stop_reason = $reason | if $child == "" then del(.stop_child) else .stop_child = $child end'
  printf '%s\n' "$1" >&2
  print_review || true
  printf 'board-needs-human\n'
  exit 0
}
stop_for_inspection() {
  printf 'Child run %s needs inspection; no next kata was started.\nLogs: %s\n' "$run_id" "$item/child.log" >&2
  printf 'Recover the child in %s with tracker -r %s %s, then choose Sweep again at the morning review.\n' "$workspace" "$run_id" "$pipeline" >&2
  stop_board "child $run_id needs inspection" "$run_id"
}
append_run() {
  # $result is a jq variable bound by --argjson; ShellCheck cannot see the jq call behind write_state.
  # shellcheck disable=SC2016
  write_state --argjson result "$result" '.runs += [$result]'
}
# A clean failure left the kata open, labeled, and commented, and put the checkout back on the
# trunk the child started from. Anything else is an integrity problem and stops the board.
record_failure() {
  handoff="$child/handoff.json"
  jq -e --arg run "$run_id" '.run_id == $run and
    all(.issue_uid, .reason, .label, .branch, .trunk; type == "string" and length > 0)' \
    "$handoff" >/dev/null 2>&1 || stop_for_inspection
  jq -e '.context_updates.tool_stdout | type == "string" and (split("\n") | any(. == "handoff-ok"))' \
    "$child/Handoff/status.json" >/dev/null 2>&1 || stop_for_inspection
  # The worker left the task branch, so the handoff preserved and restored nothing. A human looks first.
  reason=$(jq -r '.reason' "$handoff")
  [ "$reason" != unexpected_checkout ] || stop_for_inspection
  [ "$(git symbolic-ref --quiet --short HEAD)" = "$(jq -r '.trunk' "$handoff")" ] || stop_for_inspection
  dirty=$(git status --porcelain --untracked-files=normal) || stop_board 'git status failed; inspect the checkout'
  [ -z "$dirty" ] || stop_for_inspection
  uid=$(jq -r '.issue_uid' "$handoff")
  issue=$(kata show --workspace "$workspace" "$uid" --json) || stop_for_inspection
  printf '%s' "$issue" | jq -e --arg uid "$uid" --arg actor "kata-pipeline-$run_id" \
    '.issue.uid == $uid and .issue.status == "open" and .issue.owner == $actor' >/dev/null || stop_for_inspection
  result=$(jq --arg run "$run_id" '{run_id:$run,kind:"failed",issue_uid,branch,reason,label}' "$handoff")
  append_run
  printf 'Failed %s (%s); left open with %s on %s\n' "$uid" \
    "$(jq -r '.reason' "$handoff")" "$(jq -r '.label' "$handoff")" "$(jq -r '.branch' "$handoff")"
  if jq -e '[.runs[-3:][].kind] == ["failed","failed","failed"]' "$state" >/dev/null; then
    printf 'Board stopped after three consecutive failed children. Ledger: %s\n' "$state" >&2
    stop_board 'three consecutive failed children'
  fi
}

# A finished ledger ended at an empty queue. Re-entry, such as the morning review's "Sweep again",
# sweeps the board again in the same ledger.
if jq -e '.finished' "$state" >/dev/null; then
  write_state '.finished = false'
fi
while ! jq -e '.finished' "$state" >/dev/null; do
  # A stop reason and its child describe the previous controller's last iteration; this one decides afresh.
  write_state 'del(.stop_reason, .stop_child)'
  index=$(jq '.runs | length + 1' "$state")
  item="$board/items/$(printf '%06d' "$index")"
  mkdir -p "$item"
  if [ ! -e "$item/child.log" ]; then
    printf 'Starting kata attempt %s; child output: %s\n' "$index" "$item/child.log"
    # Create the log before launch. An interrupted launch must never silently claim twice.
    : >"$item/child.log"
    tracker --git off --json --no-tui --workdir "$workspace" "$pipeline" >"$item/child.log" 2>&1 &
    child_pid=$!
    printf '%s\n' "$child_pid" >"$item/child.pid"
    wait "$child_pid" || true
    child_pid=
    rm "$item/child.pid"
  elif [ -f "$item/child.pid" ]; then
    pending_pid=$(cat "$item/child.pid")
    case "$pending_pid" in ''|*[!0-9]*) stop_board "invalid child PID; inspect $item" ;; esac
    if kill -0 "$pending_pid" 2>/dev/null; then
      stop_board "child process $pending_pid is still running; wait before resuming the board"
    fi
    # A controller that Tracker cancelled never ran its traps, and its child died with it. The pid file is
    # stale; keeping it would let a reused PID pass for a running child on a later sweep.
    rm "$item/child.pid"
  fi
  run_id=$(jq -Rnr '[inputs | fromjson? | select(.source == "pipeline" and .type == "pipeline_started") | .run_id] | unique | if length == 1 then .[0] else empty end' <"$item/child.log")
  case "$run_id" in ''|*[!a-f0-9]*) stop_board "child identity is unknown; inspect $item/child.log before retrying" ;; esac
  [ "${#run_id}" -eq 12 ] || stop_board 'invalid child run ID'
  child="$workspace/.tracker/runs/$run_id"
  # The child's activity log includes manual resumes; the initial CLI log does not.
  [ -f "$child/activity.jsonl" ] || stop_for_inspection
  terminal=$(jq -Rnr --arg run "$run_id" '[inputs | fromjson? |
    select(.source == "pipeline" and .run_id == $run and
      (.type == "pipeline_started" or .type == "pipeline_completed" or .type == "pipeline_failed"))] |
    last | if .type == "pipeline_completed" and .terminal_status == "success" then "completed"
      elif .type == "pipeline_failed" then "failed" else "unknown" end' <"$child/activity.jsonl")
  if [ "$terminal" = failed ]; then
    record_failure
    continue
  fi
  [ "$terminal" = completed ] || stop_for_inspection
  jq -e '.outcome == "success"' "$child/Exit/status.json" >/dev/null 2>&1 || stop_for_inspection
  if [ -f "$child/selected.json" ]; then
    selected="$child/selected.json"
    jq -e --arg workspace "$workspace" '.workspace == $workspace and
      all(.issue_uid, .qualified_id, .branch, .trunk; type == "string" and length > 0)' "$selected" >/dev/null 2>&1 || stop_for_inspection
    jq -e '.outcome == "success" and .context_updates.tool_marker == "close-ok"' \
      "$child/CloseSelected/status.json" >/dev/null 2>&1 || stop_for_inspection
    uid=$(jq -r '.issue_uid' "$selected")
    qualified=$(jq -er '.qualified_id' "$selected")
    branch=$(jq -er '.branch' "$selected")
    trunk=$(jq -er '.trunk' "$selected")
    head=$(git rev-parse HEAD)
    [ "$(git symbolic-ref --quiet --short HEAD)" = "$trunk" ] || stop_for_inspection
    # The close step landed the work and deleted the task branch; a surviving branch means it did not finish.
    if git rev-parse --quiet --verify "refs/heads/$branch" >/dev/null 2>&1; then stop_for_inspection; fi
    dirty=$(git status --porcelain --untracked-files=normal) || stop_board 'git status failed; inspect the checkout'
    [ -z "$dirty" ] || stop_for_inspection
    for approval in review-correctness.approved review-scope.approved; do
      [ "$(sed -n '1p' "$child/$approval" 2>/dev/null || true)" = "$head" ] || stop_for_inspection
    done
    issue=$(kata show --workspace "$workspace" "$uid" --json) || stop_for_inspection
    printf '%s' "$issue" | jq -e --arg uid "$uid" '.issue.uid == $uid and .issue.status == "closed"' >/dev/null || stop_for_inspection
    if jq -e --arg uid "$uid" 'any(.runs[]; .kind == "completed" and .issue_uid == $uid)' "$state" >/dev/null; then
      stop_board "child repeated an already completed kata: $uid"
    fi
    result=$(jq --arg run "$run_id" --arg head "$head" \
      '{run_id:$run,kind:"completed",issue_uid,branch,commit:$head}' "$selected")
    append_run
    printf 'Landed %s on %s at %s\n' "$qualified" "$trunk" "$head"
  else
    jq -e '.outcome == "success" and .context_updates.tool_marker == "queue-empty"' \
      "$child/ClaimNext/status.json" >/dev/null 2>&1 || stop_for_inspection
    open=$(kata list --workspace "$workspace" --status open --limit 0 --json) || stop_board 'could not list open katas'
    printf '%s' "$open" | jq -e '.issues | type == "array"' >/dev/null || stop_board 'invalid open-board response'
    # Katas this board handed off stay open on purpose; only untouched ones count as remaining.
    remaining=$(printf '%s' "$open" | jq --slurpfile state "$state" \
      '[.issues[] | select(.uid as $uid | any($state[0].runs[]; .issue_uid == $uid) | not)] | length')
    result=$(jq -n --arg run "$run_id" '{run_id:$run,kind:"empty"}')
    append_run
    if [ "$remaining" -gt 0 ]; then
      printf '%s\n' "$open" >"$board/blocked.json"
      printf 'Board incomplete: %s open katas remain, but none were ready and unowned. See %s\n' "$remaining" "$board/blocked.json"
    else
      rm -f "$board/blocked.json"
    fi
    write_state '.finished = true'
  fi
done
# Only a kata's latest ledger entry describes it: a handoff that a later sweep finished no longer needs review.
open_for_review=$(jq '.runs as $runs | [$runs | to_entries[] | select(.value.kind == "failed") |
  select(.key as $i | .value.issue_uid as $uid | any($runs[$i + 1:][]; .issue_uid == $uid) | not)] | length' "$state")
# Every earlier exit is a stop or a refusal; only a sweep that reached the end of its queue prints this line.
printf 'Sweep finished: %s katas completed and %s left open for review so far in this board run. Ledger: %s\n' \
  "$(jq '[.runs[] | select(.kind == "completed")] | length' "$state")" "$open_for_review" "$state"
review_ok=true
print_review || review_ok=false
# The last line routes board.dip: a clean board ends the run; anything else opens the morning review.
# A review the report refused is something a person must see, so it never yields board-clean.
if [ "$review_ok" = true ] && [ "$open_for_review" -eq 0 ] && [ "$remaining" -eq 0 ]; then
  printf 'board-clean\n'
else
  printf 'board-needs-human\n'
fi
