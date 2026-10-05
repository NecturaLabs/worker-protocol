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
valid_label "$label" || exit 2
paths "$dir" "$label"
mkdir -p "$dir/answers"

override() { # text
  k=$(( $( { grep -c '^## Override O[0-9][0-9]*$' "$answers" 2>/dev/null || true; } ) + 1 ))
  printf '\n## Override O%s\n%s\n' "$k" "$(no_headings "$1")" >> "$answers" || return 1
  echo "override O$k for $label"
}

reply() { # n, text
  if answered "$answers" "$1"; then
    echo "Q$1 of $label is already answered" >&2
    return 1
  fi
  printf '\n## A%s\n%s\n' "$1" "$(no_headings "$2")" >> "$answers" || return 1
  echo "answered Q$1 for $label"
}

lock="$dir/answers/.$label.lock"
if [ "$3" = "--override" ]; then
  with_lock "$lock" override "$4"
  exit
fi

n=$3
valid_count "$n" "question number" || usage
if [ ! -f "$worker" ] || ! grep -qx "## Q$n" "$worker"; then
  echo "$label has no question Q$n" >&2
  exit 1
fi
with_lock "$lock" reply "$n" "$4"
