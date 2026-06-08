#!/usr/bin/env bats
# test_pre_filter.bats — covers filter-ok, filter-empty, filter-failed.

setup() {
  TMPDIR="$(mktemp -d)"
  export XDG_CACHE_HOME="${TMPDIR}/cache"
  DIP_ROOT="${XDG_CACHE_HOME}/dip/2389-research-pipelines"
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/pre_filter_issues.sh"
  FIXTURE="${BATS_TEST_DIRNAME}/fixtures/issues_sample.json"
  # Allocate a rid manually so the filter can find its run dir.
  rid="t-$$"
  mkdir -p "${DIP_ROOT}/runs/${rid}"
  printf '%s' "${rid}" > "${DIP_ROOT}/.current_rid"
  RUN_DIR="${DIP_ROOT}/runs/${rid}"
}

teardown() {
  rm -rf "${TMPDIR}"
}

@test "filter-ok with sample fixture and three survivors" {
  cp "${FIXTURE}" "${RUN_DIR}/issues.json"
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${lines[0]}" = "filter-ok" ]
  count="$(cat "${RUN_DIR}/filter_count.txt")"
  [ "${count}" = "3" ]
  first_number="$(jq '.[0].number' "${RUN_DIR}/filtered_issues.json")"
  [ "${first_number}" = "100" ]
}

@test "filter-ok preserves descending priority ordering" {
  cp "${FIXTURE}" "${RUN_DIR}/issues.json"
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  priorities="$(jq -r '[.[] | (.labels[0].name // "none")] | join(",")' "${RUN_DIR}/filtered_issues.json")"
  [ "${priorities}" = "P0,P1,none" ]
}

@test "empty input emits filter-empty" {
  printf '[]' > "${RUN_DIR}/issues.json"
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "filter-empty" ]
  [ "$(cat "${RUN_DIR}/filter_count.txt")" = "0" ]
}

@test "missing input emits filter-failed" {
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "filter-failed" ]
  grep -q "issues.json missing" "${RUN_DIR}/filter_error.txt"
}

@test "filter drops bot authors" {
  cp "${FIXTURE}" "${RUN_DIR}/issues.json"
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  bot_count="$(jq '[.[] | select(.author.login | test("\\[bot\\]$"))] | length' "${RUN_DIR}/filtered_issues.json")"
  [ "${bot_count}" = "0" ]
}

@test "filter drops excluded title patterns" {
  cp "${FIXTURE}" "${RUN_DIR}/issues.json"
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  meta_count="$(jq '[.[] | select(.title | test("dev_loop|dippin meta|tracker meta"; "i"))] | length' "${RUN_DIR}/filtered_issues.json")"
  [ "${meta_count}" = "0" ]
}
