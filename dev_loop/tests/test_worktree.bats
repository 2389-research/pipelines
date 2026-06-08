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
