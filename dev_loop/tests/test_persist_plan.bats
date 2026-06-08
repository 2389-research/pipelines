#!/usr/bin/env bats
# test_persist_plan.bats — covers persist_plan.sh + sidecar branch/PR files.

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
  mkdir -p "${TRACKER_RUN}/PlanMinimalPRs"

  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/persist_plan.sh"
  FIXTURES="${BATS_TEST_DIRNAME}/fixtures"
  cp "${FIXTURES}/plan_sample.json" "${TRACKER_RUN}/PlanMinimalPRs/response.md"
}

teardown() {
  rm -rf "${TMPDIR}"
}

@test "persists plan.json + extracts branch_name / pr_title / pr_body" {
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${lines[0]}" = "persisted-plan" ]
  [ -f "${RUN_DIR}/plan.json" ]
  [ -f "${RUN_DIR}/branch_name.txt" ]
  [ -f "${RUN_DIR}/pr_title.txt" ]
  [ -f "${RUN_DIR}/pr_body.txt" ]
  branch="$(cat "${RUN_DIR}/branch_name.txt")"
  [ "${branch}" = "fix/42-writable-paths-anchor" ]
}

@test "missing response.md exits non-zero" {
  rm -f "${TRACKER_RUN}/PlanMinimalPRs/response.md"
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -ne 0 ]
  grep -q "response missing" "${RUN_DIR}/persist_plan_error.txt"
}
