# resolve_gh_repo.sh — POSIX sh helper resolving GH_REPO from cwd.
#
# Sourced by setup_run.sh (NOT executed directly). Defines:
#   resolve_gh_repo YAML_REPO
# Sets RESOLVED_GH_REPO + RESOLVED_GH_REPO_SOURCE in the caller's scope.
#
# Precedence (first hit wins):
#   1. ${GH_REPO}                       source=env
#   2. YAML repo: field (arg 1)         source=yaml
#   3. git remote get-url origin        source=git-remote
#   4. gh repo view                     source=gh-cli
#   5. (none)                           emit_failure (caller's symbol)
#
# URL forms recognized in step 3 (POSIX sed):
#   https://github.com/owner/repo[.git]
#   http://github.com/owner/repo[.git]
#   git@github.com:owner/repo[.git]
#   ssh://git@github.com/owner/repo[.git]
#   git@github.example.com:owner/repo[.git]      (GHE host variant)

# Parse a single git remote URL into owner/repo. Echoes the result on success,
# echoes empty + returns non-zero on no-match.
_parse_remote_url() {
  url=$1
  # Strip trailing .git (POSIX sed).
  url=$(printf '%s' "${url}" | sed 's,\.git$,,')
  # Scheme URLs first: ssh://, https://, http://. These can include a port
  # (e.g. ssh://git@host:2222/org/repo) which would otherwise be misread as
  # an scp-style `host:path` if the *@*:* branch ran first.
  case ${url} in
    ssh://*|https://*|http://*)
      # Remove scheme, then remove host[:port] (everything up to and
      # including the first slash of the path).
      echo "${url}" | sed -e 's,^[a-z]*://,,' -e 's,^[^/]*/,,'
      return 0 ;;
  esac
  # SCP-style SSH form: git@host:owner/repo (no scheme).
  case ${url} in
    *@*:*)
      echo "${url}" | sed 's,^[^@]*@[^:]*:,,'
      return 0 ;;
  esac
  return 1
}

resolve_gh_repo() {
  yaml_repo=$1
  RESOLVED_GH_REPO=""
  RESOLVED_GH_REPO_SOURCE=""

  if [ -n "${GH_REPO:-}" ]; then
    RESOLVED_GH_REPO="${GH_REPO}"
    RESOLVED_GH_REPO_SOURCE="env"
    return 0
  fi
  if [ -n "${yaml_repo}" ]; then
    RESOLVED_GH_REPO="${yaml_repo}"
    RESOLVED_GH_REPO_SOURCE="yaml"
    return 0
  fi
  remote_url=$(git remote get-url origin 2>/dev/null || true)
  if [ -n "${remote_url}" ]; then
    parsed=$(_parse_remote_url "${remote_url}" 2>/dev/null || true)
    if [ -n "${parsed}" ]; then
      RESOLVED_GH_REPO="${parsed}"
      RESOLVED_GH_REPO_SOURCE="git-remote"
      return 0
    fi
  fi
  gh_out=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)
  if [ -n "${gh_out}" ]; then
    RESOLVED_GH_REPO="${gh_out}"
    RESOLVED_GH_REPO_SOURCE="gh-cli"
    return 0
  fi
  emit_failure "no repo configured (set GH_REPO env var, populate dev_loop.config.yaml with: repo: owner/name, or run from a git repo with a github.com origin)"
}
