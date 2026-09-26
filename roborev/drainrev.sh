#!/bin/sh
# ABOUTME: Drains a repository's open roborev reviews through roborev_issue_fixer.dip.
# ABOUTME: Runs tracker on the repository root with no token cap; extra arguments go to tracker.
set -eu

case ${1:-} in
  -h|--help)
    cat <<EOF
usage: $0 [repo] [tracker flags...]

Fixes and closes open roborev reviews on the current branch of repo (default:
the current directory) with roborev_issue_fixer.dip, up to max_reviews
(default 30) per run; run again to continue, and the final summary's REVIEW
CAP block says whether more remain. Flags after repo go to tracker and win
over the defaults, for example --no-tui, or
--param review_id=42 --param drain_queue=false to fix one review, or
--param max_reviews=10 to change the per-run cap.
EOF
    exit 0
    ;;
esac

repo=.
case ${1:-} in
  '' | -*) ;;
  *)
    repo=$1
    shift
    ;;
esac

# Resolve through a symlink so a copy linked onto PATH still finds its pipeline.
roborev_dir=$(CDPATH='' cd -- "$(dirname "$(readlink -f "$0")")" && pwd -P)
root=$(git -C "$repo" rev-parse --show-toplevel) || exit 1
exec tracker -w "$root" "$roborev_dir/roborev_issue_fixer.dip" --param drain_queue=true "$@"
