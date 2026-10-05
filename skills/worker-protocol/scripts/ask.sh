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
    --wait)
      [ $# -ge 2 ] || { echo "--wait needs seconds" >&2; exit 2; }
      valid_count "$2" "--wait" || exit 2
      wait=$2
      shift 2
      ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done
valid_label "$label" || exit 2
paths "$dir" "$label"
mkdir -p "$dir/workers"
[ -f "$worker" ] || printf '# %s\n' "$label" > "$worker"

last=$(sed -n 's/^## Q\([0-9][0-9]*\)$/\1/p' "$worker" | sort -n | tail -n 1)
n=$(( ${last:-0} + 1 ))
# One write, so a watcher never sees half a question.
block=$(printf '\n## Q%s\n**Mode:** %s\n**Context:** %s\n**Question:** %s\n**Options:** %s\n**Default:** %s' \
  "$n" "$mode" "$(one_line "$context")" "$(one_line "$question")" "$(one_line "$options")" \
  "$(one_line "$default")")
printf '%s\n' "$block" >> "$worker"
echo "Q$n"

[ "$wait" -gt 0 ] || exit 0
elapsed=0
while ! answered "$answers" "$n"; do
  if [ "$elapsed" -ge "$wait" ]; then
    echo "no answer after ${wait}s: proceed with your default, or end BLOCKED" >&2
    exit 3
  fi
  sleep 1
  elapsed=$((elapsed + 1))
done
awk -v h="## A$n" '$0 == h { on = 1; print; next } on && /^## / { exit } on { print }' "$answers"
