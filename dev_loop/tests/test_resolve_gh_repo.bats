#!/usr/bin/env bats
# test_resolve_gh_repo.bats — covers the 5 precedence sources and the 5
# URL forms the POSIX sed parser must recognize.
#
# The resolver is sourced (not invoked) by setup_run.sh; tests source it
# directly and call resolve_gh_repo with controlled inputs.

setup() {
  load 'test_helpers'
  setup_env
  RESOLVER="${BATS_TEST_DIRNAME}/../scripts/lib/resolve_gh_repo.sh"
  # The resolver expects to be sourced from a script that already exported
  # `emit_failure` for fail-closed paths. Stub it so failure paths can be
  # asserted without invoking the full setup_run trap machinery.
  emit_failure() { printf 'EMIT_FAILURE: %s\n' "$1"; exit 1; }
  export -f emit_failure 2>/dev/null || true
}

teardown() { rm -rf "${TMPDIR}"; }

# --- helpers --------------------------------------------------------------

stub_git_remote() {
  # Create a stub `git` that returns the given URL for `git remote get-url origin`.
  shim="${TMPDIR}/shim"
  mkdir -p "${shim}"
  cat > "${shim}/git" <<GIT
#!/bin/sh
if [ "\$1" = "remote" ] && [ "\$2" = "get-url" ] && [ "\$3" = "origin" ]; then
  printf '%s\n' "$1"
  exit 0
fi
exec /usr/bin/git "\$@"
GIT
  chmod +x "${shim}/git"
  PATH="${shim}:${PATH}"
  export PATH
}

stub_gh_repo_view() {
  shim="${TMPDIR}/shim"
  mkdir -p "${shim}"
  cat > "${shim}/gh" <<GH
#!/bin/sh
if [ "\$1" = "repo" ] && [ "\$2" = "view" ]; then
  printf '%s\n' "$1"
  exit 0
fi
exit 1
GH
  chmod +x "${shim}/gh"
  PATH="${shim}:${PATH}"
  export PATH
}

stub_git_remote_fail() {
  shim="${TMPDIR}/shim"
  mkdir -p "${shim}"
  cat > "${shim}/git" <<'GIT'
#!/bin/sh
if [ "$1" = "remote" ] && [ "$2" = "get-url" ] && [ "$3" = "origin" ]; then
  printf 'fatal: not a git repo\n' >&2
  exit 128
fi
exec /usr/bin/git "$@"
GIT
  chmod +x "${shim}/git"
  PATH="${shim}:${PATH}"
  export PATH
}

stub_gh_fail() {
  shim="${TMPDIR}/shim"
  mkdir -p "${shim}"
  cat > "${shim}/gh" <<'GH'
#!/bin/sh
exit 1
GH
  chmod +x "${shim}/gh"
  PATH="${shim}:${PATH}"
  export PATH
}

# --- precedence -----------------------------------------------------------

@test "precedence: env GH_REPO beats all other sources" {
  stub_git_remote "https://github.com/git-org/git-repo.git"
  . "${RESOLVER}"
  GH_REPO=env-org/env-repo
  resolve_gh_repo "yaml-org/yaml-repo"
  [ "${RESOLVED_GH_REPO}" = "env-org/env-repo" ]
  [ "${RESOLVED_GH_REPO_SOURCE}" = "env" ]
}

@test "precedence: YAML repo beats git remote + gh fallback when env unset" {
  unset GH_REPO
  stub_git_remote "https://github.com/git-org/git-repo.git"
  . "${RESOLVER}"
  resolve_gh_repo "yaml-org/yaml-repo"
  [ "${RESOLVED_GH_REPO}" = "yaml-org/yaml-repo" ]
  [ "${RESOLVED_GH_REPO_SOURCE}" = "yaml" ]
}

@test "precedence: git remote beats gh fallback when env + YAML unset" {
  unset GH_REPO
  stub_git_remote "https://github.com/git-org/git-repo.git"
  . "${RESOLVER}"
  resolve_gh_repo ""
  [ "${RESOLVED_GH_REPO}" = "git-org/git-repo" ]
  [ "${RESOLVED_GH_REPO_SOURCE}" = "git-remote" ]
}

@test "precedence: gh repo view fallback when env/YAML/remote all unavailable" {
  unset GH_REPO
  stub_git_remote_fail
  stub_gh_repo_view "gh-org/gh-repo"
  . "${RESOLVER}"
  resolve_gh_repo ""
  [ "${RESOLVED_GH_REPO}" = "gh-org/gh-repo" ]
  [ "${RESOLVED_GH_REPO_SOURCE}" = "gh-cli" ]
}

@test "precedence: all sources fail → emit_failure" {
  unset GH_REPO
  stub_git_remote_fail
  stub_gh_fail
  . "${RESOLVER}"
  run resolve_gh_repo ""
  [ "${status}" -ne 0 ]
  printf '%s\n' "${output}" | grep -q "EMIT_FAILURE"
}

# --- URL forms (POSIX sed parser) -----------------------------------------

@test "url form: HTTPS with .git suffix" {
  unset GH_REPO
  stub_git_remote "https://github.com/acme/widget.git"
  . "${RESOLVER}"
  resolve_gh_repo ""
  [ "${RESOLVED_GH_REPO}" = "acme/widget" ]
}

@test "url form: HTTPS without .git suffix" {
  unset GH_REPO
  stub_git_remote "https://github.com/acme/widget"
  . "${RESOLVER}"
  resolve_gh_repo ""
  [ "${RESOLVED_GH_REPO}" = "acme/widget" ]
}

@test "url form: SSH git@ syntax" {
  unset GH_REPO
  stub_git_remote "git@github.com:acme/widget.git"
  . "${RESOLVER}"
  resolve_gh_repo ""
  [ "${RESOLVED_GH_REPO}" = "acme/widget" ]
}

@test "url form: ssh:// URL" {
  unset GH_REPO
  stub_git_remote "ssh://git@github.com/acme/widget.git"
  . "${RESOLVER}"
  resolve_gh_repo ""
  [ "${RESOLVED_GH_REPO}" = "acme/widget" ]
}

@test "url form: GHE host variant (custom host)" {
  unset GH_REPO
  stub_git_remote "git@github.acme-corp.com:acme/widget.git"
  . "${RESOLVER}"
  resolve_gh_repo ""
  [ "${RESOLVED_GH_REPO}" = "acme/widget" ]
}
