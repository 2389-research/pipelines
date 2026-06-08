#!/usr/bin/env bats
# test_inc_iter_counter.bats

setup() {
  TMPDIR="$(mktemp -d)"
  export XDG_CACHE_HOME="${TMPDIR}/cache"
  DIP_ROOT="${XDG_CACHE_HOME}/dip/2389-research-pipelines"
  rid="t-$$"
  mkdir -p "${DIP_ROOT}/runs/${rid}"
  printf '%s' "${rid}" > "${DIP_ROOT}/.current_rid"
  RUN_DIR="${DIP_ROOT}/runs/${rid}"
  printf '5' > "${RUN_DIR}/max_iters.txt"
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/inc_iter_counter.sh"
}

teardown() {
  rm -rf "${TMPDIR}"
}

@test "iter 1 -> 2 emits iter-next" {
  printf '1' > "${RUN_DIR}/iter.txt"
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${lines[0]}" = "iter-next" ]
  [ "$(cat "${RUN_DIR}/iter.txt")" = "2" ]
}

@test "iter 4 -> 5 emits iter-next" {
  printf '4' > "${RUN_DIR}/iter.txt"
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${lines[0]}" = "iter-next" ]
  [ "$(cat "${RUN_DIR}/iter.txt")" = "5" ]
}

@test "iter-next path embeds plan, feedback, iter, repo_conventions" {
  printf '1' > "${RUN_DIR}/iter.txt"
  printf '{"branch_name":"fix/x"}' > "${RUN_DIR}/plan.json"
  printf '[{"persona":"yagni","file":"a","line_range":"1","description":"x","recommendation":"y"}]' \
    > "${RUN_DIR}/feedback.json"
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${lines[0]}" = "iter-next" ]
  printf '%s\n' "${output}" | grep -q -- "<plan>"
  printf '%s\n' "${output}" | grep -q -- "fix/x"
  printf '%s\n' "${output}" | grep -q -- "<feedback>"
  printf '%s\n' "${output}" | grep -q -- "yagni"
  printf '%s\n' "${output}" | grep -q -- "<iter>"
  printf '%s\n' "${output}" | grep -q -- "<repo_conventions>"
}

@test "iter 5 -> 6 emits iter-exhausted and does not bump counter" {
  printf '5' > "${RUN_DIR}/iter.txt"
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "iter-exhausted" ]
  [ "$(cat "${RUN_DIR}/iter.txt")" = "5" ]
}

@test "missing iter.txt emits iter-exhausted" {
  rm -f "${RUN_DIR}/iter.txt"
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "iter-exhausted" ]
}

@test "missing rid sentinel emits iter-exhausted" {
  rm "${DIP_ROOT}/.current_rid"
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "iter-exhausted" ]
}
