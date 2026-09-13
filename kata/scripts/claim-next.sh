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
[ ! -e "$TRACKER_RUN_DIR/selected.json" ] || { printf 'selection already exists for this run\n' >&2; exit 1; }

exclude=$(git rev-parse --git-path info/exclude)
case "$exclude" in /*) ;; *) exclude="$workspace/$exclude" ;; esac
if ! grep -Fx '/.tracker/' "$exclude" >/dev/null 2>&1; then
  mkdir -p "$(dirname "$exclude")"
  printf '\n/.tracker/\n' >>"$exclude"
fi

dirty=$(git status --porcelain --untracked-files=normal)
if [ -n "$dirty" ]; then
  printf 'working tree is not clean:\n%s\ncommit, stash, or remove these paths, then start a fresh tracker run.\n' "$dirty" >&2
  exit 1
fi

branch=$(git symbolic-ref --quiet --short HEAD) || { printf 'detached HEAD cannot be prepared automatically\n' >&2; exit 1; }
mkdir -p "$TRACKER_RUN_DIR"
state_tmp="$TRACKER_RUN_DIR/selected.json.tmp"
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
case "$uid" in
  *[!0123456789ABCDEFGHJKMNPQRSTVWXYZ]*|'') printf 'kata next returned an invalid issue UID\n' >&2; exit 1 ;;
esac
[ "${#uid}" -eq 26 ] || { printf 'kata next returned an invalid issue UID\n' >&2; exit 1; }
case "$short_id" in *[!abcdefghijklmnopqrstuvwxyz0123456789]*|'') printf 'kata next returned an invalid short ID\n' >&2; exit 1 ;; esac
case "$TRACKER_RUN_ID" in *[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-]*|'') printf 'TRACKER_RUN_ID is unsafe for a Git branch\n' >&2; exit 1 ;; esac

create_branch=false
case "$branch" in
  main|master|trunk)
    branch="kata/$short_id-$TRACKER_RUN_ID"
    git check-ref-format --branch "$branch" >/dev/null 2>&1 || { printf 'generated task branch is invalid\n' >&2; exit 1; }
    create_branch=true
    ;;
esac
actor="kata-pipeline-$TRACKER_RUN_ID"

claim_json=$(kata claim --workspace "$workspace" --as "$actor" --if-unowned "$uid" --json) || {
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
if [ "$create_branch" = true ]; then
  git switch -c "$branch" >/dev/null
fi
printf 'claim-ok\nSTATE_PATH=%s\n' "$TRACKER_RUN_DIR/selected.json"
