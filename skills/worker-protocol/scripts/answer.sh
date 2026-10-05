#!/bin/sh
# Manager side: answer escalation Q<n> in <dir>/<label>.md in place.
# Usage: answer.sh <dir> <label> <n> <answer>
# Flips the heading from OPEN to ANSWERED and adds "**A:** <answer>" as the question's last line.
set -eu

[ $# -eq 4 ] || { echo "usage: answer.sh <dir> <label> <n> <answer>" >&2; exit 2; }
dir=$1 label=$2 n=$3 answer=$4
file="$dir/$label.md"
open="## Q$n · $label · OPEN"

[ -f "$file" ] || { echo "no such file: $file" >&2; exit 1; }
grep -qxF "$open" "$file" || { echo "no open question Q$n in $file" >&2; exit 1; }

tmp="$file.tmp.$$"
ANSWER=$answer awk -v open="$open" -v done="## Q$n · $label · ANSWERED" '
  function flush() { print "**A:** " ENVIRON["ANSWER"]; on = 0 }
  function blanks_out() { while (blanks > 0) { print ""; blanks-- } }
  $0 == open { print done; on = 1; next }
  on && /^[ \t]*$/ { blanks++; next }
  on && /^## / { flush(); blanks_out(); print; next }
  on { blanks_out(); print; next }
  { print }
  END { if (on) { flush(); blanks_out() } }
' "$file" > "$tmp"
mv "$tmp" "$file"
echo "answered Q$n in $file"
