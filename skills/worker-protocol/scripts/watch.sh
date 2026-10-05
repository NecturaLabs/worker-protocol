#!/bin/sh
# Manager side: print one line per new event in a protocol run, until killed.
# Usage: watch.sh <dir>
# Events:
#   ESCALATION <label> Q<n> <mode>   an unanswered question (printed once)
#   RESULT <label> <status>          a worker wrote or changed its Result status
# Uses inotifywait or fswatch when installed, otherwise polls every 5 seconds.
set -u
# shellcheck source-path=SCRIPTDIR source=lib.sh
. "$(dirname "$0")/lib.sh"

[ $# -eq 1 ] || { echo "usage: watch.sh <dir>" >&2; exit 2; }
dir=$1
[ -d "$dir/workers" ] || { echo "not a protocol run (no workers/): $dir" >&2; exit 1; }
seen="$dir/.watch-seen"
: > "$seen"

emit() { # key, line
  if ! grep -qxF "$1" "$seen"; then
    printf '%s\n' "$1" >> "$seen"
    printf '%s\n' "$2"
  fi
}

scan() {
  for f in "$dir"/workers/*.md; do
    [ -f "$f" ] || continue
    label=$(basename "$f" .md)
    scan_worker "$f" | while read -r kind a b; do
      case $kind in
        Q) answered "$dir/answers/$label.md" "$a" || emit "Q $label $a" "ESCALATION $label Q$a $b" ;;
        R) emit "R $label $a $b" "RESULT $label $a${b:+ $b}" ;;
      esac
    done
  done
}

scan
if command -v inotifywait >/dev/null 2>&1; then
  inotifywait -m -r -q -e close_write,moved_to,create --format '%w%f' "$dir/workers" |
    while IFS= read -r _; do scan; done
elif command -v fswatch >/dev/null 2>&1; then
  fswatch -o "$dir/workers" | while IFS= read -r _; do scan; done
else
  while :; do sleep 5; scan; done
fi
