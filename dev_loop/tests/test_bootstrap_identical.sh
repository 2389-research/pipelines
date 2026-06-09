#!/bin/sh
# test_bootstrap_identical.sh — assert every downstream script's bootstrap
# preamble is byte-identical to the canonical reference. Prevents the 22
# inline copies from drifting silently (the cost of POSIX sh + tracker's
# `sh -c "$(cat ...)"` invocation forecloses sharing via `lib/bootstrap.sh`).
#
# Reference block lives in tests/bootstrap.ref (no markers; the file IS the
# reference). Each downstream script inlines the same content between
# `# ---begin-bootstrap-reference---` and `# ---end-bootstrap-reference---`
# markers. setup_run.sh is the config resolver, not a consumer, and is
# excluded from the check.
set -eu

cd "$(dirname "$0")/.."
if [ ! -s tests/bootstrap.ref ]; then
  printf 'tests/bootstrap.ref is empty or missing\n' >&2
  exit 1
fi

# Use `cmp` against the reference file for TRUE byte-identity. Command
# substitution (the previous mechanism) strips trailing newlines and would
# silently tolerate drift in line endings — exactly the class of bug this
# gate is meant to prevent.
tmp=$(mktemp)
trap 'rm -f "${tmp}"' EXIT INT TERM

fail=0
for f in scripts/*.sh; do
  case ${f} in scripts/setup_run.sh) continue ;; esac
  # Extract the inlined block between the markers, stripping the marker lines
  # themselves so the comparison sees only the bootstrap body.
  awk '/^# ---begin-bootstrap-reference---$/,/^# ---end-bootstrap-reference---$/' "${f}" \
    | sed '1d;$d' > "${tmp}"
  if [ ! -s "${tmp}" ]; then
    printf 'bootstrap markers missing (or empty body) in %s\n' "${f}" >&2
    fail=1
    continue
  fi
  if ! cmp -s tests/bootstrap.ref "${tmp}"; then
    printf 'bootstrap drift in %s (cmp: differs from tests/bootstrap.ref)\n' "${f}" >&2
    fail=1
  fi
done
exit ${fail}
