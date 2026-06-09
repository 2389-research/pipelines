#!/usr/bin/env bats
# test_local_gates.bats — covers gates-pass / gates-fail with a real worktree.

setup() {
  load 'test_helpers'
  setup_env
  stage_run

  REPO="${TMPDIR}/repo"
  mkdir -p "${REPO}"
  cd "${REPO}"
  git init -q -b main
  git config user.email "test@example.com"
  git config user.name "Test"
  echo seed > README.md && git add README.md && git commit -q -m seed

  printf '%s' "${REPO}" > "${RUN_DIR}/worktree.path"

  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/local_gates.sh"
}

teardown() {
  rm -rf "${TMPDIR}"
}

@test "no changed .dips means gates-pass" {
  run sh -c "$(cat "${SCRIPT}")"
  [ "${output}" = "gates-pass" ]
}

@test "valid added .dip on feature branch lets gates pass" {
  git -C "${REPO}" checkout -q -b feature
  cat > "${REPO}/clean.dip" <<'EOF'
workflow test
  goal: "trivial"
  start: A
  exit: A
  agent A
    label: A
    max_turns: 1
    tool_access: none
EOF
  git -C "${REPO}" add clean.dip
  git -C "${REPO}" commit -q -m "add clean dip"

  run sh -c "$(cat "${SCRIPT}")"
  [ "${output}" = "gates-pass" ]
}

@test "broken .dip on feature branch routes to gates-fail" {
  git -C "${REPO}" checkout -q -b feature
  cat > "${REPO}/broken.dip" <<'EOF'
workflow broken
  goal: "missing exit"
  start: A
  agent A
    prompt: hi
EOF
  git -C "${REPO}" add broken.dip
  git -C "${REPO}" commit -q -m "broken"

  run sh -c "$(cat "${SCRIPT}")"
  [ "${output}" = "gates-fail" ]
  grep -q "dippin check failed" "${RUN_DIR}/gates_error.txt"
}

@test "missing worktree.path emits gates-fail" {
  rm "${RUN_DIR}/worktree.path"
  run sh -c "$(cat "${SCRIPT}")"
  [ "${output}" = "gates-fail" ]
}
