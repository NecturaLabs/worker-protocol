#!/bin/sh
# Tests for the protocol scripts: functional checks, then 16 concurrent workers and a manager
# answering from watcher events. Usage: sh tests/run.sh
set -eu

root="$(cd "$(dirname "$0")/.." && pwd)"
s="$root/skills/worker-protocol/scripts"
work=$(mktemp -d)
pids=
cleanup() {
  for p in $pids; do kill "$p" 2>/dev/null || true; done
  rm -rf "$work"
}
trap cleanup EXIT INT TERM
fails=0

check() { # description, command...
  desc=$1
  shift
  if "$@"; then echo "ok   $desc"; else echo "FAIL $desc"; fails=$((fails + 1)); fi
}

# --- init and run identity
d="$work/run"
id=$(sh "$s/init.sh" "$d" --task "functional test" | tail -n 1)
check "init prints a run id" sh -c "printf '%s' '$id' | grep -q '^run-'"
check "init writes RUN.md with that id" grep -q "Run id:\*\* $id" "$d/RUN.md"
check "init creates the layout" test -f "$d/PROTOCOL.md" -a -f "$d/ledger.md" -a -d "$d/workers" -a -d "$d/contracts" -a -d "$d/answers"
check "init refuses a non-empty directory" sh -c "! sh '$s/init.sh' '$d' --task again >/dev/null 2>&1"
check "init --resume keeps the run" sh -c "sh '$s/init.sh' '$d' --resume | grep -q '$id'"
check "init --resume refuses a directory without a run" sh -c "! sh '$s/init.sh' '$work/none' --resume >/dev/null 2>&1"

# --- ask, answer, override (single writer per file)
check "ask rejects a bad label" sh -c "! sh '$s/ask.sh' '$d' 'Bad_Label' c q o d 2>/dev/null"
q1=$(sh "$s/ask.sh" "$d" worker-a "x.rs:1" "Which?" "(a) one (b) two" "(a)")
q2=$(sh "$s/ask.sh" "$d" worker-a "y.rs:2" "Second?" "(a) (b)" "(b)" --blocked)
check "ask numbers questions Q1, Q2" test "$q1 $q2" = "Q1 Q2"
check "ask records the mode" sh -c "grep -A1 -x '## Q2' '$d/workers/worker-a.md' | grep -qx '\*\*Mode:\*\* BLOCKED'"
before=$(cksum < "$d/workers/worker-a.md")
sh "$s/answer.sh" "$d" worker-a 1 "Use (b)." > /dev/null
check "answer never touches the worker's file" test "$(cksum < "$d/workers/worker-a.md")" = "$before"
check "answer appends A1 to answers/" grep -qx '## A1' "$d/answers/worker-a.md"
check "answer refuses a repeat" sh -c "! sh '$s/answer.sh' '$d' worker-a 1 again 2>/dev/null"
check "answer refuses an unknown question" sh -c "! sh '$s/answer.sh' '$d' worker-a 9 x 2>/dev/null"
sh "$s/answer.sh" "$d" worker-a --override "Use the preview." > /dev/null
sh "$s/answer.sh" "$d" worker-a --override "Second override." > /dev/null
check "overrides are numbered O1, O2" sh -c "grep -qx '## Override O1' '$d/answers/worker-a.md' && grep -qx '## Override O2' '$d/answers/worker-a.md'"

(sleep 2; sh "$s/answer.sh" "$d" worker-a 3 "Go with (a)." > /dev/null) &
out=$(sh "$s/ask.sh" "$d" worker-a ctx "Third?" "(a)" "(a)" --wait 30)
check "ask --wait prints the answer" sh -c "printf '%s' \"\$1\" | grep -q 'Go with (a).'" _ "$out"
check "ask --wait times out with status 3" sh -c "sh '$s/ask.sh' '$d' worker-b c q o d --wait 1 >/dev/null 2>&1; test \$? -eq 3"

