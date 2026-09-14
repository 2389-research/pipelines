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

git symbolic-ref --quiet --short HEAD >/dev/null || { printf 'detached HEAD cannot be prepared automatically\n' >&2; exit 1; }
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
github=null

# Read configured URLs so Git's transport rewrites do not change repository identity.
github_repository() {
  printf '%s' "$1" | jq -Rer '
    sub("/$"; "") | sub("\\.git$"; "")
    | capture("^(?:https://github\\.com/|git@github\\.com:|ssh://git@github\\.com(?::22)?/)(?<repository>[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)$")
    | .repository
  ' 2>/dev/null
}
github_remote=
repository=
github_count=0
for remote in $(git remote); do
  fetch_urls=$(git config --get-all "remote.$remote.url" || true)
  first_url=$(printf '%s\n' "$fetch_urls" | sed -n '1p')
  if remote_repository=$(github_repository "$first_url"); then
    github_count=$((github_count + 1))
    if [ "$remote" = origin ] || [ -z "$github_remote" ]; then
      github_remote=$remote
      repository=$remote_repository
    fi
  fi
done
if [ "$github_count" -gt 1 ] && [ "$github_remote" != origin ]; then
  printf 'multiple GitHub remotes without a GitHub origin; choose an origin before running\n' >&2
  exit 1
fi
if [ -n "$github_remote" ]; then
  fetch_urls=$(git config --get-all "remote.$github_remote.url")
  [ "$(printf '%s\n' "$fetch_urls" | wc -l | tr -d ' ')" -eq 1 ] || { printf 'GitHub remote must have exactly one fetch URL\n' >&2; exit 1; }
  push_urls=$(git config --get-all "remote.$github_remote.pushurl" || true)
  if [ -n "$push_urls" ]; then
    [ "$(printf '%s\n' "$push_urls" | wc -l | tr -d ' ')" -eq 1 ] || { printf 'GitHub remote must have at most one push URL\n' >&2; exit 1; }
    push_repository=$(github_repository "$push_urls") || { printf 'GitHub push URL does not identify the fetch repository\n' >&2; exit 1; }
    [ "$(printf '%s' "$push_repository" | tr '[:upper:]' '[:lower:]')" = "$(printf '%s' "$repository" | tr '[:upper:]' '[:lower:]')" ] || { printf 'GitHub push repository differs from fetch repository\n' >&2; exit 1; }
  fi
  command -v gh >/dev/null || { printf 'gh is required for GitHub repositories\n' >&2; exit 1; }
  repo_json=$(gh repo view "github.com/$repository" --json nameWithOwner,defaultBranchRef) || { printf 'GitHub repository lookup failed before claim\n' >&2; exit 1; }
  printf '%s' "$repo_json" | jq -e --arg repository "$repository" '
    (.nameWithOwner | type == "string") and
    ((.nameWithOwner | ascii_downcase) == ($repository | ascii_downcase)) and
    (.defaultBranchRef.name | type == "string" and length > 0)
  ' >/dev/null || { printf 'GitHub repository metadata is invalid\n' >&2; exit 1; }
  repository=$(printf '%s' "$repo_json" | jq -r '.nameWithOwner')
  base_branch=$(printf '%s' "$repo_json" | jq -r '.defaultBranchRef.name')
  git check-ref-format "refs/heads/$base_branch" >/dev/null || { printf 'GitHub default branch is invalid\n' >&2; exit 1; }
  git fetch --no-tags -- "$github_remote" "refs/heads/$base_branch" || { printf 'GitHub default branch fetch failed before claim\n' >&2; exit 1; }
  base_commit=$(git rev-parse --verify 'FETCH_HEAD^{commit}')
  github=$(jq -n --arg remote "$github_remote" --arg repository "$repository" --arg base "$base_branch" '{remote:$remote,repository:$repository,base_branch:$base}')
fi
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
  --arg workspace "$workspace" --arg branch "$branch" --arg base "$base_commit" --arg actor "$actor" --argjson github "$github" \
  --argjson issue "$(printf '%s' "$claim_json" | jq '.issue')" \
  '{issue_uid:$uid,short_id:$short,qualified_id:$qualified,workspace:$workspace,branch:$branch,base_commit:$base,actor:$actor,github:$github,issue:$issue}' >"$state_tmp"
mv "$state_tmp" "$TRACKER_RUN_DIR/selected.json"
git switch -c "$branch" "$base_commit" >/dev/null
printf 'claim-ok\nSTATE_PATH=%s\n' "$TRACKER_RUN_DIR/selected.json"
