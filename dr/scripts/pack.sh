#!/bin/sh
# ABOUTME: Build deterministic .dipx bundles for the three top-level dr/ pipelines.
# ABOUTME: Output: dr/dist/<pipeline>.dipx (gitignored — reproducible from .dip sources).
#
# Usage:
#   dr/scripts/pack.sh           # pack all three
#   dr/scripts/pack.sh runner    # pack just sprint_runner (also bundles exec + spec_to_sprints subgraphs)
#   dr/scripts/pack.sh exec      # pack just sprint_exec (and its parts/recovery/* subgraphs)
#   dr/scripts/pack.sh spec      # pack just spec_to_sprints
set -eu

DR_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$DR_ROOT/dist"
mkdir -p "$DIST_DIR"

pack_one() {
  ENTRY="$1"
  OUT="$DIST_DIR/$(basename "$ENTRY" .dip).dipx"
  cd "$DR_ROOT"
  dippin pack --dry-run "$ENTRY" >/dev/null
  dippin pack -o "$OUT" "$ENTRY"
  IDENTITY=$(dippin inspect "$OUT" | awk '/^identity:/{print $2}')
  printf '  %-32s %s\n' "$(basename "$OUT")" "$IDENTITY"
}

WHICH="${1:-all}"
case "$WHICH" in
  all)
    echo "→ packing all three dr/ pipelines into $DIST_DIR/"
    pack_one sprint_runner.dip
    pack_one sprint_exec.dip
    pack_one spec_to_sprints.dip
    ;;
  runner) pack_one sprint_runner.dip ;;
  exec)   pack_one sprint_exec.dip ;;
  spec)   pack_one spec_to_sprints.dip ;;
  *)
    echo "unknown target: $WHICH (use: all|runner|exec|spec)" >&2
    exit 1
    ;;
esac
