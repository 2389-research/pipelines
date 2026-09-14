#!/bin/sh
# ABOUTME: Checks approved-commit publication with real Git pushes to temporary bare repositories.
# ABOUTME: Uses gh and kata response fixtures only for orchestration, not end-to-end coverage.
set -eu
pipeline_dir=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT HUP INT TERM
mkdir -p "$test_root/bin"
cat >"$test_root/bin/kata" <<'KATA'
#!/bin/sh
set -eu
printf 'kata %s\n' "$*" >>"$TEST_EVENTS"
case "$1" in
 show) printf '{"issue":{"uid":"selected","owner":"runner","status":"%s"}}\n' "${ISSUE_STATUS:-open}" ;;
 close) printf '%s\n' "$*" >"$TEST_CLOSE" ;;
 *) exit 2 ;;
esac
KATA
cat >"$test_root/bin/gh" <<'GH'
#!/bin/sh
set -eu
printf 'gh %s\n' "$*" >>"$TEST_EVENTS"
operation=$2
shift 2
repo= head= base= body= target= title=
while [ "$#" -gt 0 ]; do
 case "$1" in
  --repo) repo=$2; shift 2 ;;
  --head) head=$2; shift 2 ;;
  --base) base=$2; shift 2 ;;
  --body-file) body=$2; shift 2 ;;
  --title) title=$2; shift 2 ;;
  --json|--state|--limit) shift 2 ;;
  --draft) printf 'unexpected draft\n' >&2; exit 2 ;;
  *) target=$1; shift ;;
 esac
done
[ "$repo" = 'github.com/owner/project' ] || { printf 'missing explicit GitHub host/repository\n' >&2; exit 2; }
record() {
 jq -n --arg oid "${PR_HEAD:-$TEST_HEAD}" --arg head "${PR_BRANCH:-kata/publish}" \
  --argjson cross "${PR_CROSS:-false}" \
  '{url:"https://github.com/owner/project/pull/42",headRefOid:$oid,headRefName:$head,baseRefName:"main",isCrossRepository:$cross,state:"OPEN",isDraft:false}'
}
case "$operation" in
 list)
  [ "$head" = kata/publish ] && [ "$base" = main ]
  [ "${GH_FAILURE:-}" != list ] || exit 7
  if [ "${PR_EXISTS:-0}" = 1 ] || [ -f "$TEST_CREATED" ]; then
   if [ "${PR_AMBIGUOUS:-0}" = 1 ]; then record | jq -s '.[0] as $pr | [$pr,$pr]'
   elif [ "${PR_NO_URL:-0}" = 1 ]; then record | jq -s 'map(del(.url))'
   else record | jq -s '.'; fi
  else printf '[]\n'; fi ;;
 create)
  [ "$head" = kata/publish ] && [ "$base" = main ] && [ -s "$body" ]
  [ "$title" = 'Preserve the approved commit when publishing' ] || { printf 'PR title lost selected issue title\n' >&2; exit 2; }
  cp "$body" "$TEST_BODY"
  [ "${GH_FAILURE:-}" != create ] || exit 7
  touch "$TEST_CREATED"
  [ "${GH_FAILURE:-}" != after-create ] || exit 7
  printf 'https://github.com/owner/project/pull/42\n' ;;
 view)
  [ "$target" = https://github.com/owner/project/pull/42 ]
  [ "${GH_FAILURE:-}" != view ] || exit 7
  record
  if [ "${MUTATE_TREE:-0}" = 1 ]; then printf 'concurrent change\n' >>task; fi ;;
 *) exit 2 ;;
