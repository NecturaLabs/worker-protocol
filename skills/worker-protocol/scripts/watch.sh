#!/bin/sh
# Manager side: print one line per new event in a protocol run, until killed.
# Usage: watch.sh <dir> [--replay]
# Events:
#   ESCALATION <label> Q<n> <mode>   an unanswered question
#   RESULT <label> <status>          a worker wrote a Result block (each block and status once)
# Each event is printed once per run, across restarts: the watcher records what it printed in
# <dir>/.watch-seen. --replay forgets that record and prints every current event again.
# Uses inotifywait or fswatch when installed, otherwise polls every 5 seconds;
# WORKER_PROTOCOL_WATCHER=inotifywait|fswatch|poll forces one. Exits 1 if its event source dies.
set -u
# shellcheck source-path=SCRIPTDIR source=lib.sh
. "$(dirname "$0")/lib.sh"

usage() { echo "usage: watch.sh <dir> [--replay]" >&2; exit 2; }
[ $# -ge 1 ] && [ $# -le 2 ] || usage
dir=$1
[ -d "$dir/workers" ] || { echo "not a protocol run (no workers/): $dir" >&2; exit 1; }
seen="$dir/.watch-seen"
if [ $# -eq 2 ]; then
  [ "$2" = --replay ] || usage
  : > "$seen"
fi
touch "$seen"

emit() { # key, line
  if ! grep -qxF "$1" "$seen"; then
    printf '%s\n' "$1" >> "$seen"
    printf '%s\n' "$2"
  fi
}

scan_file() { # worker file
  label=$(basename "$1" .md)
  i=0
  scan_worker "$1" | while read -r kind a b; do
    case $kind in
      Q) answered "$dir/answers/$label.md" "$a" || emit "Q $label $a" "ESCALATION $label Q$a $b" ;;
      R) i=$((i + 1)); emit "R $label $i $a" "RESULT $label $a" ;;
    esac
  done
}

scan_all() {
  for f in "$dir"/workers/*.md; do
    [ -f "$f" ] && scan_file "$f"
  done
}

backend=${WORKER_PROTOCOL_WATCHER:-}
if [ -z "$backend" ]; then
  if command -v inotifywait >/dev/null 2>&1; then backend=inotifywait
  elif command -v fswatch >/dev/null 2>&1; then backend=fswatch
  else backend=poll
  fi
fi

# Runs the event source in the background and reports on the feed when it ends; a TERM stops the
# source with it, so the watcher never leaves a child behind.
source_run() { # command...
  "$@" &
  src=$!
  trap 'kill "$src" 2>/dev/null; exit 0' INT TERM HUP
  wait "$src"
  echo "__watch-source-ended__ $?"
}

feed="$dir/.watch-feed-$$"
ready="$dir/.watch-ready-$$"
probe="$dir/workers/.watch-probe-$$"
mkfifo "$feed"
# Held open for reading and writing, so the feed never reports end-of-file between writers.
exec 3<> "$feed"
rm -f "$feed"
child=
prober=
trap 'kill $child $prober 2>/dev/null; rm -f "$ready" "$probe"' EXIT
trap 'exit 0' INT TERM HUP

# The source starts listening before the first full scan, so a write between the two is never
# missed. inotifywait announces "Watches established."; fswatch announces nothing, so a probe file
# is touched until fswatch reports an event, and that first event triggers the scan.
case $backend in
  inotifywait)
    (source_run inotifywait -m -r -e close_write,moved_to,create --format '%w%f' "$dir/workers") >&3 2>&1 &
    child=$!
    # If this inotifywait words its readiness differently, start anyway after 5 seconds.
    (sleep 5; echo __watch-fallback__) >&3 &
    prober=$!
    ;;
  fswatch)
    (source_run fswatch -o "$dir/workers") >&3 2>&1 &
    child=$!
    (until [ -e "$ready" ]; do touch "$probe"; sleep 1; done; rm -f "$probe") &
    prober=$!
    ;;
  poll)
    (while :; do echo poll; sleep 5; done) >&3 &
    child=$!
    ;;
  *) echo "unknown WORKER_PROTOCOL_WATCHER: $backend" >&2; exit 2 ;;
esac

listening=
while IFS= read -r line <&3; do
  case $line in
    __watch-source-ended__*)
      echo "watch.sh: $backend stopped (exit ${line#__watch-source-ended__ }); no events will be reported" >&2
      exit 1
      ;;
    "$dir"/workers/*.md) [ -n "$listening" ] && [ -f "$line" ] && scan_file "$line" ;;
    "$dir"/workers/*) ;;
    "Setting up watches."*) ;;
    "Watches established."*) listening=1; scan_all ;;
    __watch-fallback__) [ -n "$listening" ] || { listening=1; scan_all; } ;;
    poll) scan_all ;;
    "" | *[!0-9]*) printf 'watch.sh: %s\n' "$line" >&2 ;;
    *)
      # fswatch -o prints a count of changes per batch.
      [ -n "$listening" ] || { listening=1; touch "$ready"; }
      scan_all
      ;;
  esac
done
