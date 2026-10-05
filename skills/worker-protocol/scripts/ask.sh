#!/bin/sh
# Worker side: append an escalation to <dir>/<label>.md and print its heading.
# Usage: ask.sh <dir> <label> <context> <question> <options> <default> [--wait [seconds]]
# With --wait, block until the manager answers (default 1200 s), then print the answer block.
# Exit 0 when answered or not waiting, 3 when the wait timed out.
set -eu

[ $# -ge 6 ] || {
  echo "usage: ask.sh <dir> <label> <context> <question> <options> <default> [--wait [seconds]]" >&2
  exit 2
}
dir=$1 label=$2 context=$3 question=$4 options=$5 default=$6
shift 6
wait=0 limit=1200
if [ $# -gt 0 ] && [ "$1" = "--wait" ]; then
  wait=1
  [ $# -gt 1 ] && limit=$2
fi
case $label in
  *[!a-z0-9-]* | "") echo "label must match [a-z0-9-]+" >&2; exit 2 ;;
esac

file="$dir/$label.md"
[ -f "$file" ] || printf '# %s\n\n## Decisions\n\n## Deferred\n' "$label" > "$file"

last=$(grep -o "^## Q[0-9]* · $label · " "$file" | sed 's/^## Q\([0-9]*\).*/\1/' | sort -n | tail -n 1)
n=$(( ${last:-0} + 1 ))
heading="## Q$n · $label · OPEN"
{
  printf '\n%s\n' "$heading"
  printf '**Context:** %s\n' "$context"
  printf '**Question:** %s\n' "$question"
  printf '**Options:** %s\n' "$options"
  printf '**Default:** %s\n' "$default"
} >> "$file"
echo "$heading"

[ $wait -eq 1 ] || exit 0
answered="^## Q$n · $label · ANSWERED"
elapsed=0
while ! grep -q "$answered" "$file"; do
  if [ $elapsed -ge "$limit" ]; then
    echo "no answer after ${limit}s: proceed with your default and say so" >&2
    exit 3
  fi
  sleep 10
  elapsed=$((elapsed + 10))
done
awk -v h="## Q$n · $label · ANSWERED" '
  $0 == h { on = 1; print; next }
  on && /^## / { exit }
  on { print }
' "$file"
