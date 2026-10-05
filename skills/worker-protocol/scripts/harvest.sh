#!/bin/sh
# Manager side: summarise a protocol run at a checkpoint.
# Usage: harvest.sh <dir>
# Prints the run, open questions, each worker's result, decisions, deferred items, answers and
# overrides count, every contract, and the ledger's open lines. Exit 1 while a question is open.
set -eu
# shellcheck source-path=SCRIPTDIR source=lib.sh
. "$(dirname "$0")/lib.sh"

[ $# -eq 1 ] || { echo "usage: harvest.sh <dir>" >&2; exit 2; }
dir=$1
[ -d "$dir/workers" ] || { echo "not a protocol run (no workers/): $dir" >&2; exit 1; }
open=0

if [ -f "$dir/RUN.md" ]; then
  echo "== Run"
  grep '^- \*\*' "$dir/RUN.md" || echo "(RUN.md has no fields)"
  echo
fi

echo "== Open questions"
for f in "$dir"/workers/*.md; do
  [ -f "$f" ] || continue
  label=$(basename "$f" .md)
  for line in $(scan_worker "$f" all | awk '$1 == "Q" { print $2 ":" $3 }'); do
    n=${line%%:*}
    if ! answered "$dir/answers/$label.md" "$n"; then
      echo "$label Q$n (${line#*:})"
      open=$((open + 1))
    fi
  done
done
[ "$open" -gt 0 ] || echo "(none)"

for f in "$dir"/workers/*.md; do
  [ -f "$f" ] || continue
  label=$(basename "$f" .md)
  echo
  echo "== $label"
  status=$(scan_worker "$f" all | awk '$1 == "R" { $1 = ""; sub(/^ /, ""); s = $0 } END { print s }')
  echo "-- result: ${status:-(none yet)}"
  [ -z "$(tail -c 1 "$f")" ] || echo "-- warning: the last line has no newline; the watcher ignores it until it ends"
  echo "-- decisions"
  entries "$f" D
  echo "-- deferred"
  entries "$f" F
  a="$dir/answers/$label.md"
  if [ -f "$a" ]; then
    echo "-- answers: $(grep -c '^## A[0-9][0-9]*$' "$a" || true), overrides: $(grep -c '^## Override O[0-9][0-9]*$' "$a" || true)"
  fi
done

echo
echo "== Contracts"
for f in "$dir"/contracts/*.md; do
  [ -f "$f" ] || continue
  label=$(basename "$f" .md)
  grep '^## ' "$f" | sed 's/^## //' | awk -v l="$label" '
    { if (!($0 in n)) order[++k] = $0; n[$0]++ }
    END { for (i = 1; i <= k; i++) print l " · " order[i] (n[order[i]] > 1 ? " (" n[order[i]] " versions; the last wins)" : "") }
  '
done

if [ -f "$dir/ledger.md" ]; then
  echo
  echo "== Ledger (open)"
  grep '^- \[ \]' "$dir/ledger.md" || echo "(none)"
fi
[ "$open" -eq 0 ]
