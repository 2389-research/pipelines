#!/usr/bin/env bats
# test_pre_filter.bats — covers filter-ok, filter-empty, filter-failed.

setup() {
  load 'test_helpers'
  setup_env
  stage_run
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/pre_filter_issues.sh"
  FIXTURE="${BATS_TEST_DIRNAME}/fixtures/issues_sample.json"
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

@test "priority label variants (priority/P0, P0 - critical, prio:P1) sort correctly" {
  cat > "${RUN_DIR}/issues.json" <<'JSON'
[
  {"number":201,"title":"prio:P1 stuff","url":"https://github.com/test/test/issues/201","labels":[{"name":"prio:P1"}],"author":{"login":"a"},"createdAt":"2026-06-01T00:00:00Z","body":""},
  {"number":202,"title":"variant","url":"https://github.com/test/test/issues/202","labels":[{"name":"priority/P0"}],"author":{"login":"b"},"createdAt":"2026-06-02T00:00:00Z","body":""},
  {"number":203,"title":"verbose","url":"https://github.com/test/test/issues/203","labels":[{"name":"P0 - critical"}],"author":{"login":"c"},"createdAt":"2026-06-03T00:00:00Z","body":""},
  {"number":204,"title":"colon","url":"https://github.com/test/test/issues/204","labels":[{"name":"priority:P2"}],"author":{"login":"d"},"createdAt":"2026-06-04T00:00:00Z","body":""}
]
JSON
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${lines[0]}" = "filter-ok" ]
  # Ordering MUST be: 202 (priority/P0) | 203 (P0 - critical), then 201 (prio:P1), then 204 (priority:P2).
  ordering="$(jq -r '[.[] | .number] | join(",")' "${RUN_DIR}/filtered_issues.json")"
  # P0 group goes first; the two P0s tie on rank so they are ordered by issue_number ASC.
  [ "${ordering}" = "202,203,201,204" ]
}

@test "filter drops excluded title patterns" {
  cp "${FIXTURE}" "${RUN_DIR}/issues.json"
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  meta_count="$(jq '[.[] | select(.title | test("dev_loop|dippin meta|tracker meta"; "i"))] | length' "${RUN_DIR}/filtered_issues.json")"
  [ "${meta_count}" = "0" ]
}

@test "YAML excluded_labels override filters out custom labels" {
  rid="rid-$$"
  stage_run "${rid}"
  mkdir -p "${WORKDIR}/dev_loop/config"
  cat > "${WORKDIR}/dev_loop/config/dev_loop.config.yaml" <<'YAML'
issue_filter:
  excluded_labels: ["wontfix"]
  excluded_title_regex: "(?i)WIP:"
YAML

  cat > "${DIP_ROOT}/runs/${rid}/issues.json" <<'JSON'
[
  {"number":1,"title":"keep me","url":"https://github.com/test/test/issues/1","labels":[{"name":"P1"}],"author":{"login":"a"},"createdAt":"2026-06-01T00:00:00Z","body":""},
  {"number":2,"title":"WIP: skip","url":"https://github.com/test/test/issues/2","labels":[{"name":"P1"}],"author":{"login":"a"},"createdAt":"2026-06-01T00:00:00Z","body":""},
  {"number":3,"title":"label skip","url":"https://github.com/test/test/issues/3","labels":[{"name":"wontfix"}],"author":{"login":"a"},"createdAt":"2026-06-01T00:00:00Z","body":""}
]
JSON

  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/pre_filter_issues.sh"
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  count=$(cat "${DIP_ROOT}/runs/${rid}/filter_count.txt")
  [ "${count}" = "1" ]
  jq -e '.[0].number == 1' "${DIP_ROOT}/runs/${rid}/filtered_issues.json"
}
