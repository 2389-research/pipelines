#!/usr/bin/env bats
# test_load_conventions.bats — Block 4: conventions cascade.
#
# Precedence:
#   1. ${DEV_LOOP_CONVENTIONS_FILE} env
#   2. ./.dev_loop/conventions.md
#   3. ./AGENTS.md
#   4. ./CLAUDE.md
#   5. ./CONVENTIONS.md
#   6. dev_loop/config/repo_conventions.md (shipped)
#   7. empty stub

setup() {
  load 'test_helpers'
  setup_env
  HELPER="${BATS_TEST_DIRNAME}/../scripts/lib/load_conventions.sh"
}

teardown() { rm -rf "${TMPDIR}"; }

@test "env DEV_LOOP_CONVENTIONS_FILE wins over all" {
  override="${TMPDIR}/over.md"
  printf 'ENV CONVENTIONS\n' > "${override}"
  mkdir -p "${WORKDIR}/.dev_loop"
  printf 'OPERATOR\n' > "${WORKDIR}/.dev_loop/conventions.md"
  printf 'AGENTS\n' > "${WORKDIR}/AGENTS.md"
  DEV_LOOP_CONVENTIONS_FILE="${override}" \
    out=$(. "${HELPER}" && load_conventions; printf '%s' "${CONVENTIONS_TEXT}")
  echo "${out}" | grep -q "ENV CONVENTIONS"
}

@test "operator .dev_loop/conventions.md wins over AGENTS.md / CLAUDE.md" {
  mkdir -p "${WORKDIR}/.dev_loop"
  printf 'OPERATOR\n' > "${WORKDIR}/.dev_loop/conventions.md"
  printf 'AGENTS\n' > "${WORKDIR}/AGENTS.md"
  printf 'CLAUDE\n' > "${WORKDIR}/CLAUDE.md"
  unset DEV_LOOP_CONVENTIONS_FILE
  out=$(. "${HELPER}" && load_conventions; printf '%s' "${CONVENTIONS_TEXT}")
  echo "${out}" | grep -q "OPERATOR"
}

@test "AGENTS.md wins over CLAUDE.md / CONVENTIONS.md" {
  printf 'AGENTS\n' > "${WORKDIR}/AGENTS.md"
  printf 'CLAUDE\n' > "${WORKDIR}/CLAUDE.md"
  printf 'CONV\n' > "${WORKDIR}/CONVENTIONS.md"
  unset DEV_LOOP_CONVENTIONS_FILE
  out=$(. "${HELPER}" && load_conventions; printf '%s' "${CONVENTIONS_TEXT}")
  echo "${out}" | grep -q "AGENTS"
}

@test "CLAUDE.md wins over CONVENTIONS.md when AGENTS.md absent" {
  printf 'CLAUDE\n' > "${WORKDIR}/CLAUDE.md"
  printf 'CONV\n' > "${WORKDIR}/CONVENTIONS.md"
  unset DEV_LOOP_CONVENTIONS_FILE
  out=$(. "${HELPER}" && load_conventions; printf '%s' "${CONVENTIONS_TEXT}")
  echo "${out}" | grep -q "CLAUDE"
}

@test "CONVENTIONS.md wins over shipped when nothing else present" {
  printf 'CONV\n' > "${WORKDIR}/CONVENTIONS.md"
  mkdir -p "${WORKDIR}/dev_loop/config"
  printf 'SHIPPED\n' > "${WORKDIR}/dev_loop/config/repo_conventions.md"
  unset DEV_LOOP_CONVENTIONS_FILE
  out=$(. "${HELPER}" && load_conventions; printf '%s' "${CONVENTIONS_TEXT}")
  echo "${out}" | grep -q "CONV"
}

@test "shipped dev_loop/config/repo_conventions.md wins when nothing else" {
  mkdir -p "${WORKDIR}/dev_loop/config"
  printf 'SHIPPED\n' > "${WORKDIR}/dev_loop/config/repo_conventions.md"
  unset DEV_LOOP_CONVENTIONS_FILE
  out=$(. "${HELPER}" && load_conventions; printf '%s' "${CONVENTIONS_TEXT}")
  echo "${out}" | grep -q "SHIPPED"
}

@test "subdirectory cwd: resolves cascade against repo top-level" {
  # AGENTS.md sits at the repo root, but the caller runs from a subdir.
  # The cascade must still find it (via git rev-parse --show-toplevel).
  printf 'AGENTS\n' > "${WORKDIR}/AGENTS.md"
  mkdir -p "${WORKDIR}/sub/deeper"
  unset DEV_LOOP_CONVENTIONS_FILE
  ( cd "${WORKDIR}/sub/deeper" \
    && . "${HELPER}" \
    && load_conventions \
    && printf '%s' "${CONVENTIONS_TEXT}" ) | grep -q "AGENTS"
}

@test "DEV_LOOP_REPO_ROOT override: resolves cascade against the override" {
  # When DEV_LOOP_REPO_ROOT is published by setup_run, callers can run
  # from anywhere and the cascade still anchors on the real repo root.
  printf 'AGENTS\n' > "${WORKDIR}/AGENTS.md"
  unset DEV_LOOP_CONVENTIONS_FILE
  out=$( cd / \
         && export DEV_LOOP_REPO_ROOT="${WORKDIR}" \
         && . "${HELPER}" \
         && load_conventions \
         && printf '%s' "${CONVENTIONS_TEXT}" )
  echo "${out}" | grep -q "AGENTS"
}

@test "unreadable cascade entry: falls through to next, never aborts" {
  # AGENTS.md is chmod 000; cascade must skip it and land on CLAUDE.md
  # rather than exiting non-zero under a `set -e` caller.
  printf 'AGENTS\n' > "${WORKDIR}/AGENTS.md"
  chmod 000 "${WORKDIR}/AGENTS.md"
  printf 'CLAUDE\n' > "${WORKDIR}/CLAUDE.md"
  unset DEV_LOOP_CONVENTIONS_FILE
  # Run under `set -e` to assert the cascade does not abort on the
  # unreadable file.
  out=$( set -e
         . "${HELPER}"
         load_conventions
         printf '%s' "${CONVENTIONS_TEXT}" )
  echo "${out}" | grep -q "CLAUDE"
  # Restore for teardown.
  chmod 644 "${WORKDIR}/AGENTS.md"
}

@test "nothing present: empty stub" {
  unset DEV_LOOP_CONVENTIONS_FILE
  out=$(. "${HELPER}" && load_conventions; printf '%s' "${CONVENTIONS_TEXT}")
  # Empty stub indicates "no conventions found" — must not error, must not
  # be the literal placeholder text from the old inline duplication
  # (`(no repo_conventions.md found)`).
  [ -n "${out}" ]
  echo "${out}" | grep -qi "no conventions"
}
