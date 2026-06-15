#!/usr/bin/env bats
# test_init_iter_counter.bats

setup() {
  load 'test_helpers'
  setup_env
  stage_run
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/init_iter_counter.sh"
}

teardown() {
  rm -rf "${TMPDIR}"
}

@test "init writes iter=1 and max_iters" {
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${lines[0]}" = "iter-init-ok" ]
  [ "$(cat "${RUN_DIR}/iter.txt")" = "1" ]
  [ -f "${RUN_DIR}/max_iters.txt" ]
}

@test "init embeds plan, feedback, iter, repo_conventions for the Implementer" {
  printf '{"branch_name":"fix/test"}' > "${RUN_DIR}/plan.json"
  printf '[]' > "${RUN_DIR}/feedback.json"
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${lines[0]}" = "iter-init-ok" ]
  # All four blocks must appear so the Implementer's prompt contract holds.
  printf '%s\n' "${output}" | grep -q -- "<plan>"
  printf '%s\n' "${output}" | grep -q -- "fix/test"
  printf '%s\n' "${output}" | grep -q -- "<feedback>"
  printf '%s\n' "${output}" | grep -q -- "<iter>"
  printf '%s\n' "${output}" | grep -q -- "<repo_conventions>"
}

@test "packed mode (lib absent): inline cascade still loads AGENTS.md" {
  # Simulate the packed quickstart: AGENTS.md present at the repo root
  # but dev_loop/scripts/lib NOT on disk. The Implementer's
  # repo_conventions block must still contain the AGENTS.md text via
  # the inline fallback cascade.
  printf 'PACKED-AGENTS-MARKER\n' > "${WORKDIR}/AGENTS.md"
  DEV_LOOP_LIB_DIR="${WORKDIR}/no/such/lib"
  export DEV_LOOP_LIB_DIR
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${lines[0]}" = "iter-init-ok" ]
  printf '%s\n' "${output}" | grep -q "PACKED-AGENTS-MARKER"
}

@test "init without rid sentinel exits non-zero" {
  rm "${DIP_ROOT}/.current_rid"
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -ne 0 ]
}
