#!/bin/sh
# ABOUTME: Records one board sweep from the records the subgraph body left at the workspace root: it
# ABOUTME: classifies the sweep, appends a self-contained ledger entry, scrubs bookkeeping, and marks.
set -eu

workflow_dir="${1:?workflow_dir argument is required}"
# shellcheck source=scripts/board-lib.sh
. "$workflow_dir/scripts/board-lib.sh"

command -v git >/dev/null
command -v jq >/dev/null
command -v kata >/dev/null
# The board parent gives every node these; a missing one means this is not running as the board parent.
: "${TRACKER_WORKDIR:?TRACKER_WORKDIR is required}"
: "${TRACKER_RUN_DIR:?TRACKER_RUN_DIR is required}"
: "${TRACKER_RUN_ID:?TRACKER_RUN_ID is required}"

workspace=$(cd "$TRACKER_WORKDIR" && pwd -P)
board_item="$workflow_dir/board-item.dip"
[ -f "$board_item" ] || { printf 'board body %s is missing\n' "$board_item" >&2; exit 1; }

top=$(git -C "$workspace" rev-parse --show-toplevel 2>/dev/null) || {
  printf 'the workspace %s is not inside a Git repository\n' "$workspace" >&2; exit 1; }
[ "$top" = "$workspace" ] || {
  printf 'the workspace %s is not the Git root (%s)\n' "$workspace" "$top" >&2; exit 1; }

