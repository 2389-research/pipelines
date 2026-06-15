#!/usr/bin/env bats
# test_yaml_config_cascade.bats — Block 3: YAML config discovery cascades
# through env > operator-curated > shipped default > skip.

setup() {
  load 'test_helpers'
  setup_env
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/setup_run.sh"
}

teardown() { rm -rf "${TMPDIR}"; }

@test "DEV_LOOP_CONFIG_PATH env override wins over operator + shipped" {
  # All three layers staged with distinct repos; env wins.
  override_dir="${TMPDIR}/over"
  mkdir -p "${override_dir}"
  cat > "${override_dir}/config.yaml" <<'YAML'
repo: env-org/env-repo
base_branch: main
YAML
  mkdir -p "${WORKDIR}/.dev_loop"
  cat > "${WORKDIR}/.dev_loop/config.yaml" <<'YAML'
repo: operator-org/operator-repo
base_branch: main
YAML
  mkdir -p "${WORKDIR}/dev_loop/config"
  cat > "${WORKDIR}/dev_loop/config/dev_loop.config.yaml" <<'YAML'
repo: shipped-org/shipped-repo
base_branch: main
YAML
  DEV_LOOP_CONFIG_PATH="${override_dir}/config.yaml" run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "setup-ok" ]
  rid="$(cat "${DIP_ROOT}/.current_rid")"
  grep -q "^GH_REPO='env-org/env-repo'$" "${DIP_ROOT}/runs/${rid}/env"
}

@test "operator .dev_loop/config.yaml wins over shipped default" {
  mkdir -p "${WORKDIR}/.dev_loop"
  cat > "${WORKDIR}/.dev_loop/config.yaml" <<'YAML'
repo: operator-org/operator-repo
base_branch: main
YAML
  mkdir -p "${WORKDIR}/dev_loop/config"
  cat > "${WORKDIR}/dev_loop/config/dev_loop.config.yaml" <<'YAML'
repo: shipped-org/shipped-repo
base_branch: main
YAML
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "setup-ok" ]
  rid="$(cat "${DIP_ROOT}/.current_rid")"
  grep -q "^GH_REPO='operator-org/operator-repo'$" "${DIP_ROOT}/runs/${rid}/env"
}

@test "shipped default used when env + operator unset" {
  mkdir -p "${WORKDIR}/dev_loop/config"
  cat > "${WORKDIR}/dev_loop/config/dev_loop.config.yaml" <<'YAML'
repo: shipped-org/shipped-repo
base_branch: main
YAML
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "setup-ok" ]
  rid="$(cat "${DIP_ROOT}/.current_rid")"
  grep -q "^GH_REPO='shipped-org/shipped-repo'$" "${DIP_ROOT}/runs/${rid}/env"
}

@test "no YAML at all: skip (env GH_REPO carries the run)" {
  # Block 1's resolver allows env > YAML > git-remote > gh-cli; with no YAML
  # we expect git-remote to win (workdir is git init in setup_env helper).
  # That origin doesn't exist, but env GH_REPO carries.
  GH_REPO=fallback-org/fallback-repo DEV_LOOP_BASE_BRANCH=main \
    run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "setup-ok" ]
  rid="$(cat "${DIP_ROOT}/.current_rid")"
  grep -q "^GH_REPO='fallback-org/fallback-repo'$" "${DIP_ROOT}/runs/${rid}/env"
}
