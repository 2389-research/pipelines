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

@test "setup_run publishes DEV_LOOP_REPO_ROOT so downstream nodes re-anchor" {
  # Run setup_run from a subdirectory, then verify DEV_LOOP_REPO_ROOT is
  # written into the env file pointing at the repo top-level. Then run a
  # downstream script (pre_filter_issues) from yet another subdirectory
  # and assert it sees the repo root and finds the cwd-relative
  # dev_loop/config/dev_loop.config.yaml.
  cd "${WORKDIR}"
  git init -q
  git config user.email test@example.com
  git config user.name test
  mkdir -p dev_loop/config
  cat > dev_loop/config/dev_loop.config.yaml <<'YAML'
repo: test-org/test-repo
base_branch: main
issue_filter:
  excluded_labels: ["zzz-yaml-marker"]
  excluded_title_regex: "(no-match-anchor)"
YAML
  mkdir -p subdir
  cd subdir
  mkdir -p "${WORKDIR}/.tracker/runs/trk-$$"
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "setup-ok" ]
  rid="$(cat "${DIP_ROOT}/.current_rid")"
  grep -q "^DEV_LOOP_REPO_ROOT='${WORKDIR}'$" \
    "${DIP_ROOT}/runs/${rid}/env"

  # Drive pre_filter_issues from a different subdirectory. It must cd
  # back to DEV_LOOP_REPO_ROOT and read dev_loop/config/... successfully
  # (the test asserts via the YAML-marker label flowing into the jq query).
  cd "${WORKDIR}"
  printf '[]' > "${DIP_ROOT}/runs/${rid}/issues.json"
  mkdir -p subdir2
  cd subdir2
  PRE_FILTER="${BATS_TEST_DIRNAME}/../scripts/pre_filter_issues.sh"
  run sh -c "$(cat "${PRE_FILTER}")"
  [ "${status}" -eq 0 ]
  # With empty issues.json the script emits filter-empty; we only care
  # that it didn't trip filter-failed on a missing CFG (which it would
  # if the cd back to repo root hadn't happened).
  printf '%s\n' "${output}" | head -1 | grep -qE '^(filter-ok|filter-empty)$'
}

@test "packed mode (lib absent): setup_run still autodetects from git remote" {
  # Simulate the packed quickstart: AGENTS.md present, dev_loop/ tree
  # NOT checked out (no scripts/lib on disk). The fallback branch must
  # try `git remote get-url origin` inline rather than failing with
  # "no repo configured".
  cd "${WORKDIR}"
  git init -q
  git config user.email t@t
  git config user.name t
  git remote add origin "https://github.com/packed-org/packed-repo.git"
  mkdir -p "${WORKDIR}/.tracker/runs/trk-$$"
  # Point LIB_DIR at a path that doesn't exist so the helper is skipped.
  DEV_LOOP_LIB_DIR="${WORKDIR}/no/such/lib"
  # Provide DEV_LOOP_BASE_BRANCH so the test doesn't depend on `gh auth`
  # for autodetect; we're testing the repo-autodetect path specifically.
  DEV_LOOP_BASE_BRANCH=main
  export DEV_LOOP_LIB_DIR DEV_LOOP_BASE_BRANCH
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "setup-ok" ]
  rid="$(cat "${DIP_ROOT}/.current_rid")"
  grep -q "^GH_REPO='packed-org/packed-repo'$" \
    "${DIP_ROOT}/runs/${rid}/env"
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
