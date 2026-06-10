#!/bin/sh
# test_marker_coverage.sh — assert every marker_grep regex in dev_loop.dip
# matches at least one literal listed in scripts/markers.txt, AND every literal
# in markers.txt is reachable from at least one marker_grep.
#
# Run from the repo root: ./dev_loop/tests/test_marker_coverage.sh
set -eu

DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIP="${DIR}/dev_loop.dip"
MARKERS="${DIR}/scripts/markers.txt"

if [ ! -f "${DIP}" ] || [ ! -f "${MARKERS}" ]; then
  echo "missing dev_loop.dip or scripts/markers.txt" >&2
  exit 2
fi

# Extract each marker_grep regex (the double-quoted body) from the .dip.
# Double-quoted is required by dippin-lang#114 — pack corrupts single-quoted
# scalars by embedding literal quotes into the packed .dipx value.
regexes=$(grep -oE 'marker_grep: "[^"]+"' "${DIP}" | sed 's/marker_grep: "//;s/"$//' | sort -u)

# Extract literal markers (skip comments / blanks).
literals=$(sed -e 's/#.*$//' "${MARKERS}" | grep -vE '^[[:space:]]*$' | sort -u)

rc=0

# Every regex must match at least one literal.
for re in ${regexes}; do
  if ! printf '%s\n' "${literals}" | grep -E "${re}" >/dev/null; then
    printf 'FAIL: marker_grep %s matches no literal in markers.txt\n' "${re}" >&2
    rc=1
  fi
done

# Every literal must be matchable by at least one regex.
for lit in ${literals}; do
  matched=0
  for re in ${regexes}; do
    if printf '%s\n' "${lit}" | grep -E "${re}" >/dev/null; then
      matched=1
      break
    fi
  done
  if [ "${matched}" -eq 0 ]; then
    printf 'FAIL: literal %s is not matched by any marker_grep\n' "${lit}" >&2
    rc=1
  fi
done

if [ "${rc}" -eq 0 ]; then
  printf 'OK: marker coverage clean (%d regexes, %d literals)\n' \
    "$(printf '%s\n' "${regexes}" | wc -l)" \
    "$(printf '%s\n' "${literals}" | wc -l)"
fi

exit "${rc}"
