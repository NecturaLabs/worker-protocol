#!/bin/sh
# Manager side: answer a worker's question, or add a binding override, in <dir>/answers/<label>.md.
# Usage: answer.sh <dir> <label> <n> <answer>
#        answer.sh <dir> <label> --override <text>
# Only appends to the manager-owned answers file; never rewrites a worker's file.
set -eu
# shellcheck source-path=SCRIPTDIR source=lib.sh
. "$(dirname "$0")/lib.sh"

usage() { echo "usage: answer.sh <dir> <label> <n> <answer> | answer.sh <dir> <label> --override <text>" >&2; exit 2; }
[ $# -eq 4 ] || usage
dir=$1 label=$2
valid_label "$label"
paths "$dir" "$label"
mkdir -p "$dir/answers"

if [ "$3" = "--override" ]; then
  k=$(( $( { grep -c '^## Override O[0-9][0-9]*$' "$answers" 2>/dev/null || true; } ) + 1 ))
  printf '\n## Override O%s\n%s\n' "$k" "$4" >> "$answers"
  echo "override O$k for $label"
  exit 0
fi

n=$3
case $n in "" | *[!0-9]*) usage ;; esac
if [ ! -f "$worker" ] || ! grep -qx "## Q$n" "$worker"; then
  echo "$label has no question Q$n" >&2
  exit 1
fi
if answered "$answers" "$n"; then
  echo "Q$n of $label is already answered" >&2
  exit 1
fi
printf '\n## A%s\n%s\n' "$n" "$4" >> "$answers"
echo "answered Q$n for $label"
