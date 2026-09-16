#!/bin/sh
# ABOUTME: Publishes the approved task commit to a GitHub PR before closing its bound kata.
# ABOUTME: Checks saved repository identity and review evidence before any publication.
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
jq -e 'has("github")' "$state" >/dev/null || {
  printf 'GitHub setup state is missing; inspect and recover this saved run before retrying\n' >&2
  exit 1
}
if jq -e '.github != null' "$state" >/dev/null; then
  jq -e '.github | type == "object" and
    (.remote | type == "string" and length > 0) and
    (.repository | type == "string" and test("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")) and
    (.base_branch | type == "string" and length > 0)' "$state" >/dev/null || {
    printf 'invalid GitHub publication settings\n' >&2; exit 1
  }
  remote=$(jq -r '.github.remote' "$state")
  git check-ref-format "refs/remotes/$remote" >/dev/null || { printf 'invalid saved Git remote name\n' >&2; exit 1; }
  repository=$(jq -r '.github.repository' "$state")
  base_branch=$(jq -r '.github.base_branch' "$state")
  title=$(jq -er '.issue.title | select(type == "string" and length > 0)' "$state")
  kata_id=$(jq -r '.issue.qualified_id // .issue_uid' "$state")
  case "$branch" in kata/*) ;; *) printf 'publication requires a kata/ task branch\n' >&2; exit 1 ;; esac
  git check-ref-format "refs/heads/$branch" >/dev/null
  git check-ref-format "refs/heads/$base_branch" >/dev/null
  [ "$branch" != "$base_branch" ] || { printf 'task branch equals PR base\n' >&2; exit 1; }
  # Inspect configured identities; Git may apply local transport URL rewrites.
  fetch_url=$(git config --get-all "remote.$remote.url" || true)
  push_url=$(git config --get-all "remote.$remote.pushurl" || true)
  [ -n "$push_url" ] || push_url=$fetch_url
  github_repository() {
    case "$1" in
      https://github.com/*) repo_path=${1#https://github.com/} ;;
      git@github.com:*) repo_path=${1#git@github.com:} ;;
      ssh://git@github.com:22/*) repo_path=${1#ssh://git@github.com:22/} ;;
      ssh://git@github.com/*) repo_path=${1#ssh://git@github.com/} ;;
      *) return 1 ;;
    esac
    repo_path=${repo_path%/}
    repo_path=${repo_path%.git}
    printf '%s' "$repo_path" | jq -Rer 'select(test("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")) | ascii_downcase'
  }
  expected=$(printf '%s' "$repository" | tr '[:upper:]' '[:lower:]')
  for remote_url in "$fetch_url" "$push_url"; do
    actual=$(github_repository "$remote_url") || {
      printf 'GitHub remote must have one supported fetch URL and one push URL\n' >&2; exit 1
    }
    [ "$actual" = "$expected" ] || { printf 'GitHub remote repository changed since setup\n' >&2; exit 1; }
  done
  command -v gh >/dev/null || { printf 'gh is required to publish this GitHub task\n' >&2; exit 1; }
  git -c push.followTags=false push -- "$remote" "$head:refs/heads/$branch"
  prs=$(gh pr list --repo "github.com/$repository" --head "$branch" --base "$base_branch" --state open \
    --limit 2 --json url,headRefName,baseRefName,isCrossRepository)
  printf '%s' "$prs" | jq -e --arg branch "$branch" --arg base "$base_branch" \
    'type == "array" and length <= 1 and all(.[];
      .headRefName == $branch and .baseRefName == $base and .isCrossRepository == false and
      (.url | type == "string" and length > 0))' >/dev/null || {
    printf 'PR lookup returned ambiguous or mismatched head/base repositories\n' >&2; exit 1
  }
  pr_url=$(printf '%s' "$prs" | jq -r '.[0].url // empty')
  if [ -z "$pr_url" ]; then
    {
      printf '%s\n\n' "$completion"
      printf 'Verification: %s\n\nKata: %s (%s)\n\nApproved commit: %s\n' "$test_evidence" "$kata_id" "$uid" "$head"
    } >"$TRACKER_RUN_DIR/pr-body.md"
    pr_url=$(gh pr create --repo "github.com/$repository" --head "$branch" --base "$base_branch" \
      --title "$title" --body-file "$TRACKER_RUN_DIR/pr-body.md")
  fi
  pr=$(gh pr view "$pr_url" --repo "github.com/$repository" \
    --json url,headRefOid,headRefName,baseRefName,isCrossRepository,state,isDraft)
  printf '%s' "$pr" | jq -e --arg head "$head" --arg branch "$branch" --arg base "$base_branch" \
    '.headRefOid == $head and .headRefName == $branch and .baseRefName == $base and
      .isCrossRepository == false and .state == "OPEN" and .isDraft == false' >/dev/null || {
    printf 'published PR does not match the approved commit and ready head/base\n' >&2; exit 1
  }
  pr_url=$(printf '%s' "$pr" | jq -er '.url | select(type == "string" and length > 0)')
  printf '%s\n' "$pr_url" >"$TRACKER_RUN_DIR/pr-url.txt"
  printf 'Pull request: %s\n' "$pr_url"
  completion=$(printf '%s\n\nPull request: %s' "$completion" "$pr_url")
fi
[ "$(git rev-parse HEAD)" = "$head" ] &&
  [ "$(git symbolic-ref --quiet --short HEAD)" = "$branch" ] &&
  [ -z "$(git status --porcelain --untracked-files=normal)" ] || {
  printf 'task branch or working tree changed during publication\n' >&2; exit 1
}
kata close --workspace "$workspace" --as "$actor" "$uid" --done \
  --message "$completion" \
  --commit "$head" --test "$test_evidence" --json >/dev/null
# The warm-continue override belongs to this run's worker; the next run starts from the base budget.
rm -f "$workspace/.tracker/turn_overrides/Implement"
printf 'close-ok\n'
