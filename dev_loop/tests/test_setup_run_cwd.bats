#!/usr/bin/env bats
# test_setup_run_cwd.bats — Block 2: setup_run.sh cd's to the git top-level
# at the very start so paths resolve consistently regardless of operator
# subdirectory cwd. When not in a git repo, emits setup-failed with an
# actionable message.

setup() {
  load 'test_helpers'
  setup_env
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/setup_run.sh"
}

teardown() { rm -rf "${TMPDIR}"; }

@test "not in a git repo: emits setup-failed naming the cwd" {
  # WORKDIR is a fresh mktemp dir — NOT a git repo. setup_run.sh must
  # refuse before trying to read dev_loop/config/, since paths from cwd
  # would resolve unpredictably.
  rm -rf "${WORKDIR}/.git"
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "setup-failed" ]
  rid="$(cat "${DIP_ROOT}/.current_rid")"
  grep -qi "not in a git repo\|not a git" \
    "${DIP_ROOT}/runs/${rid}/setup_error.txt"
}

@test "from a subdirectory: cwd is resolved to repo top-level" {
  # Initialize a real git repo in WORKDIR, stage dev_loop/ config under
  # the repo root, then run setup_run.sh from a subdirectory. The YAML
  # peek (reads dev_loop/config/dev_loop.config.yaml from cwd) must still
  # find the file — proving the cd happened.
  cd "${WORKDIR}"
  git init -q
  git config user.email test@example.com
  git config user.name test
  mkdir -p dev_loop/config
  cat > dev_loop/config/dev_loop.config.yaml <<'YAML'
repo: test-org/test-repo
base_branch: main
YAML
  mkdir -p subdir/deeper
  cd subdir/deeper
  # tracker per-node artifact dir must exist at the repo root for the
  # discovery block to succeed.
  mkdir -p "${WORKDIR}/.tracker/runs/trk-$$"
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "setup-ok" ]
  rid="$(cat "${DIP_ROOT}/.current_rid")"
  grep -q "^GH_REPO='test-org/test-repo'$" \
    "${DIP_ROOT}/runs/${rid}/env"
}
