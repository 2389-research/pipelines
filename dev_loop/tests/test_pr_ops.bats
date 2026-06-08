#!/usr/bin/env bats
# test_pr_ops.bats — covers push_and_open_pr, fetch_pr_context, recheck_pr_sha,
# merge_pr, post_squad_comment. Mocks `gh` and `git` via a PATH shim.

setup() {
  TMPDIR="$(mktemp -d)"
  export XDG_CACHE_HOME="${TMPDIR}/cache"
  DIP_ROOT="${XDG_CACHE_HOME}/dip/2389-research-pipelines"
  rid="t-$$"
  mkdir -p "${DIP_ROOT}/runs/${rid}"
  printf '%s' "${rid}" > "${DIP_ROOT}/.current_rid"
  RUN_DIR="${DIP_ROOT}/runs/${rid}"

  WORKDIR="${TMPDIR}/repo"
  mkdir -p "${WORKDIR}"
  cd "${WORKDIR}"
  git init -q -b main
  git config user.email "test@example.com"
  git config user.name "Test"
  echo seed > README.md && git add README.md && git commit -q -m seed

  # Pre-populate state needed by the scripts.
  printf 'fix/42-test' > "${RUN_DIR}/branch_name.txt"
  printf 'fix(test): PR title' > "${RUN_DIR}/pr_title.txt"
  printf 'PR body content for testing\n' > "${RUN_DIR}/pr_body.txt"
  printf '42' > "${RUN_DIR}/selected_issue_number.txt"

  SHIM="${TMPDIR}/bin"
  mkdir -p "${SHIM}"
  export PATH="${SHIM}:${PATH}"
  SCRIPTS="${BATS_TEST_DIRNAME}/../scripts"
}

teardown() {
  rm -rf "${TMPDIR}"
}

write_gh_shim() {
  cat > "${SHIM}/gh" <<EOF
#!/bin/sh
$1
EOF
  chmod +x "${SHIM}/gh"
}

# --- push_and_open_pr -------------------------------------------------------

@test "push_and_open_pr happy path emits pr-ready" {
  # create worktree first
  sh -c "$(cat "${SCRIPTS}/create_worktree.sh")" >/dev/null
  write_gh_shim '
case "$1" in
  pr) shift; case "$1" in
    list) printf "[]"; exit 0 ;;
    create) exit 0 ;;
    view) printf "{\"number\":7,\"url\":\"https://example.com/pr/7\",\"headRefOid\":\"abc123\"}"; exit 0 ;;
  esac ;;
esac
exit 0'
  # mock git push so it does not actually push
  cat > "${SHIM}/git" <<'EOF'
#!/bin/sh
if [ "$1" = "push" ]; then exit 0; fi
exec /usr/bin/git "$@"
EOF
  chmod +x "${SHIM}/git"

  run sh -c "$(cat "${SCRIPTS}/push_and_open_pr.sh")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "pr-ready" ]
  [ "$(cat "${RUN_DIR}/pr_number.txt")" = "7" ]
}

@test "push_and_open_pr without worktree.path fails" {
  run sh -c "$(cat "${SCRIPTS}/push_and_open_pr.sh")"
  [ "${output}" = "pr-push-failed" ]
  grep -q "worktree.path missing" "${RUN_DIR}/push_error.txt"
}

# --- fetch_pr_context -------------------------------------------------------

@test "fetch_pr_context returns pr-context-ok on first line for an OPEN PR" {
  printf '7' > "${RUN_DIR}/pr_number.txt"
  write_gh_shim '
if [ "$1" = "pr" ] && [ "$2" = "view" ]; then
  printf "{\"state\":\"OPEN\",\"mergedAt\":null,\"headRefOid\":\"sha-now\",\"number\":7,\"url\":\"u\",\"headRefName\":\"b\",\"baseRefName\":\"main\"}"
  exit 0
fi
exit 0'
  run sh -c "$(cat "${SCRIPTS}/fetch_pr_context.sh")"
  [ "${status}" -eq 0 ]
  [ "${lines[0]}" = "pr-context-ok" ]
  [ "$(cat "${RUN_DIR}/pr_head_sha.txt")" = "sha-now" ]
  # The stdout embeds the diff + plan + feedback + repo_conventions sections for the reviewers.
  printf '%s\n' "${output}" | grep -q -- "<pr_diff>"
  printf '%s\n' "${output}" | grep -q -- "<plan>"
  printf '%s\n' "${output}" | grep -q -- "<feedback>"
  printf '%s\n' "${output}" | grep -q -- "<repo_conventions>"
}

