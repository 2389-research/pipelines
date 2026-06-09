#!/usr/bin/env bats
# test_fetch_open_issues.bats — covers fetched-ok and fetch-failed.
# Uses a PATH shim to mock `gh` without hitting the network.

setup() {
  load 'test_helpers'
  setup_env
  stage_run
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/fetch_open_issues.sh"
  FIXTURE="${BATS_TEST_DIRNAME}/fixtures/issues_sample.json"

  # PATH shim directory.
  SHIM="${TMPDIR}/bin"
  mkdir -p "${SHIM}"
  export PATH="${SHIM}:${PATH}"
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

@test "fetched-ok writes issues.json + count" {
  write_gh_shim "cat '${FIXTURE}'; exit 0"
  run sh -c "sh -c \"\$(cat '${SCRIPT}')\" 2>/dev/null"
  [ "${status}" -eq 0 ]
  [ "${output}" = "fetched-ok" ]
  [ -f "${RUN_DIR}/issues.json" ]
  [ "$(cat "${RUN_DIR}/issues_count.txt")" = "6" ]
}

@test "gh failure routes to fetch-failed" {
  write_gh_shim "echo 'gh: rate limited' >&2; exit 4"
  run sh -c "sh -c \"\$(cat '${SCRIPT}')\" 2>/dev/null"
  [ "${status}" -eq 0 ]
  [ "${output}" = "fetch-failed" ]
  grep -q "gh issue list failed" "${RUN_DIR}/fetch_error.txt"
}

@test "malformed JSON from gh fails closed to fetch-failed" {
  write_gh_shim "printf 'this is not json\n'"
  run sh -c "sh -c \"\$(cat '${SCRIPT}')\" 2>/dev/null"
  [ "${status}" -eq 0 ]
  [ "${output}" = "fetch-failed" ]
  grep -q "jq parse failed" "${RUN_DIR}/fetch_error.txt"
}

@test "missing rid sentinel exits non-zero" {
  rm "${DIP_ROOT}/.current_rid"
  write_gh_shim "exit 0"
  run sh -c "sh -c \"\$(cat '${SCRIPT}')\" 2>/dev/null"
  [ "${status}" -ne 0 ]
}
