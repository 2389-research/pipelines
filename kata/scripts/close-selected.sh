#!/bin/sh
# ABOUTME: Closes the bound kata only after a clean committed tree and review path.
# ABOUTME: Uses the saved full issue identity so another queue item cannot be closed.
set -eu

test -n "${TRACKER_RUN_DIR:-}" || { printf 'TRACKER_RUN_DIR is required\n' >&2; exit 1; }
test -n "${TRACKER_WORKDIR:-}" || { printf 'TRACKER_WORKDIR is required\n' >&2; exit 1; }
state="$TRACKER_RUN_DIR/selected.json"
[ -f "$state" ] || { printf 'selected state is missing\n' >&2; exit 1; }
workspace=$(jq -er '.workspace' "$state")
uid=$(jq -er '.issue_uid' "$state")
branch=$(jq -er '.branch' "$state")
base=$(jq -er '.base_commit' "$state")
actor=$(jq -er '.actor' "$state")
cd "$workspace"
[ "$(pwd -P)" = "$(cd "$TRACKER_WORKDIR" && pwd -P)" ] || { printf 'tracker workspace changed\n' >&2; exit 1; }
[ "$(git symbolic-ref --quiet --short HEAD)" = "$branch" ] || { printf 'task branch changed\n' >&2; exit 1; }
[ -z "$(git status --porcelain --untracked-files=normal)" ] || { printf 'working tree is not clean\n' >&2; exit 1; }
head=$(git rev-parse HEAD)
[ "$head" != "$base" ] || { printf 'no task commit was created\n' >&2; exit 1; }
git merge-base --is-ancestor "$base" "$head" || { printf 'task history no longer descends from the claimed base\n' >&2; exit 1; }
[ -s "$TRACKER_RUN_DIR/verification.txt" ] || { printf 'verification evidence is missing\n' >&2; exit 1; }
[ -s "$TRACKER_RUN_DIR/completion.md" ] || { printf 'completion summary is missing\n' >&2; exit 1; }
for approval in review-correctness.approved review-scope.approved; do
  [ "$(sed -n '1p' "$TRACKER_RUN_DIR/$approval" 2>/dev/null || true)" = "$head" ] || {
    printf '%s does not approve current commit %s\n' "$approval" "$head" >&2
    exit 1
  }
done
issue_json=$(kata show --workspace "$workspace" "$uid" --json)
printf '%s' "$issue_json" | jq -e --arg uid "$uid" --arg actor "$actor" \
  '.issue.uid == $uid and .issue.status == "open" and .issue.owner == $actor' >/dev/null || {
    printf 'selected kata is no longer open and owned by this run\n' >&2
    exit 1
  }
test_evidence=$(head -n 1 "$TRACKER_RUN_DIR/verification.txt")
completion=$(cat "$TRACKER_RUN_DIR/completion.md")
[ "${#completion}" -ge 60 ] || { printf 'completion summary is too short\n' >&2; exit 1; }
kata close --workspace "$workspace" --as "$actor" "$uid" --done \
  --message "$completion" \
  --commit "$head" --test "$test_evidence" --json >/dev/null
printf 'close-ok\n'
