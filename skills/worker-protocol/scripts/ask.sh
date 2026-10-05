#!/bin/sh
# Worker side: append an escalation to <dir>/workers/<label>.md and print its id (Q<n>).
# Usage: ask.sh <dir> <label> <context> <question> <options> <default> [--blocked] [--wait <seconds>]
# --blocked marks it BLOCKED (default CONTINUING). --wait polls <dir>/answers/<label>.md and prints
# the answer; use it only when your brief allows waiting. Exit 3 when the wait times out.
set -eu
# shellcheck source-path=SCRIPTDIR source=lib.sh
. "$(dirname "$0")/lib.sh"

[ $# -ge 6 ] || {
  echo "usage: ask.sh <dir> <label> <context> <question> <options> <default> [--blocked] [--wait <seconds>]" >&2
  exit 2
}
dir=$1 label=$2 context=$3 question=$4 options=$5 default=$6
shift 6
mode=CONTINUING wait=0
while [ $# -gt 0 ]; do
  case $1 in
    --blocked) mode=BLOCKED; shift ;;
    --wait) [ $# -ge 2 ] || { echo "--wait needs seconds" >&2; exit 2; }; wait=$2; shift 2 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done
valid_label "$label"
paths "$dir" "$label"
mkdir -p "$dir/workers"
[ -f "$worker" ] || printf '# %s\n\n## Decisions\n\n## Deferred\n' "$label" > "$worker"

last=$(sed -n 's/^## Q\([0-9][0-9]*\)$/\1/p' "$worker" | sort -n | tail -n 1)
n=$(( ${last:-0} + 1 ))
{
  printf '\n## Q%s\n' "$n"
  printf '**Mode:** %s\n' "$mode"
  printf '**Context:** %s\n' "$context"
  printf '**Question:** %s\n' "$question"
  printf '**Options:** %s\n' "$options"
  printf '**Default:** %s\n' "$default"
} >> "$worker"
echo "Q$n"

[ "$wait" -gt 0 ] || exit 0
elapsed=0
while ! answered "$answers" "$n"; do
  if [ "$elapsed" -ge "$wait" ]; then
    echo "no answer after ${wait}s: proceed with your default, or end BLOCKED" >&2
    exit 3
  fi
  sleep 5
  elapsed=$((elapsed + 5))
done
awk -v h="## A$n" '$0 == h { on = 1; print; next } on && /^## / { exit } on { print }' "$answers"
