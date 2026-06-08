#!/usr/bin/env bats
# test_persist_synthesis.bats — covers synthesized-approved | _changes_requested | _abandoned
# routing markers + synthesis.json / feedback.json persistence.

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
  TRACKER_RID="trk-$$"
  TRACKER_RUN="${WORKDIR}/.tracker/runs/${TRACKER_RID}"
  mkdir -p "${TRACKER_RUN}/SquadSynthesizer"

  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/persist_synthesis.sh"
  FIXTURES="${BATS_TEST_DIRNAME}/fixtures"
}

teardown() {
  rm -rf "${TMPDIR}"
}

stage() {
  cp "${FIXTURES}/$1" "${TRACKER_RUN}/SquadSynthesizer/response.md"
}

@test "approved synthesis emits synthesized-approved" {
  stage synthesis_approved.json
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "synthesized-approved" ]
  [ -f "${RUN_DIR}/synthesis.json" ]
  [ -f "${RUN_DIR}/feedback.json" ]
  feedback_count="$(jq 'length' "${RUN_DIR}/feedback.json")"
  [ "${feedback_count}" -eq 0 ]
}

@test "changes_requested synthesis emits synthesized-changes_requested + non-empty feedback" {
  stage synthesis_changes_requested.json
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "synthesized-changes_requested" ]
  [ -f "${RUN_DIR}/feedback.json" ]
  feedback_count="$(jq 'length' "${RUN_DIR}/feedback.json")"
  [ "${feedback_count}" -ge 1 ]
}

@test "missing response.md falls back to synthesized-abandoned" {
  rm -f "${TRACKER_RUN}/SquadSynthesizer/response.md"
  run sh -c "$(cat "${SCRIPT}")"
  [ "${output}" = "synthesized-abandoned" ]
  [ -f "${RUN_DIR}/persist_synthesis_error.txt" ]
}

@test "missing rid sentinel falls back to synthesized-abandoned" {
  rm "${DIP_ROOT}/.current_rid"
  stage synthesis_approved.json
  run sh -c "$(cat "${SCRIPT}")"
  [ "${output}" = "synthesized-abandoned" ]
}