@test "fetch_pr_context emits pr-merged-externally when state=MERGED" {
  printf '7' > "${RUN_DIR}/pr_number.txt"
  write_gh_shim '
if [ "$1" = "pr" ] && [ "$2" = "view" ]; then
  printf "{\"state\":\"MERGED\",\"mergedAt\":\"2026-06-05T15:00:00Z\",\"headRefOid\":\"sha\",\"number\":7,\"url\":\"u\",\"headRefName\":\"b\",\"baseRefName\":\"main\"}"
fi
exit 0'
  run sh -c "$(cat "${SCRIPTS}/fetch_pr_context.sh")"
  [ "${output}" = "pr-merged-externally" ]
}

@test "fetch_pr_context emits pr-closed when state=CLOSED" {
  printf '7' > "${RUN_DIR}/pr_number.txt"
  write_gh_shim '
if [ "$1" = "pr" ] && [ "$2" = "view" ]; then
  printf "{\"state\":\"CLOSED\",\"mergedAt\":null,\"headRefOid\":\"sha\",\"number\":7,\"url\":\"u\",\"headRefName\":\"b\",\"baseRefName\":\"main\"}"
fi
exit 0'
  run sh -c "$(cat "${SCRIPTS}/fetch_pr_context.sh")"
  [ "${output}" = "pr-closed" ]
}

# --- recheck_pr_sha ---------------------------------------------------------

@test "recheck_pr_sha emits sha-same when SHA matches pinned value" {
  printf '7' > "${RUN_DIR}/pr_number.txt"
  printf 'abc123' > "${RUN_DIR}/pr_head_sha.txt"
  write_gh_shim 'printf abc123'
  run sh -c "$(cat "${SCRIPTS}/recheck_pr_sha.sh")"
  [ "${output}" = "sha-same" ]
}

@test "recheck_pr_sha emits sha-drifted when SHA differs" {
  printf '7' > "${RUN_DIR}/pr_number.txt"
  printf 'abc123' > "${RUN_DIR}/pr_head_sha.txt"
  write_gh_shim 'printf "def456"'
  run sh -c "$(cat "${SCRIPTS}/recheck_pr_sha.sh")"
  [ "${output}" = "sha-drifted" ]
}

# --- merge_pr ---------------------------------------------------------------

@test "merge_pr happy path emits merge-ok" {
  printf '7' > "${RUN_DIR}/pr_number.txt"
  write_gh_shim 'printf "merged.\n"; exit 0'
  run sh -c "$(cat "${SCRIPTS}/merge_pr.sh")"
  [ "${output}" = "merge-ok" ]
}

@test "merge_pr emits merge-blocked with protected reason when branch-protection error" {
  printf '7' > "${RUN_DIR}/pr_number.txt"
  write_gh_shim 'echo "GraphQL: Branch protection rule violation" >&2; exit 1'
  run sh -c "$(cat "${SCRIPTS}/merge_pr.sh")"
  [ "${output}" = "merge-blocked" ]
  [ "$(cat "${RUN_DIR}/merge_block_reason.txt")" = "protected" ]
}

@test "merge_pr emits merge-blocked with conflicts reason on merge conflict" {
  printf '7' > "${RUN_DIR}/pr_number.txt"
  write_gh_shim 'echo "Pull request has merge conflict" >&2; exit 1'
  run sh -c "$(cat "${SCRIPTS}/merge_pr.sh")"
  [ "${output}" = "merge-blocked" ]
  [ "$(cat "${RUN_DIR}/merge_block_reason.txt")" = "conflicts" ]
}

# --- post_squad_comment -----------------------------------------------------

@test "post_squad_comment always emits comment-posted" {
  printf '7' > "${RUN_DIR}/pr_number.txt"
  printf '{"outcome":"changes_requested","summary":"some feedback","reasoning":"because tests","block_count":1,"attest_valid":true,"feedback":[]}' \
    > "${RUN_DIR}/synthesis.json"
  printf '1' > "${RUN_DIR}/iter.txt"
  write_gh_shim 'exit 0'
  run sh -c "$(cat "${SCRIPTS}/post_squad_comment.sh")"
  [ "${output}" = "comment-posted" ]
  [ -f "${RUN_DIR}/squad_comment.md" ]
  grep -q "some feedback" "${RUN_DIR}/squad_comment.md"
}

@test "post_squad_comment emits comment-posted even when no PR number" {
  rm -f "${RUN_DIR}/pr_number.txt"
  run sh -c "$(cat "${SCRIPTS}/post_squad_comment.sh")"
  [ "${output}" = "comment-posted" ]
}
