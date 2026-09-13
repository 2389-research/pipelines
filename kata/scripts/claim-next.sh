#!/bin/sh
# ABOUTME: Guards the target tree, claims one ready unowned kata, and binds its identity.
# ABOUTME: Stops on claim races and writes run state only after a confirmed claim.
set -eu

test -n "${TRACKER_RUN_DIR:-}" || { printf 'TRACKER_RUN_DIR is required\n' >&2; exit 1; }
test -n "${TRACKER_RUN_ID:-}" || { printf 'TRACKER_RUN_ID is required\n' >&2; exit 1; }
test -n "${TRACKER_WORKDIR:-}" || { printf 'TRACKER_WORKDIR is required\n' >&2; exit 1; }
command -v git >/dev/null
command -v jq >/dev/null
command -v kata >/dev/null

workspace=$(cd "$TRACKER_WORKDIR" && pwd -P)
[ "$(git rev-parse --show-toplevel)" = "$workspace" ] || { printf 'target is not the Git root\n' >&2; exit 1; }
git check-ignore -q .tracker/ || { printf '.tracker must be ignored by Git\n' >&2; exit 1; }
[ -z "$(git status --porcelain --untracked-files=normal)" ] || { printf 'working tree is not clean\n' >&2; exit 1; }
branch=$(git symbolic-ref --quiet --short HEAD) || { printf 'detached HEAD is not a task branch\n' >&2; exit 1; }
case "$branch" in main|master|trunk) printf 'refusing default branch: %s\n' "$branch" >&2; exit 1 ;; esac
mkdir -p "$TRACKER_RUN_DIR"
state_tmp="$TRACKER_RUN_DIR/selected.json.tmp"
[ ! -e "$TRACKER_RUN_DIR/selected.json" ] || { printf 'selection already exists for this run\n' >&2; exit 1; }
printf '' >"$state_tmp"
trap 'rm -f "$state_tmp"' EXIT HUP INT TERM

next_json=$(kata next --workspace "$workspace" --unowned --json)
uid=$(printf '%s' "$next_json" | jq -er '.issue.uid // empty') || {
  if printf '%s' "$next_json" | jq -e '.issue == null' >/dev/null; then
    printf 'queue-empty\n'
    exit 0
  fi
  printf 'kata next returned an invalid response\n' >&2
  exit 1
}
short_id=$(printf '%s' "$next_json" | jq -er '.issue.short_id')
qualified_id=$(printf '%s' "$next_json" | jq -er '.issue.qualified_id')
actor="kata-pipeline-$TRACKER_RUN_ID"

claim_json=$(kata claim --workspace "$workspace" --as "$actor" "$uid" --json) || {
  printf 'claim failed for %s; stopping without reselection\n' "$qualified_id" >&2
  exit 1
}
printf '%s' "$claim_json" | jq -e --arg uid "$uid" --arg actor "$actor" \
  '.issue.uid == $uid and .issue.owner == $actor' >/dev/null || {
    printf 'claim response did not confirm identity and owner\n' >&2
    exit 1
  }

jq -n --arg uid "$uid" --arg short "$short_id" --arg qualified "$qualified_id" \
  --arg workspace "$workspace" --arg branch "$branch" --arg base "$(git rev-parse HEAD)" --arg actor "$actor" \
  --argjson issue "$(printf '%s' "$claim_json" | jq '.issue')" \
  '{issue_uid:$uid,short_id:$short,qualified_id:$qualified,workspace:$workspace,branch:$branch,base_commit:$base,actor:$actor,issue:$issue}' >"$state_tmp"
mv "$state_tmp" "$TRACKER_RUN_DIR/selected.json"
printf 'claim-ok\nSTATE_PATH=%s\n' "$TRACKER_RUN_DIR/selected.json"
