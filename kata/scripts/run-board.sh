#!/bin/sh
# ABOUTME: Runs complete.dip once per kata with a durable ledger of isolated child runs.
# ABOUTME: Carries verified stack bases forward, records clean failures for review, and stops on integrity problems.
set -eu

if [ "${1:-}" = --help ]; then
  printf 'Usage: run-board.sh /path/to/complete.dip\nInvoked by board.dip with Tracker run identity. Logs and ledger are in the parent run directory under board/.\n'
  exit 0
fi
[ "$#" -eq 1 ] && [ -f "$1" ] || { printf 'expected the complete.dip source path\n' >&2; exit 1; }
: "${TRACKER_RUN_DIR:?TRACKER_RUN_DIR is required}"
: "${TRACKER_RUN_ID:?TRACKER_RUN_ID is required}"
: "${TRACKER_WORKDIR:?TRACKER_WORKDIR is required}"
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
trap 'rm -f "$lock/pid"; rmdir "$lock"' EXIT
trap 'if [ -n "$child_pid" ]; then kill "$child_pid" 2>/dev/null || true; wait "$child_pid" 2>/dev/null || true; fi; exit 130' HUP INT TERM
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
  all(.runs[]; (.run_id | type == "string" and test("^[a-f0-9]{12}$")) and
    (.kind == "completed" or .kind == "failed" or .kind == "empty")) and
  ([.runs[].run_id] | length == (unique | length))
' "$state" >/dev/null || { printf 'invalid board state or changed workspace/pipeline: %s\n' "$state" >&2; exit 1; }

write_state() {
  jq "$@" "$state" >"$state.tmp"
  mv "$state.tmp" "$state"
}
set_stop_reason() {
  # $reason is a jq variable bound by --arg; ShellCheck cannot see the jq call behind write_state.
  # shellcheck disable=SC2016
  write_state --arg reason "$1" '.stop_reason = $reason'
}
stop_child() {
  set_stop_reason "child $run_id needs inspection"
  printf 'Child run %s needs inspection; no next kata was started.\nLogs: %s\n' "$run_id" "$item/child.log" >&2
  printf 'Recover the child in %s with tracker -r %s %s, then resume board %s.\n' "$workspace" "$run_id" "$pipeline" "$TRACKER_RUN_ID" >&2
  exit 1
}
# A stop outside a child belongs in the ledger too, so the morning review says the board stopped.
stop_board() {
  set_stop_reason "$1"
  printf '%s\n' "$1" >&2
  exit 1
}
append_run() {
  # $result is a jq variable bound by --argjson; ShellCheck cannot see the jq call behind write_state.
  # shellcheck disable=SC2016
  write_state --argjson result "$result" '.runs += [$result]'
}
# A clean failure left the kata open, labeled, and commented, and put the checkout back on the
# branch the child started from. Anything else is an integrity problem and stops the board.
record_failure() {
  handoff="$child/handoff.json"
  jq -e --arg run "$run_id" '.run_id == $run and
    all(.issue_uid, .reason, .label, .branch, .start_branch; type == "string" and length > 0)' \
    "$handoff" >/dev/null 2>&1 || stop_child
  jq -e '.context_updates.tool_stdout | type == "string" and (split("\n") | any(. == "handoff-ok"))' \
    "$child/Handoff/status.json" >/dev/null 2>&1 || stop_child
  # The worker left the task branch, so the handoff preserved and restored nothing. A human looks first.
  reason=$(jq -r '.reason' "$handoff")
  [ "$reason" != unexpected_checkout ] || stop_child
  [ "$(git symbolic-ref --quiet --short HEAD)" = "$(jq -r '.start_branch' "$handoff")" ] || stop_child
  dirty=$(git status --porcelain --untracked-files=normal) || stop_board 'git status failed; inspect the checkout'
  [ -z "$dirty" ] || stop_child
  if [ -n "$KATA_STACK_BASE_FILE" ]; then
    [ "$(git rev-parse HEAD)" = "$(jq -r '.commit' "$KATA_STACK_BASE_FILE")" ] || stop_child
  fi
  uid=$(jq -r '.issue_uid' "$handoff")
  issue=$(kata show --workspace "$workspace" "$uid" --json)
  printf '%s' "$issue" | jq -e --arg uid "$uid" --arg actor "kata-pipeline-$run_id" \
    '.issue.uid == $uid and .issue.status == "open" and .issue.owner == $actor' >/dev/null || stop_child
  result=$(jq --arg run "$run_id" '{run_id:$run,kind:"failed",issue_uid,branch,reason,label}' "$handoff")
  append_run
  printf 'Failed %s (%s); left open with %s on %s\n' "$uid" \
    "$(jq -r '.reason' "$handoff")" "$(jq -r '.label' "$handoff")" "$(jq -r '.branch' "$handoff")"
  if jq -e '[.runs[-3:][].kind] == ["failed","failed","failed"]' "$state" >/dev/null; then
    set_stop_reason 'three consecutive failed children'
    printf 'Board stopped after three consecutive failed children. Ledger: %s\n' "$state" >&2
    "$report" "$TRACKER_RUN_ID"
    exit 1
  fi
}

