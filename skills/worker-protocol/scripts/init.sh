#!/bin/sh
# Create a new protocol run directory, or resume an existing one.
# Usage: init.sh <dir> --task "<one-line task>"   new run; refuses a non-empty directory
#        init.sh <dir> --resume                   resume; prints RUN.md
# A new run prints its run id on the last line; put it in every worker's brief.
set -eu

usage() { echo 'usage: init.sh <dir> --task "<task>" | init.sh <dir> --resume' >&2; exit 2; }
[ $# -ge 2 ] || usage
dir=$1
shift
templates="$(cd "$(dirname "$0")/../templates" && pwd)"

case $1 in
  --resume)
    [ $# -eq 1 ] || usage
    [ -f "$dir/RUN.md" ] || { echo "no run to resume in $dir (RUN.md missing)" >&2; exit 1; }
    mkdir -p "$dir/workers" "$dir/contracts" "$dir/answers"
    cat "$dir/RUN.md"
    exit 0
    ;;
  --task)
    [ $# -eq 2 ] || usage
    task=$(printf '%s' "$2" | tr '\n' ' ')
    ;;
  *) usage ;;
esac

if [ -d "$dir" ] && [ -n "$(ls -A "$dir" 2>/dev/null)" ]; then
  echo "$dir is not empty: use a new directory for a new run, or --resume this one" >&2
  exit 1
fi

mkdir -p "$dir/workers" "$dir/contracts" "$dir/answers"
cp "$templates/PROTOCOL.md" "$dir/PROTOCOL.md"
cp "$templates/ledger.md" "$dir/ledger.md"
id="run-$(date -u +%Y%m%dT%H%M%SZ)-$$"
{
  echo "# Run"
  echo
  echo "- **Run id:** $id"
  echo "- **Created:** $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "- **Task:** $task"
  echo "- **Manager:** ${WORKER_PROTOCOL_MANAGER:-unspecified}"
  echo "- **Protocol:** 2"
  echo "- **Status:** ACTIVE"
} > "$dir/RUN.md"
echo "created $dir (PROTOCOL.md, ledger.md, RUN.md, workers/, contracts/, answers/)"
echo "Next: edit section 1 of PROTOCOL.md, brief workers with templates/brief-snippet.md,"
echo "and run watch.sh $dir as a background monitor."
echo "$id"
