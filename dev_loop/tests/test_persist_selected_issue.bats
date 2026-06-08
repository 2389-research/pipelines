#!/usr/bin/env bats
# test_persist_selected_issue.bats — covers persist_selected_issue.sh +
# sidecar selected_issue_number.txt.

setup() {
  TMPDIR="$(mktemp -d)"
  export XDG_CACHE_HOME="${TMPDIR}/cache"
  DIP_ROOT="${XDG_CACHE_HOME}/dip/2389-research-pipelines"
  rid="t-$$"
  mkdir -p "${DIP_ROOT}/runs/${rid}"
  printf '%s' "${rid}" > "${DIP_ROOT}/.current_rid"
  RUN_DIR="${DIP_ROOT}/runs/${rid}"

  WORKDIR="${TMPDIR}/workdir"
  mkdir -p "${WORKDIR}"
  cd "${WORKDIR}"
  TRACKER_RUN="${WORKDIR}/.tracker/runs/trk-$$"
  mkdir -p "${TRACKER_RUN}/SelectNextIssue"

  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/persist_selected_issue.sh"
  FIXTURES="${BATS_TEST_DIRNAME}/fixtures"
  cp "${FIXTURES}/selected_issue_sample.json" "${TRACKER_RUN}/SelectNextIssue/response.md"
}

teardown() {
  rm -rf "${TMPDIR}"
}

@test "persists selected_issue.json + emits issue number sidecar" {
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${lines[0]}" = "persisted-selected" ]
  [ -f "${RUN_DIR}/selected_issue.json" ]
  [ -f "${RUN_DIR}/selected_issue_number.txt" ]
  num="$(cat "${RUN_DIR}/selected_issue_number.txt")"
  [ "${num}" = "42" ]
}

@test "missing response.md exits non-zero with error file" {
  rm -f "${TRACKER_RUN}/SelectNextIssue/response.md"
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -ne 0 ]
  grep -q "response missing" "${RUN_DIR}/persist_selected_error.txt"
}