esac
GH
chmod +x "$test_root/bin/kata" "$test_root/bin/gh"
export PATH="$test_root/bin:$PATH"
new_case() {
 case_dir="$test_root/$1"
 repo="$case_dir/repo"
 bare="$case_dir/remote.git"
 run_dir="$repo/.tracker/run"
 git init -q -b main "$repo"
 git init -q --bare "$bare"
 git --git-dir="$bare" config core.hooksPath "$bare/hooks"
 git -C "$repo" config user.name 'Pipeline check'
 git -C "$repo" config user.email 'pipeline-check@example.invalid'
 printf '.tracker/\n' >"$repo/.gitignore"
 git -C "$repo" add .gitignore
 git -C "$repo" commit -qm 'test: seed publishing repository'
 base=$(git -C "$repo" rev-parse HEAD)
 git -C "$repo" switch -qc kata/publish
 printf 'verified task change\n' >"$repo/task"
 git -C "$repo" add task
 git -C "$repo" commit -qm 'fix: implement selected kata'
 TEST_HEAD=$(git -C "$repo" rev-parse HEAD)
 git -C "$repo" remote add origin https://github.com/owner/project.git
 git -C "$repo" config "url.$bare.insteadOf" https://github.com/owner/project.git
 mkdir -p "$run_dir"
 jq -n --arg workspace "$repo" --arg base "$base" \
  '{workspace:$workspace,base_commit:$base,branch:"kata/publish",issue_uid:"selected",actor:"runner",issue:{title:"Preserve the approved commit when publishing",qualified_id:"demo#selected"},github:{remote:"origin",repository:"owner/project",base_branch:"main"}}' >"$run_dir/selected.json"
 printf '%s\n' "$TEST_HEAD" | tee "$run_dir/review-correctness.approved" >"$run_dir/review-scope.approved"
 printf 'scripts/check\n' >"$run_dir/verification.txt"
 printf 'Implemented the selected task and checked its behavior against the acceptance criteria.\n' >"$run_dir/completion.md"
 TEST_EVENTS="$case_dir/events" TEST_CLOSE="$case_dir/closed" TEST_BODY="$case_dir/body" TEST_CREATED="$case_dir/created"
 export TEST_HEAD TEST_EVENTS TEST_CLOSE TEST_BODY TEST_CREATED
 unset GH_FAILURE PR_EXISTS PR_HEAD PR_BRANCH PR_CROSS PR_AMBIGUOUS PR_NO_URL ISSUE_STATUS MUTATE_TREE
 cat >"$bare/hooks/post-receive" <<'HOOK'
#!/bin/sh
printf 'push\n' >>"$TEST_EVENTS"
HOOK
 chmod +x "$bare/hooks/post-receive"
}
run_close() {
 TRACKER_RUN_DIR="$run_dir" TRACKER_WORKDIR="$repo" "$pipeline_dir/scripts/close-selected.sh" >"$case_dir/output" 2>&1
}
reject() {
 if run_close; then printf 'FAIL: publication accepted %s\n' "$1" >&2; exit 1; fi
 [ ! -f "$TEST_CLOSE" ] || { printf 'FAIL: closed kata after %s\n' "$1" >&2; exit 1; }
}
not_pushed() {
 if git --git-dir="$bare" show-ref --verify --quiet refs/heads/kata/publish; then
  printf 'FAIL: unapproved publication\n' >&2; exit 1
 fi
}
new_case publish
run_close || { cat "$case_dir/output" >&2; exit 1; }
[ "$(git --git-dir="$bare" rev-parse refs/heads/kata/publish 2>/dev/null)" = "$TEST_HEAD" ] || { printf 'FAIL: approved commit was not published\n' >&2; exit 1; }
[ "$(cat "$run_dir/pr-url.txt")" = https://github.com/owner/project/pull/42 ]
grep -F 'https://github.com/owner/project/pull/42' "$TEST_CLOSE" >/dev/null
grep -F "$TEST_HEAD" "$TEST_BODY" >/dev/null
grep -F 'scripts/check' "$TEST_BODY" >/dev/null
grep -F 'demo#selected' "$TEST_BODY" >/dev/null
grep -F 'https://github.com/owner/project/pull/42' "$case_dir/output" >/dev/null
awk '/^push$/{p=NR} /^gh pr view/{v=NR} /^kata close/{c=NR} END{exit !(p>0 && v>p && c>v)}' "$TEST_EVENTS"
new_case slash-remote
git -C "$repo" remote rename origin upstream/github
jq '.github.remote = "upstream/github"' "$run_dir/selected.json" >"$case_dir/state"
mv "$case_dir/state" "$run_dir/selected.json"
run_close || { cat "$case_dir/output" >&2; exit 1; }
[ "$(git --git-dir="$bare" rev-parse refs/heads/kata/publish)" = "$TEST_HEAD" ]
[ -f "$TEST_CLOSE" ]
new_case follow-tags
git -C "$repo" config push.followTags true
git -C "$repo" tag -a unrelated-release "$base" -m 'Existing release outside selected task'
run_close || { cat "$case_dir/output" >&2; exit 1; }
[ "$(git --git-dir="$bare" rev-parse refs/heads/kata/publish)" = "$TEST_HEAD" ]
if git --git-dir="$bare" show-ref --verify --quiet refs/tags/unrelated-release; then
 printf 'FAIL: publication pushed an unrelated tag\n' >&2; exit 1
fi
new_case local
jq '.github = null' "$run_dir/selected.json" >"$case_dir/state"
mv "$case_dir/state" "$run_dir/selected.json"
run_close
[ -f "$TEST_CLOSE" ]
if grep '^gh ' "$TEST_EVENTS"; then exit 1; fi
not_pushed
new_case missing-state
jq 'del(.github)' "$run_dir/selected.json" >"$case_dir/state"
mv "$case_dir/state" "$run_dir/selected.json"
reject missing-state
not_pushed
grep -F 'setup state is missing' "$case_dir/output" >/dev/null
new_case reuse
export PR_EXISTS=1
run_close
if grep '^gh pr create' "$TEST_EVENTS"; then exit 1; fi
[ -f "$TEST_CLOSE" ]
for failure in list create view after-create; do
 new_case "gh-$failure"
 export GH_FAILURE="$failure"
 reject "gh-$failure"
 if [ "$failure" = after-create ]; then
  unset GH_FAILURE
  run_close
  [ "$(grep -c '^gh pr create' "$TEST_EVENTS")" = 1 ]
 fi
done
new_case push-failure
printf '#!/bin/sh\nexit 1\n' >"$bare/hooks/pre-receive"
chmod +x "$bare/hooks/pre-receive"
reject push-failure
if grep '^gh pr create' "$TEST_EVENTS"; then exit 1; fi
not_pushed
new_case stale
printf '%s\n' "$base" >"$run_dir/review-scope.approved"
reject stale
not_pushed
new_case ownership
export ISSUE_STATUS=closed
reject ownership
not_pushed
new_case concurrent-change
export MUTATE_TREE=1
reject concurrent-change
for mismatch in changed-fetch changed-push multiple-push; do
 new_case "$mismatch"
 case "$mismatch" in
  changed-fetch) git -C "$repo" remote set-url origin https://github.com/other/project.git ;;
  changed-push) git -C "$repo" remote set-url --push origin git@github.com:other/project.git ;;
  multiple-push)
   git -C "$repo" config --add remote.origin.pushurl git@github.com:owner/project.git
   git -C "$repo" config --add remote.origin.pushurl https://github.com/owner/project.git ;;
 esac
 reject "$mismatch"
 not_pushed
done
for mismatch in oid branch cross ambiguous missing-url; do
 new_case "pr-$mismatch"
 export PR_EXISTS=1
 case "$mismatch" in
  oid) export PR_HEAD="$base" ;;
  branch) export PR_BRANCH=kata/other ;;
  cross) export PR_CROSS=true ;;
  ambiguous) export PR_AMBIGUOUS=1 ;;
  missing-url) export PR_NO_URL=1 ;;
 esac
 reject "pr-$mismatch"
done
printf 'ok - approved commit publication, PR reuse, and failure gates (Git integration; gh/kata orchestration fixtures)\n'
