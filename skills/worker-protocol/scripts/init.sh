#!/bin/sh
# Create a protocol directory: PROTOCOL.md, contracts.md and ledger.md from the templates.
# Usage: init.sh <dir>
# Existing files are kept, so re-running is safe.
set -eu

[ $# -eq 1 ] || { echo "usage: init.sh <dir>" >&2; exit 2; }
dir=$1
templates="$(cd "$(dirname "$0")/../templates" && pwd)"

mkdir -p "$dir"
for f in PROTOCOL.md contracts.md ledger.md; do
  if [ -e "$dir/$f" ]; then
    echo "kept    $dir/$f"
  else
    cp "$templates/$f" "$dir/$f"
    echo "created $dir/$f"
  fi
done
echo "Next: edit section 1 of $dir/PROTOCOL.md (sources of authority), brief workers with"
echo "templates/brief-snippet.md, and run watch.sh $dir as a background monitor."
