#!/bin/sh
# ABOUTME: Checks that both independent reviewers approved the current commit.
# ABOUTME: Fails closed on missing, stale, or malformed approval attestations.
set -eu

test -n "${TRACKER_WORKDIR:-}" || { printf 'TRACKER_WORKDIR is required\n' >&2; exit 1; }
# Standalone complete.dip supplies TRACKER_RUN_DIR; as a board subgraph body only TRACKER_WORKDIR is set.
base="${TRACKER_RUN_DIR:-$(cd "$TRACKER_WORKDIR" && pwd -P)}"
state="$base/selected.json"
workspace=$(jq -er '.workspace' "$state")
[ "$(cd "$workspace" && pwd -P)" = "$(cd "$TRACKER_WORKDIR" && pwd -P)" ] || { printf 'tracker workspace changed\n' >&2; exit 1; }
head=$(git -C "$workspace" rev-parse HEAD)
for approval in review-correctness.approved review-scope.approved; do
  [ "$(sed -n '1p' "$base/$approval" 2>/dev/null || true)" = "$head" ] || {
    printf 'approval-missing-or-stale: %s\n' "$approval" >&2
    exit 1
  }
done
printf 'approvals-ok\n'
