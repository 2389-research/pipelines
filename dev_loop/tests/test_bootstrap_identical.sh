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
ref=$(cat tests/bootstrap.ref)
if [ -z "${ref}" ]; then
  printf 'tests/bootstrap.ref is empty or missing\n' >&2
  exit 1
fi

fail=0
for f in scripts/*.sh; do
  case ${f} in scripts/setup_run.sh) continue ;; esac
  # Extract the inlined block between the markers, then strip the marker lines
  # themselves so the comparison sees only the bootstrap body.
  block=$(awk '/^# ---begin-bootstrap-reference---$/,/^# ---end-bootstrap-reference---$/' "${f}" \
    | sed '1d;$d')
  if [ -z "${block}" ]; then
    printf 'bootstrap markers missing in %s\n' "${f}" >&2
    fail=1
    continue
  fi
  if [ "${block}" != "${ref}" ]; then
    printf 'bootstrap drift in %s\n' "${f}" >&2
    fail=1
  fi
done
exit ${fail}
