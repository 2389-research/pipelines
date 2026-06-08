#!/usr/bin/env bats
# test_worktree.bats — covers create_worktree.sh + cleanup_worktree.sh.

setup() {
  TMPDIR="$(mktemp -d)"
  export XDG_CACHE_HOME="${TMPDIR}/cache"
  DIP_ROOT="${XDG_CACHE_HOME}/dip/2389-research-pipelines"
  rid="t-$$"
  mkdir -p "${DIP_ROOT}/runs/${rid}"
  printf '%s' "${rid}" > "${DIP_ROOT}/.current_rid"
  RUN_DIR="${DIP_ROOT}/runs/${rid}"

  # Fresh git repo under workdir for worktree to act on.
  WORKDIR="${TMPDIR}/repo"
  mkdir -p "${WORKDIR}"
  cd "${WORKDIR}"
  git init -q -b main
  git config user.email "test@example.com"
  git config user.name "Test"
  echo "seed" > README.md
  git add README.md
  git commit -q -m "seed"

  printf 'fix/42-test-fixture' > "${RUN_DIR}/branch_name.txt"
  printf '42' > "${RUN_DIR}/selected_issue_number.txt"

  CREATE="${BATS_TEST_DIRNAME}/../scripts/create_worktree.sh"
  CLEANUP="${BATS_TEST_DIRNAME}/../scripts/cleanup_worktree.sh"
}

teardown() {
  rm -rf "${TMPDIR}"
}

@test "create_worktree provisions a worktree on a new branch" {
  run sh -c "$(cat "${CREATE}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "worktree-ok" ]
  [ -d "${WORKDIR}/.dev_loop_worktree" ]
  [ -d "${RUN_DIR}/worktree" ]
  [ -f "${RUN_DIR}/worktree.path" ]
  branch="$(cd "${WORKDIR}/.dev_loop_worktree" && git branch --show-current)"
  [ "${branch}" = "fix/42-test-fixture" ]
}

@test "create_worktree refuses to clobber an existing non-symlink directory at .dev_loop_worktree" {
  # User foot-gun: an unrelated directory at the symlink path. Script must
  # NOT rm -rf it. (Earlier versions did.)
  mkdir "${WORKDIR}/.dev_loop_worktree"
  echo "important user data" > "${WORKDIR}/.dev_loop_worktree/keep.txt"
  run sh -c "$(cat "${CREATE}")"
  [ "${output}" = "worktree-failed" ]
  # Critical: the user's directory and file are still there.
  [ -d "${WORKDIR}/.dev_loop_worktree" ]
  [ ! -L "${WORKDIR}/.dev_loop_worktree" ]
  [ -f "${WORKDIR}/.dev_loop_worktree/keep.txt" ]
  grep -q "not a symlink" "${RUN_DIR}/worktree_error.txt"
}

@test "create_worktree without branch_name.txt fails" {
  rm "${RUN_DIR}/branch_name.txt"
  run sh -c "$(cat "${CREATE}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "worktree-failed" ]
  grep -q "missing branch_name" "${RUN_DIR}/worktree_error.txt"
}

@test "cleanup_worktree removes a created worktree" {
  run sh -c "$(cat "${CREATE}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "worktree-ok" ]
  run sh -c "$(cat "${CLEANUP}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "worktree-cleaned" ]
  [ ! -e "${WORKDIR}/.dev_loop_worktree" ]
}

@test "cleanup_worktree refuses path-traversal escape from RUN_DIR" {
  # Stage an "innocent bystander" directory outside RUN_DIR that must NOT be
  # touched. Then plant a malicious worktree.path that lexically passes the
  # `${RUN_DIR}/worktree` prefix check but resolves via .. to the bystander.
  bystander="${WORKDIR}/bystander"
  mkdir -p "${bystander}"
  echo "important data" > "${bystander}/keep.txt"
  # rel path that lexically starts with ${RUN_DIR}/worktree but escapes via ..
  mkdir -p "${RUN_DIR}/worktree"
  printf '%s' "${RUN_DIR}/worktree/../../bystander" > "${RUN_DIR}/worktree.path"

  run sh -c "$(cat "${CLEANUP}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "worktree-cleaned" ]
  # Bystander dir + file must survive — readlink -f canonicalization caught
  # the traversal.
  [ -d "${bystander}" ]
  [ -f "${bystander}/keep.txt" ]
  grep -q "refused to clean unsafe path" "${RUN_DIR}/cleanup_log.txt"
}

@test "cleanup_worktree is idempotent (no worktree)" {
  run sh -c "$(cat "${CLEANUP}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "worktree-cleaned" ]
}

@test "cleanup_worktree drops the .current_rid sentinel" {
  run sh -c "$(cat "${CLEANUP}")"
  [ "${status}" -eq 0 ]
  [ ! -f "${DIP_ROOT}/.current_rid" ]
}
