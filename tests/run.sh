#!/bin/sh
# End-to-end test of the protocol scripts in a temporary directory.
# Usage: sh tests/run.sh
set -eu

root="$(cd "$(dirname "$0")/.." && pwd)"
s="$root/skills/worker-protocol/scripts"
work=$(mktemp -d)
watch_pid=
cleanup() { [ -n "$watch_pid" ] && kill "$watch_pid" 2>/dev/null; rm -rf "$work"; }
trap cleanup EXIT INT TERM
d="$work/qa"
fails=0

check() { # description, command...
  desc=$1; shift
  if "$@"; then echo "ok   $desc"; else echo "FAIL $desc"; fails=$((fails + 1)); fi
}

sh "$s/init.sh" "$d" > /dev/null
check "init creates the three files" test -f "$d/PROTOCOL.md" -a -f "$d/contracts.md" -a -f "$d/ledger.md"
echo "edited" >> "$d/PROTOCOL.md"
sh "$s/init.sh" "$d" > /dev/null
check "init keeps edited files" grep -q '^edited$' "$d/PROTOCOL.md"

sh "$s/watch.sh" "$d" > "$work/watch.out" 2>&1 &
watch_pid=$!
sleep 1

check "ask rejects a bad label" sh -c "! sh '$s/ask.sh' '$d' 'Bad_Label' c q o d 2>/dev/null"
h1=$(sh "$s/ask.sh" "$d" worker-a "x.rs:1" "Which?" "(a) one (b) two" "(a), CONTINUING")
check "ask prints Q1 heading" test "$h1" = "## Q1 · worker-a · OPEN"
h2=$(sh "$s/ask.sh" "$d" worker-a "y.rs:2" "Second?" "(a) (b)" "(b), CONTINUING")
check "ask numbers the next question Q2" test "$h2" = "## Q2 · worker-a · OPEN"

sleep 2
check "watch reports Q1" grep -q 'ESCALATION .*worker-a.md:## Q1 · worker-a · OPEN' "$work/watch.out"
check "watch reports Q2" grep -q 'ESCALATION .*worker-a.md:## Q2 · worker-a · OPEN' "$work/watch.out"

sh "$s/answer.sh" "$d" worker-a 1 "Use (b)." > /dev/null
check "answer flips Q1 to ANSWERED" grep -qx '## Q1 · worker-a · ANSWERED' "$d/worker-a.md"
check "answer leaves Q2 open" grep -qx '## Q2 · worker-a · OPEN' "$d/worker-a.md"
check "answer sits inside Q1, before Q2" sh -c "awk '/^## Q1 /{a=1} /^\\*\\*A:\\*\\* Use \\(b\\)\\.\$/{if(a&&!b)ok=1} /^## Q2 /{b=1} END{exit !ok}' '$d/worker-a.md'"
check "answer refuses an already answered question" sh -c "! sh '$s/answer.sh' '$d' worker-a 1 again 2>/dev/null"

(sleep 2; sh "$s/answer.sh" "$d" worker-a 3 "Go with (a)." > /dev/null) &
out=$(sh "$s/ask.sh" "$d" worker-a ctx "Third?" "(a)" "(a), BLOCKED" --wait 30)
check "ask --wait returns the answer" sh -c "printf '%s' \"\$1\" | grep -q 'Go with (a).'" _ "$out"
check "ask --wait times out with status 3" sh -c "sh '$s/ask.sh' '$d' worker-b c q o d --wait 1 >/dev/null 2>&1; test \$? -eq 3"

printf '\n## Decisions\nD1: picked x — because spec\n' >> "$d/worker-b.md"
printf '%s\n' '- [ ] L1 something open [worker-b]' >> "$d/ledger.md"
set +e
sh "$s/harvest.sh" "$d" > "$work/harvest.out"
hs=$?
set -e
check "harvest exits 1 while questions are open" test "$hs" -eq 1
check "harvest lists decisions" grep -q 'D1: picked x' "$work/harvest.out"
check "harvest lists open ledger lines" grep -q 'L1 something open' "$work/harvest.out"

if command -v shellcheck >/dev/null 2>&1; then
  check "shellcheck" shellcheck -s sh "$s"/*.sh "$root/tests/run.sh"
fi

echo
if [ "$fails" -ne 0 ]; then
  echo "$fails failed"
  exit 1
fi
echo "all tests passed"
