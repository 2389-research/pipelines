#!/bin/sh
# ABOUTME: Run tracker against a .dipx bundle by unpacking to a temp dir first.
# ABOUTME: Workaround until tracker has native .dipx support (see docs/requests in tracker repo).
#
# Usage:
#   scripts/tracker-dipx.sh <bundle.dipx> [tracker-args...]
#
# Examples:
#   scripts/tracker-dipx.sh dist/sprint_runner_dr.dipx
#   scripts/tracker-dipx.sh dist/sprint_runner_dr.dipx --no-tui --auto-approve
set -eu

if [ $# -lt 1 ]; then
  echo "usage: $0 <bundle.dipx> [tracker-args...]" >&2
  exit 1
fi

BUNDLE="$1"; shift
if [ ! -f "$BUNDLE" ]; then
  echo "error: bundle not found: $BUNDLE" >&2
  exit 1
fi

# Resolve to absolute path before changing dirs (tracker is run from $PWD)
case "$BUNDLE" in
  /*) ;;
  *)  BUNDLE="$(cd "$(dirname "$BUNDLE")" && pwd)/$(basename "$BUNDLE")" ;;
esac

OUT=$(mktemp -d -t tracker-dipx-XXXXXX)
trap 'rm -rf "$OUT"' EXIT

dippin unpack --force -o "$OUT" "$BUNDLE" >/dev/null

ENTRY=$(dippin inspect "$BUNDLE" | awk '/^entry:/{print $2}')
if [ -z "$ENTRY" ]; then
  echo "error: could not determine entry from bundle manifest" >&2
  exit 1
fi

IDENTITY=$(dippin inspect "$BUNDLE" | awk '/^identity:/{print $2}')
echo "→ bundle identity: $IDENTITY" >&2
echo "→ entry:           $ENTRY" >&2
echo "→ unpacked to:     $OUT" >&2
echo >&2

exec tracker "$OUT/$ENTRY" "$@"
