#!/bin/sh
# Manager side: print one line per new open escalation in <dir>/*.md, until killed.
# Usage: watch.sh <dir>
# Output: "ESCALATION <file>:<heading>". Questions already open when it starts are printed once.
# Uses inotifywait or fswatch when installed, otherwise polls every 5 seconds.
set -u

[ $# -eq 1 ] || { echo "usage: watch.sh <dir>" >&2; exit 2; }
dir=$1
[ -d "$dir" ] || { echo "no such directory: $dir" >&2; exit 1; }
seen="$dir/.watch-seen"
: > "$seen"

scan() {
  for f in "$dir"/*.md; do
    [ -f "$f" ] || continue
    grep -H '^## Q[0-9][0-9]* · [a-z0-9-]* · OPEN$' "$f" 2>/dev/null || true
  done | while IFS= read -r line; do
    if ! grep -qxF "$line" "$seen"; then
      printf '%s\n' "$line" >> "$seen"
      printf 'ESCALATION %s\n' "$line"
    fi
  done
}

scan
if command -v inotifywait >/dev/null 2>&1; then
  inotifywait -m -q -e close_write,moved_to,create --format '%f' "$dir" | while IFS= read -r _; do scan; done
elif command -v fswatch >/dev/null 2>&1; then
  fswatch -o "$dir" | while IFS= read -r _; do scan; done
else
  while :; do sleep 5; scan; done
fi
