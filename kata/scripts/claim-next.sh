#!/bin/sh
# ABOUTME: Guards the target tree, claims one ready unowned kata, and binds its identity.
# ABOUTME: Records the trunk to land on later and writes run state only after a confirmed claim.
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

trunk=$(git symbolic-ref --quiet --short HEAD) || { printf 'detached HEAD; check out the branch this work should land on\n' >&2; exit 1; }
case "$trunk" in
  kata/*) printf '%s is a task branch; check out the branch this work should land on\n' "$trunk" >&2; exit 1 ;;
esac
# A warm-continue override outlives its run; a stale one would inflate this run's worker budget.
rm -f "$workspace/.tracker/turn_overrides/Implement"
mkdir -p "$TRACKER_RUN_DIR"
state_tmp="$TRACKER_RUN_DIR/selected.json.tmp"
printf '' >"$state_tmp"
trap 'rm -f "$state_tmp"' EXIT HUP INT TERM

ready_json=$(kata ready --workspace "$workspace" --unowned --limit 0 --json)
# Kata next prefers lower numeric priorities, then preserves ready API order.
# Slurping rejects empty or multiple response documents before any claim.
selected_json=$(printf '%s' "$ready_json" | jq -cs '
  def count: type == "number" and . >= 0 and floor == .;
  if length != 1 or (.[0] | type) != "object" or (.[0].issues | type) != "array" then
    error("invalid ready response envelope")
  else .[0].issues end
  | if all(.[];
      type == "object"
      and (.priority == null or (.priority | type == "number" and floor == . and . >= 0 and . <= 4))
      and ((has("child_counts") | not) or
        (.child_counts | type == "object"
          and (.open | count) and (.total | count) and .open <= .total)))
    then . else error("invalid ready issue priority or child counts") end
  | to_entries
  | map(select((.value.child_counts.open // 0) == 0))
  | sort_by([(.value.priority == null), (.value.priority // 0), .key])
  | .[0].value
') || {
  printf 'kata ready returned an invalid response\n' >&2
  exit 1
}
if [ "$selected_json" = null ]; then
  printf 'queue-empty\n'
  exit 0
fi
uid=$(printf '%s' "$selected_json" | jq -er '.uid // empty') || { printf 'kata ready returned an invalid response\n' >&2; exit 1; }
short_id=$(printf '%s' "$selected_json" | jq -er '.short_id')
qualified_id=$(printf '%s' "$selected_json" | jq -er '.qualified_id')
case "$uid" in
  *[!0123456789ABCDEFGHJKMNPQRSTVWXYZ]*|'') printf 'kata ready returned an invalid issue UID\n' >&2; exit 1 ;;
esac
[ "${#uid}" -eq 26 ] || { printf 'kata ready returned an invalid issue UID\n' >&2; exit 1; }
case "$short_id" in *[!abcdefghijklmnopqrstuvwxyz0123456789]*|'') printf 'kata ready returned an invalid short ID\n' >&2; exit 1 ;; esac
case "$TRACKER_RUN_ID" in *[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-]*|'') printf 'TRACKER_RUN_ID is unsafe for a Git branch\n' >&2; exit 1 ;; esac

branch="kata/$short_id-$TRACKER_RUN_ID"
git check-ref-format --branch "$branch" >/dev/null 2>&1 || { printf 'generated task branch is invalid\n' >&2; exit 1; }
if git show-ref --verify --quiet "refs/heads/$branch"; then
  printf 'task branch already exists: %s\n' "$branch" >&2
  exit 1
fi
base_commit=$(git rev-parse HEAD)
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

# A kata handed back after a review or decision still carries its handoff label; this run owns it now.
for label in needs-review needs-decision; do
  printf '%s' "$selected_json" | jq -e --arg label "$label" '(.labels // []) | any(. == $label)' >/dev/null || continue
  kata label rm --workspace "$workspace" --as "$actor" "$uid" "$label" --agent >/dev/null || {
    printf 'could not remove the %s label from %s\n' "$label" "$qualified_id" >&2
    exit 1
  }
done

jq -n --arg uid "$uid" --arg short "$short_id" --arg qualified "$qualified_id" \
  --arg workspace "$workspace" --arg branch "$branch" --arg base "$base_commit" --arg actor "$actor" \
  --arg trunk "$trunk" \
  --argjson issue "$(printf '%s' "$claim_json" | jq '.issue')" \
  '{issue_uid:$uid,short_id:$short,qualified_id:$qualified,workspace:$workspace,branch:$branch,base_commit:$base,actor:$actor,trunk:$trunk,issue:$issue}' >"$state_tmp"
mv "$state_tmp" "$TRACKER_RUN_DIR/selected.json"
git switch -c "$branch" "$base_commit" >/dev/null
printf 'claim-ok\nSTATE_PATH=%s\n' "$TRACKER_RUN_DIR/selected.json"
