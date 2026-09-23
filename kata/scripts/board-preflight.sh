#!/bin/sh
# ABOUTME: Prepares one board sweep: guards the parent env and Git root, hides the subgraph body's
# ABOUTME: workspace-root paths, and seeds the ledger and per-sweep run-id. Prints preflight-ok when ready.
set -eu

workflow_dir="${1:?workflow_dir argument is required}"
# shellcheck source=scripts/board-lib.sh
. "$workflow_dir/scripts/board-lib.sh"

command -v git >/dev/null
command -v jq >/dev/null
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

# Refuse to start if any body path already exists: the board would overwrite the operator's file. On a
# sweep-again the previous RecordOutcome scrubbed these, so a survivor here is real and must be inspected.
# Node names and artifact filenames never contain whitespace, so splitting the lists is safe and lets a
# collision exit the script, which a while-read pipe running in a subshell could not.
# shellcheck disable=SC2046
for path in $(board_node_names "$board_item") $(board_artifact_files); do
  [ ! -e "$workspace/$path" ] || {
    printf 'the target already contains %s; the board would overwrite it — move it aside and start again\n' "$path" >&2
    exit 1
  }
done

exclude=$(git -C "$workspace" rev-parse --git-path info/exclude)
case "$exclude" in /*) ;; *) exclude="$workspace/$exclude" ;; esac
mkdir -p "$(dirname "$exclude")"
# The parent run dir and per-kata identity live under .tracker; claim-next.sh hides it too, and this keeps
# it hidden before the first body node runs.
grep -Fx '/.tracker/' "$exclude" >/dev/null 2>&1 || printf '\n/.tracker/\n' >>"$exclude"
if ! grep -Fx "$BOARD_EXCLUDE_BEGIN" "$exclude" >/dev/null 2>&1; then
  {
    printf '%s\n' "$BOARD_EXCLUDE_BEGIN"
    board_node_names "$board_item" | while IFS= read -r name; do printf '/%s/\n' "$name"; done
    board_artifact_files | while IFS= read -r name; do printf '/%s\n' "$name"; done
    printf '%s\n' "$BOARD_EXCLUDE_END"
  } >>"$exclude"
fi

ledger="$TRACKER_RUN_DIR/board/state.json"
if [ -f "$ledger" ]; then
  jq -e --arg ws "$workspace" '.workspace == $ws and (.runs | type) == "array"' "$ledger" >/dev/null || {
    printf 'board ledger at %s is invalid or built for another workspace\n' "$ledger" >&2; exit 1; }
  # Re-entering for another sweep: this ledger is no longer finished, and any earlier stop is cleared.
  jq '.finished = false | del(.stop_reason, .stop_child)' "$ledger" >"$ledger.tmp" && mv "$ledger.tmp" "$ledger"
else
  mkdir -p "$(dirname "$ledger")"
  jq -n --arg ws "$workspace" --arg pipeline "$board_item" \
    '{workspace:$ws,pipeline:$pipeline,runs:[],finished:false}' >"$ledger.tmp" && mv "$ledger.tmp" "$ledger"
fi

# claim-next.sh reads this file for its run identity in subgraph mode. Seed it when it is absent or was
# left by another parent run; keep it when it already carries this run's prefix (RecordOutcome rotates it).
run_id_file="$workspace/.tracker/kata-board-run-id"
current=$(cat "$run_id_file" 2>/dev/null || true)
case "$current" in
  "$TRACKER_RUN_ID"-*) : ;;
  *)
    mkdir -p "$(dirname "$run_id_file")"
    printf '%s-%s\n' "$TRACKER_RUN_ID" "$(board_rand6)" >"$run_id_file"
    ;;
esac

printf 'preflight-ok\n'