# A finished ledger ended at an empty queue. Re-entry, such as the morning review's "Sweep again",
# sweeps the board again in the same ledger.
if jq -e '.finished' "$state" >/dev/null; then
  write_state '.finished = false'
fi
while ! jq -e '.finished' "$state" >/dev/null; do
  # A stop reason describes the previous controller's last iteration; this one decides afresh.
  write_state 'del(.stop_reason)'
  index=$(jq '.runs | length + 1' "$state")
  item="$board/items/$(printf '%06d' "$index")"
  mkdir -p "$item"
  # Empty and failed attempts do not change the stack tip. Only verified child completions do.
  jq '[.runs[] | select(.kind == "completed")] | last' "$state" >"$item/base.json"
  KATA_STACK_BASE_FILE=
  if jq -e '. != null' "$item/base.json" >/dev/null; then
    KATA_STACK_BASE_FILE="$item/base.json"
  fi
  export KATA_STACK_BASE_FILE
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
  fi
  run_id=$(jq -Rnr '[inputs | fromjson? | select(.source == "pipeline" and .type == "pipeline_started") | .run_id] | unique | if length == 1 then .[0] else empty end' <"$item/child.log")
  case "$run_id" in ''|*[!a-f0-9]*) stop_board "child identity is unknown; inspect $item/child.log before retrying" ;; esac
  [ "${#run_id}" -eq 12 ] || stop_board 'invalid child run ID'
  child="$workspace/.tracker/runs/$run_id"
  # The child's activity log includes manual resumes; the initial CLI log does not.
  [ -f "$child/activity.jsonl" ] || stop_child
  terminal=$(jq -Rnr --arg run "$run_id" '[inputs | fromjson? |
    select(.source == "pipeline" and .run_id == $run and
      (.type == "pipeline_started" or .type == "pipeline_completed" or .type == "pipeline_failed"))] |
    last | if .type == "pipeline_completed" and .terminal_status == "success" then "completed"
      elif .type == "pipeline_failed" then "failed" else "unknown" end' <"$child/activity.jsonl")
  if [ "$terminal" = failed ]; then
    record_failure
    continue
  fi
  [ "$terminal" = completed ] || stop_child
  jq -e '.outcome == "success"' "$child/Exit/status.json" >/dev/null 2>&1 || stop_child
  if [ -f "$child/selected.json" ]; then
    selected="$child/selected.json"
    jq -e --arg workspace "$workspace" '.workspace == $workspace and
      (.issue_uid | type == "string" and length > 0) and has("github")' "$selected" >/dev/null || stop_child
    jq -e '.outcome == "success" and .context_updates.tool_marker == "close-ok"' \
      "$child/CloseSelected/status.json" >/dev/null 2>&1 || stop_child
    uid=$(jq -r '.issue_uid' "$selected")
    branch=$(jq -er '.branch' "$selected")
    head=$(git rev-parse HEAD)
    [ "$(git symbolic-ref --quiet --short HEAD)" = "$branch" ] || stop_child
    dirty=$(git status --porcelain --untracked-files=normal) || stop_board 'git status failed; inspect the checkout'
    [ -z "$dirty" ] || stop_child
    for approval in review-correctness.approved review-scope.approved; do
      [ "$(sed -n '1p' "$child/$approval" 2>/dev/null || true)" = "$head" ] || stop_child
    done
    issue=$(kata show --workspace "$workspace" "$uid" --json)
    printf '%s' "$issue" | jq -e --arg uid "$uid" '.issue.uid == $uid and .issue.status == "closed"' >/dev/null || stop_child
    if jq -e --arg uid "$uid" 'any(.runs[]; .kind == "completed" and .issue_uid == $uid)' "$state" >/dev/null; then
      stop_board "child repeated an already completed kata: $uid"
    fi
    pr_url=
    if jq -e '.github != null' "$selected" >/dev/null; then
      [ -s "$child/pr-url.txt" ] || stop_child
      pr_url=$(cat "$child/pr-url.txt")
    fi
    result=$(jq --arg run "$run_id" --arg head "$head" --arg url "$pr_url" \
      '{run_id:$run,kind:"completed",issue_uid,branch,commit:$head,github,pr_url:$url}' "$selected")
    append_run
    printf 'Completed %s on %s%s\n' "$uid" "$branch" "${pr_url:+; $pr_url}"
  else
    jq -e '.outcome == "success" and .context_updates.tool_marker == "queue-empty"' \
      "$child/ClaimNext/status.json" >/dev/null 2>&1 || stop_child
    open=$(kata list --workspace "$workspace" --status open --limit 0 --json)
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
printf 'Board complete: %s katas finished, %s left open for review. Ledger: %s\n' \
  "$(jq '[.runs[] | select(.kind == "completed")] | length' "$state")" "$open_for_review" "$state"
"$report" "$TRACKER_RUN_ID"
# The last line routes board.dip: a clean board ends the run; anything else opens the morning review.
if [ "$open_for_review" -eq 0 ] && [ "$remaining" -eq 0 ]; then
  printf 'board-clean\n'
else
  printf 'board-needs-human\n'
fi
