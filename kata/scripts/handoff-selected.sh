#!/bin/sh
# ABOUTME: Leaves a failed claimed kata open with a needs-review handoff.
# ABOUTME: Records the bounded pipeline failure without selecting another item.
set -eu

test -n "${TRACKER_RUN_DIR:-}" || { printf 'TRACKER_RUN_DIR is required\n' >&2; exit 1; }
test -n "${TRACKER_WORKDIR:-}" || { printf 'TRACKER_WORKDIR is required\n' >&2; exit 1; }
state="$TRACKER_RUN_DIR/selected.json"
[ -f "$state" ] || { printf 'no claimed kata exists to hand off\n' >&2; exit 1; }
workspace=$(jq -er '.workspace' "$state")
uid=$(jq -er '.issue_uid' "$state")
actor=$(jq -er '.actor' "$state")
branch=$(jq -er '.branch' "$state")
[ "$(cd "$workspace" && pwd -P)" = "$(cd "$TRACKER_WORKDIR" && pwd -P)" ] || { printf 'tracker workspace changed\n' >&2; exit 1; }
if [ ! -s "$TRACKER_RUN_DIR/handoff.md" ]; then
  printf 'Attempted the selected kata on branch %s. The bounded run did not earn both SHA-bound approvals. Inspect tracker run %s and the branch diff; unresolved review or test findings remain.\n' "$branch" "${TRACKER_RUN_ID:-unknown}" >"$TRACKER_RUN_DIR/handoff.md"
fi
kata label add --workspace "$workspace" --as "$actor" "$uid" needs-review --agent
kata comment --workspace "$workspace" --as "$actor" "$uid" --body-file "$TRACKER_RUN_DIR/handoff.md" --agent
printf 'handoff-ok\n'
exit 1
