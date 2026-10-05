#!/bin/sh
# Manager side: summarise every worker file for a checkpoint.
# Usage: harvest.sh <dir>
# Prints open questions, then each worker's decisions and deferred items, then the contracts
# headings and the ledger's open lines. Exit status 1 when a question is still open.
set -eu

[ $# -eq 1 ] || { echo "usage: harvest.sh <dir>" >&2; exit 2; }
dir=$1
status=0

section() { # file, heading: print the non-empty lines of every section with that heading
  awk -v h="$2" '$0 == h { on = 1; next } /^## / { on = 0 } on && NF { print }' "$1"
}

echo "== Open questions"
for f in "$dir"/*.md; do
  [ -f "$f" ] || continue
  if grep -H '^## Q[0-9][0-9]* · .* · OPEN$' "$f"; then status=1; fi
done

for f in "$dir"/*.md; do
  [ -f "$f" ] || continue
  case $(basename "$f") in PROTOCOL.md | contracts.md | ledger.md) continue ;; esac
  label=$(basename "$f" .md)
  echo
  echo "== $label"
  echo "-- decisions"
  section "$f" "## Decisions"
  echo "-- deferred"
  section "$f" "## Deferred"
  if grep -q '^## Overrides$' "$f"; then
    echo "-- overrides"
    section "$f" "## Overrides"
  fi
done

if [ -f "$dir/contracts.md" ]; then
  echo
  echo "== Contracts"
  grep '^## ' "$dir/contracts.md" || true
fi
if [ -f "$dir/ledger.md" ]; then
  echo
  echo "== Ledger (open)"
  grep -- '- \[ \]' "$dir/ledger.md" || echo "(none)"
fi
exit $status
