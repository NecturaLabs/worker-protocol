#!/bin/sh
# Create a new protocol run directory, resume an existing one, or close it.
# Usage: init.sh <dir> --task "<one-line task>"   new run; refuses a non-empty directory
#        init.sh <dir> --resume                   resume an ACTIVE run; prints RUN.md
#        init.sh <dir> --close [--force]          mark the run CLOSED; refuses while a question or a
#                                                 ledger line is open, unless --force
# A new run prints its run id on the last line; put it in every worker's brief.
set -eu

usage() { echo 'usage: init.sh <dir> --task "<task>" | init.sh <dir> --resume | init.sh <dir> --close [--force]' >&2; exit 2; }
[ $# -ge 2 ] || usage
dir=$1
shift
templates="$(cd "$(dirname "$0")/../templates" && pwd)"
scripts="$(cd "$(dirname "$0")" && pwd)"

status_of() { sed -n 's/^- \*\*Status:\*\* //p' "$dir/RUN.md"; }

case $1 in
  --resume | --close)
    [ $# -eq 1 ] || { [ "$1" = --close ] && [ $# -eq 2 ] && [ "$2" = --force ]; } || usage
    [ -f "$dir/RUN.md" ] || { echo "no run in $dir (RUN.md missing)" >&2; exit 1; }
    if [ "$1" = --close ]; then
      if [ $# -eq 1 ]; then
        [ -d "$dir/workers" ] || { echo "not a protocol run (no workers/): $dir" >&2; exit 1; }
        hs=0
        sh "$scripts/harvest.sh" "$dir" > /dev/null 2>&1 || hs=$?
        if [ "$hs" -eq 1 ]; then
          echo "$dir has open questions (see harvest.sh); answer them, or use --close --force" >&2
          exit 1
        elif [ "$hs" -ne 0 ]; then
          echo "harvest.sh failed on $dir (exit $hs); run it to see why" >&2
          exit 1
        fi
        if grep -q '^- \[ \]' "$dir/ledger.md" 2>/dev/null; then
          echo "$dir/ledger.md has open lines; close them, or use --close --force" >&2
          exit 1
        fi
      fi
      sed 's/^- \*\*Status:\*\* .*/- **Status:** CLOSED/' "$dir/RUN.md" > "$dir/RUN.md.tmp"
      mv "$dir/RUN.md.tmp" "$dir/RUN.md"
      echo "closed $dir"
      exit 0
    fi
    if [ "$(status_of)" != ACTIVE ]; then
      echo "the run in $dir is $(status_of): start a new run in a new directory" >&2
      exit 1
    fi
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
  printf '# Run\n\n'
  printf -- '- **Run id:** %s\n' "$id"
  printf -- '- **Created:** %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf -- '- **Task:** %s\n' "$task"
  printf -- '- **Manager:** %s\n' "${WORKER_PROTOCOL_MANAGER:-unspecified}"
  printf -- '- **Protocol:** 2\n'
  printf -- '- **Scripts:** %s\n' "$scripts"
  printf -- '- **Status:** ACTIVE\n'
} > "$dir/RUN.md"
echo "created $dir (PROTOCOL.md, ledger.md, RUN.md, workers/, contracts/, answers/)"
echo "Next: edit section 1 of PROTOCOL.md, brief workers with templates/brief-snippet.md,"
echo "and run watch.sh $dir as a background monitor."
echo "$id"