exclude=$(git -C "$workspace" rev-parse --git-path info/exclude)
case "$exclude" in /*) ;; *) exclude="$workspace/$exclude" ;; esac

board="$TRACKER_RUN_DIR/board"
ledger="$board/state.json"
[ -f "$ledger" ] || { printf 'board ledger %s is missing; preflight did not run\n' "$ledger" >&2; exit 1; }

# claim-next.sh, handoff-selected.sh, and this script all use the run identity from this file, so the
# actor and branch names line up across the sweep. Preflight seeds it; a sweep-again rotates it below.
run_id_file="$workspace/.tracker/kata-board-run-id"
run_id=$(cat "$run_id_file" 2>/dev/null || true)
[ -n "$run_id" ] || { printf 'run-id file %s is missing or empty; preflight did not run\n' "$run_id_file" >&2; exit 1; }

marker=

write_ledger() { jq "$@" "$ledger" >"$ledger.tmp" && mv "$ledger.tmp" "$ledger"; }
# The single quotes below keep the $-prefixed jq variables literal for jq; shellcheck cannot see that a
# wrapper's argument is a jq program, so SC2016 is a false positive on these two helpers.
# shellcheck disable=SC2016
append_run() { write_ledger --argjson e "$1" '.runs += [$e]'; }
# shellcheck disable=SC2016
set_stop_reason() { write_ledger --arg r "$1" '.stop_reason = $r | del(.stop_child)'; }

# Hold the board for a person: record why, print it to stderr, and mark board-needs-human. No ledger
# run entry — the sweep did not reach a clean outcome, so there is nothing trustworthy to record.
stop_for_inspection() {
  set_stop_reason "$1"
  printf '%s; the board is holding for a person. Inspect %s and the ledger %s\n' "$1" "$workspace" "$ledger" >&2
  marker='board-needs-human'
}

# A handoff. Verify the worker left the trunk clean and the kata open and owned, record the review the
# self-contained ledger needs, then sweep past it — three failures in a row stop for a person instead.
record_failure() {
  h="$workspace/handoff.json"
  jq -e --arg run "$run_id" \
    '.run_id == $run and all(.issue_uid, .reason, .label, .branch, .trunk; type == "string" and length > 0)' \
    "$h" >/dev/null 2>&1 || { stop_for_inspection "the handoff record for run $run_id is malformed"; return; }
  jq -e '.context_updates.tool_stdout | type == "string" and (split("\n") | any(. == "handoff-ok"))' \
    "$workspace/Handoff/status.json" >/dev/null 2>&1 || { stop_for_inspection "the Handoff node did not confirm handoff-ok"; return; }
  reason=$(jq -r '.reason' "$h")
  [ "$reason" != unexpected_checkout ] || { stop_for_inspection "the worker left the task branch (unexpected_checkout)"; return; }
  trunk=$(jq -r '.trunk' "$h")
  [ "$(git -C "$workspace" symbolic-ref --quiet --short HEAD 2>/dev/null || true)" = "$trunk" ] || \
    { stop_for_inspection "the checkout is not on the trunk after handoff"; return; }
  [ -z "$(git -C "$workspace" status --porcelain --untracked-files=normal)" ] || \
    { stop_for_inspection "the working tree is dirty after handoff"; return; }
  uid=$(jq -r '.issue_uid' "$h")
  issue=$(kata show --workspace "$workspace" "$uid" --json) || \
    { stop_for_inspection "kata show failed for $uid after handoff"; return; }
  printf '%s' "$issue" | jq -e --arg uid "$uid" --arg actor "kata-pipeline-$run_id" \
    '.issue.uid == $uid and .issue.status == "open" and .issue.owner == $actor' >/dev/null 2>&1 || \
    { stop_for_inspection "kata $uid is not open and owned by this run after handoff"; return; }
  append_run "$(jq --arg run "$run_id" \
    '{run_id:$run, kind:"failed", issue_uid, qualified_id, branch, reason, label, base_commit, wip_commit, trunk, question}' "$h")"
  printf 'Failed %s (%s); left open with %s on %s\n' \
    "$(jq -r '.qualified_id' "$h")" "$reason" "$(jq -r '.label' "$h")" "$(jq -r '.branch' "$h")"
  if jq -e '[.runs[-3:][].kind] == ["failed","failed","failed"]' "$ledger" >/dev/null; then
    printf 'Board stopped after three consecutive failed children. Ledger: %s\n' "$ledger" >&2
    set_stop_reason "three consecutive failed children"
    marker='board-needs-human'
  else
    marker='sweep-again'
  fi
}

# A landing. Verify the approved commit is on the trunk, the task branch is gone, and the kata is closed,
# then record the commit and sweep on. Anything short of a clean landing holds the board for a person.
record_completed() {
  s="$workspace/selected.json"
  jq -e --arg ws "$workspace" \
    '.workspace == $ws and all(.issue_uid, .qualified_id, .branch, .trunk, .base_commit; type == "string" and length > 0)' \
    "$s" >/dev/null 2>&1 || { stop_for_inspection "selected.json is malformed"; return; }
  jq -e '.outcome == "success"' "$workspace/Exit/status.json" >/dev/null 2>&1 || \
    { stop_for_inspection "the subgraph did not reach a successful Exit"; return; }
  jq -e '.outcome == "success" and .context_updates.tool_marker == "close-ok"' \
    "$workspace/CloseSelected/status.json" >/dev/null 2>&1 || \
    { stop_for_inspection "CloseSelected did not confirm close-ok"; return; }
  uid=$(jq -r '.issue_uid' "$s")
  qualified=$(jq -r '.qualified_id' "$s")
  branch=$(jq -r '.branch' "$s")
  trunk=$(jq -r '.trunk' "$s")
  head=$(git -C "$workspace" rev-parse HEAD)
  [ "$(git -C "$workspace" symbolic-ref --quiet --short HEAD 2>/dev/null || true)" = "$trunk" ] || \
    { stop_for_inspection "the checkout is not on the trunk after close"; return; }
  ! git -C "$workspace" rev-parse --quiet --verify "refs/heads/$branch" >/dev/null 2>&1 || \
    { stop_for_inspection "the task branch $branch still exists after close"; return; }
  [ -z "$(git -C "$workspace" status --porcelain --untracked-files=normal)" ] || \
    { stop_for_inspection "the working tree is dirty after close"; return; }
  for approval in review-correctness.approved review-scope.approved; do
    [ "$(sed -n '1p' "$workspace/$approval" 2>/dev/null || true)" = "$head" ] || \
      { stop_for_inspection "$approval does not approve the landed commit $head"; return; }
  done
  issue=$(kata show --workspace "$workspace" "$uid" --json) || \
    { stop_for_inspection "kata show failed for $uid after close"; return; }
  printf '%s' "$issue" | jq -e --arg uid "$uid" '.issue.uid == $uid and .issue.status == "closed"' >/dev/null 2>&1 || \
    { stop_for_inspection "kata $uid is not closed after landing"; return; }
  jq -e --arg uid "$uid" 'any(.runs[]; .kind == "completed" and .issue_uid == $uid) | not' "$ledger" >/dev/null || \
    { stop_for_inspection "kata $uid was already recorded as completed in this board run"; return; }
  append_run "$(jq --arg run "$run_id" --arg head "$head" \
    '{run_id:$run, kind:"completed", issue_uid, qualified_id, branch, base_commit, commit:$head}' "$s")"
  printf 'Landed %s on %s at %s\n' "$qualified" "$trunk" "$head"
  marker='sweep-again'
}

# The queue is empty. Record it, then decide whether the board is done: it is clean only when nothing is
# still open for a person to review and no open kata was left untouched (a sign every worker was blocked).
record_empty() {
  open=$(kata list --workspace "$workspace" --status open --limit 0 --json) || \
    { stop_for_inspection "could not list the open katas"; return; }
  printf '%s' "$open" | jq -e '.issues | type == "array"' >/dev/null 2>&1 || \
    { stop_for_inspection "the open-kata listing was not valid JSON"; return; }
  append_run "$(jq -n --arg run "$run_id" '{run_id:$run, kind:"empty"}')"
  remaining=$(printf '%s' "$open" | jq --slurpfile L "$ledger" \
    '[.issues[] | select(.uid as $u | any($L[0].runs[]; .issue_uid == $u) | not)] | length')
  write_ledger '.finished = true'
  if [ "$remaining" -gt 0 ]; then
    printf '%s\n' "$open" >"$board/blocked.json"
  else
    rm -f "$board/blocked.json"
  fi
  # A failed run is still open for review unless a later run for the same kata superseded it.
  open_for_review=$(jq \
    '[.runs as $r | range(0; ($r | length)) | select($r[.].kind == "failed") | . as $i
      | select([$r[($i + 1):][].issue_uid] | index($r[$i].issue_uid) | not)] | length' "$ledger")
  landed=$(jq '[.runs[] | select(.kind == "completed")] | length' "$ledger")
  printf 'Sweep finished: %s landed, %s open for review, %s remaining. Ledger: %s\n' \
    "$landed" "$open_for_review" "$remaining" "$ledger"
  if [ "$open_for_review" -eq 0 ] && [ "$remaining" -eq 0 ]; then
    marker='board-clean'
  else
    marker='board-needs-human'
  fi
}

# A failed run leaves both selected.json and handoff.json, so the handoff check must come first; a clean
# landing leaves selected.json with no handoff; an empty queue leaves neither, only ClaimNext's marker.
claimstatus="$workspace/ClaimNext/status.json"
if [ -f "$workspace/handoff.json" ]; then
  record_failure
elif [ -f "$workspace/selected.json" ]; then
  record_completed
elif [ -f "$claimstatus" ] && \
  jq -e '.outcome == "success" and .context_updates.tool_marker == "queue-empty"' "$claimstatus" >/dev/null 2>&1; then
  record_empty
else
  stop_for_inspection "the claim neither selected a kata nor reported an empty queue"
fi

# Clear the body's bookkeeping so the next preflight starts clean. Git state (branches, commits, the
# working tree) and .tracker (the ledger and run-id) are never touched — they carry the board's memory,
# and the review a failed sweep needs now lives in the ledger, not in these files.
board_node_names "$board_item" | while IFS= read -r name; do
  case "$name" in ''|.*|*/*) continue ;; esac
  rm -rf "${workspace:?}/$name"
done
board_artifact_files | while IFS= read -r name; do
  case "$name" in ''|.*|*/*) continue ;; esac
  rm -f "$workspace/$name" "$workspace/$name.tmp"
done

case "$marker" in
  sweep-again)
    # Keep the managed excludes for the next sweep, but rotate the run-id so a reclaimed kata lands on a
    # new branch name instead of colliding with the branch this sweep left behind.
    printf '%s-%s\n' "$TRACKER_RUN_ID" "$(board_rand6)" >"$run_id_file"
    ;;
  *)
    # Terminal: drop the managed excludes so a person sees the workspace as Git normally would.
    if [ -f "$exclude" ] && grep -Fx "$BOARD_EXCLUDE_BEGIN" "$exclude" >/dev/null 2>&1; then
      awk -v b="$BOARD_EXCLUDE_BEGIN" -v e="$BOARD_EXCLUDE_END" \
        '$0 == b {skip = 1} skip {if ($0 == e) skip = 0; next} {print}' "$exclude" >"$exclude.tmp" && mv "$exclude.tmp" "$exclude"
    fi
    ;;
esac

printf '%s\n' "$marker"