printf '\n## Decisions\nD1: picked x — because spec\n' >> "$d/workers/worker-b.md"
printf '\n## Result\n**Status:** PARTIAL\n**Remaining:** y\n' >> "$d/workers/worker-b.md"
printf '## api · rows\nrow height 28\n' > "$d/contracts/worker-b.md"
printf '%s\n' '- [ ] L1 something open [worker-b]' >> "$d/ledger.md"
set +e
sh "$s/harvest.sh" "$d" > "$work/harvest.out"
hs=$?
set -e
check "harvest exits 1 while questions are open" test "$hs" -eq 1
check "harvest lists open questions" grep -q 'worker-a Q2 (BLOCKED)' "$work/harvest.out"
check "harvest lists decisions" grep -q 'D1: picked x' "$work/harvest.out"
check "harvest shows the result status" grep -q -- '-- result: PARTIAL' "$work/harvest.out"
check "harvest lists contracts by label" grep -q 'worker-b · api · rows' "$work/harvest.out"
check "harvest lists open ledger lines" grep -q 'L1 something open' "$work/harvest.out"

# --- concurrency: 16 workers write their own files while the manager answers from watcher events
c="$work/conc"
sh "$s/init.sh" "$c" --task "concurrency test" > /dev/null
workers=16 decisions=40 questions=3
sh "$s/watch.sh" "$c" > "$work/watch.out" 2>&1 &
pids="$pids $!"
sleep 1

manager() { # answer every ESCALATION the watcher prints until all are answered
  total=$((workers * questions))
  done_count=0 waited=0
  while [ "$done_count" -lt "$total" ] && [ "$waited" -lt 120 ]; do
    grep '^ESCALATION ' "$work/watch.out" | while read -r _ label q _; do
      n=${q#Q}
      grep -qx "## A$n" "$c/answers/$label.md" 2>/dev/null ||
        sh "$s/answer.sh" "$c" "$label" "$n" "answer to $label $q" > /dev/null
    done
    done_count=$(cat "$c"/answers/*.md 2>/dev/null | grep -c '^## A[0-9][0-9]*$' || true)
    sleep 1
    waited=$((waited + 1))
  done
}

worker() { # label
  f="$c/workers/$1.md"
  printf '# %s\n\n## Decisions\n' "$1" > "$f"
  i=1
  while [ "$i" -le "$decisions" ]; do
    printf 'D%s: decision %s of %s\n' "$i" "$i" "$1" >> "$f"
    printf '## item-%s\nvalue %s\n' "$i" "$i" >> "$c/contracts/$1.md"
    case $i in 10 | 20 | 30) sh "$s/ask.sh" "$c" "$1" ctx "q$i" opts def > /dev/null ;; esac
    i=$((i + 1))
  done
  printf '\n## Result\n**Status:** COMPLETE\n' >> "$f"
}

manager &
mpid=$!
w=1 wpids=
while [ "$w" -le "$workers" ]; do
  worker "w$w" &
  wpids="$wpids $!"
  w=$((w + 1))
done
for p in $wpids; do wait "$p"; done
wait "$mpid"
sleep 2

lost=0 w=1
while [ "$w" -le "$workers" ]; do
  f="$c/workers/w$w.md"
  [ "$(grep -c '^D[0-9]' "$f")" -eq "$decisions" ] || lost=1
  [ "$(grep -c '^## Q[0-9]' "$f")" -eq "$questions" ] || lost=1
  [ "$(grep -c '^## item-' "$c/contracts/w$w.md")" -eq "$decisions" ] || lost=1
  [ "$(grep -c '^## A[0-9]' "$c/answers/w$w.md")" -eq "$questions" ] || lost=1
  w=$((w + 1))
done
check "16 concurrent workers: no decision, question, contract or answer lost" test "$lost" -eq 0
check "watcher reported every question exactly once" test "$(grep -c '^ESCALATION ' "$work/watch.out")" -eq $((workers * questions))
check "watcher reported every COMPLETE result" test "$(grep -c '^RESULT w[0-9]* COMPLETE$' "$work/watch.out")" -eq "$workers"
check "harvest of the concurrent run has nothing open" sh -c "sh '$s/harvest.sh' '$c' > /dev/null"

if command -v shellcheck >/dev/null 2>&1; then
  check "shellcheck" shellcheck -x -s sh "$s"/*.sh "$root/tests/run.sh"
fi

echo
if [ "$fails" -ne 0 ]; then
  echo "$fails failed"
  exit 1
fi
echo "all tests passed"
