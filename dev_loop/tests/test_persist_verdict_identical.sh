#!/bin/sh
# test_persist_verdict_identical.sh — assert every persist_*_verdict.sh carries
# a byte-identical persist body, modulo the per-squad `squad`/`squad_node`
# declarations. The five scripts are intentional inline copies: tracker inlines
# each `command_file:` body into the .dipx bundle, which does NOT ship
# scripts/lib/, so the shared logic cannot be sourced at runtime. This gate
# (mirroring test_bootstrap_identical.sh) keeps the copies from drifting
# silently — issue #107.
#
# Reference block lives in tests/persist_verdict.ref (no markers; the file IS
# the reference, with the two decl lines blanked to `squad=` / `squad_node=`).
# Each script inlines the same content between
# `# ---begin-persist-verdict-reference---` and
# `# ---end-persist-verdict-reference---` markers.
set -eu

cd "$(dirname "$0")/.."
if [ ! -s tests/persist_verdict.ref ]; then
  printf 'tests/persist_verdict.ref is empty or missing\n' >&2
  exit 1
fi

tmp=$(mktemp)
trap 'rm -f "${tmp}"' EXIT INT TERM

# Resolve the glob into positional params and fail loud if it matched nothing
# (scripts renamed/moved under a new scheme). A bare `for f in glob` would
# otherwise iterate once over the literal pattern and the cmp would error per
# file — but an empty match must be an explicit FAIL, not a silent pass, so the
# gate can't be defeated by deleting the scripts. Mirrors the glob guard in
# test_persist_neutral_breadcrumb.sh.
set -- scripts/persist_*verdict*.sh
if [ "$#" -eq 0 ] || [ ! -e "$1" ]; then
  printf 'no persist_*verdict*.sh scripts found (glob did not match)\n' >&2
  exit 1
fi

fail=0
for f in "$@"; do
  # Extract the inlined block between the markers, strip the marker lines, and
  # blank the two per-squad decl lines so the comparison sees only the shared
  # body. The blanking is anchored to the exact decl form (`squad='...'`) so a
  # stray `squad=...` elsewhere in the body would not be masked.
  awk '/^# ---begin-persist-verdict-reference---$/,/^# ---end-persist-verdict-reference---$/' "${f}" \
    | sed '1d;$d' \
    | sed -E "s/^squad='[a-z0-9_]+'\$/squad=/; s/^squad_node='[A-Za-z0-9_]+'\$/squad_node=/" \
    > "${tmp}"
  if [ ! -s "${tmp}" ]; then
    printf 'persist-verdict markers missing (or empty body) in %s\n' "${f}" >&2
    fail=1
    continue
  fi
  if ! cmp -s tests/persist_verdict.ref "${tmp}"; then
    printf 'persist-verdict drift in %s (cmp: differs from tests/persist_verdict.ref)\n' "${f}" >&2
    fail=1
  fi
done
exit ${fail}
