#!/bin/sh
# Tests for the protocol scripts: functional checks, the watcher's lifecycle, then 16 concurrent
# workers and a manager answering from watcher events. Usage: sh tests/run.sh
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

# True when the command exits with <code> and its stderr matches <pattern>.
fails_with() { # code, pattern, command...
  code=$1 pattern=$2
  shift 2
  set +e
  "$@" > /dev/null 2> "$work/stderr"
  rc=$?
  set -e
  [ "$rc" -eq "$code" ] && grep -q -- "$pattern" "$work/stderr"
}

# shellcheck disable=SC2009 # the path must match as a fixed string, which pgrep cannot do
inotify_children() { # dir: number of inotifywait processes watching it
  ps -eo args | grep -F "$1/workers" | grep -cE '^([^ ]*/)?inotifywait ' || true
}

# --- init and run identity (the run directory has a space in its path)
d="$work/run dir"
id=$(sh "$s/init.sh" "$d" --task "functional test" | tail -n 1)
check "init prints a run id" sh -c "printf '%s' '$id' | grep -q '^run-'"
check "init writes RUN.md with that id" grep -q "Run id:\*\* $id" "$d/RUN.md"
check "init records the scripts directory" grep -qF -- "- **Scripts:** $s" "$d/RUN.md"
check "init creates the layout" test -f "$d/PROTOCOL.md" -a -f "$d/ledger.md" -a -d "$d/workers" -a -d "$d/contracts" -a -d "$d/answers"
check "init refuses a non-empty directory" fails_with 1 'is not empty' sh "$s/init.sh" "$d" --task again
check "init --resume keeps the run" sh -c "sh \"\$1\" \"\$2\" --resume | grep -q '$id'" _ "$s/init.sh" "$d"
check "init --resume refuses a directory without a run" fails_with 1 'RUN.md missing' sh "$s/init.sh" "$work/none" --resume
check "init rejects an unknown mode" fails_with 2 'usage' sh "$s/init.sh" "$d" --bogus

# --- a fresh run's ledger has no open line (the template's prose is not an item)
sh "$s/harvest.sh" "$d" > "$work/fresh.out"
check "harvest of a fresh run shows no open ledger line" sh -c "sed -n '/^== Ledger/,\$p' \"\$1\" | sed -n 2p | grep -qx '(none)'" _ "$work/fresh.out"

# --- ask, answer, override (single writer per file)
check "ask rejects a bad label" fails_with 2 'label must match' sh "$s/ask.sh" "$d" 'Bad_Label' c q o d
check "ask rejects a non-numeric wait" fails_with 2 'whole number' sh "$s/ask.sh" "$d" worker-z c q o d --wait abc
check "ask rejects a wait too large for the shell" fails_with 2 'too large' sh "$s/ask.sh" "$d" worker-z c q o d --wait 999999999999999999999999
check "a rejected ask writes nothing" test ! -e "$d/workers/worker-z.md"
q1=$(sh "$s/ask.sh" "$d" worker-a "x.rs:1" "Which?" "(a) one (b) two" "(a)")
q2=$(sh "$s/ask.sh" "$d" worker-a "y.rs:2" "Second?" "(a) (b)" "(b)" --blocked)
check "ask numbers questions Q1, Q2" test "$q1 $q2" = "Q1 Q2"
check "ask records the mode" sh -c "grep -A1 -x '## Q2' \"\$1\" | grep -qx '\*\*Mode:\*\* BLOCKED'" _ "$d/workers/worker-a.md"
before=$(cksum < "$d/workers/worker-a.md")
sh "$s/answer.sh" "$d" worker-a 1 "Use (b)." > /dev/null
check "answer never touches the worker's file" test "$(cksum < "$d/workers/worker-a.md")" = "$before"
check "answer appends A1 to answers/" grep -qx '## A1' "$d/answers/worker-a.md"
check "answer refuses a repeat" fails_with 1 'already answered' sh "$s/answer.sh" "$d" worker-a 1 again
check "answer refuses an unknown question" fails_with 1 'no question Q9' sh "$s/answer.sh" "$d" worker-a 9 x
check "answer rejects a bad question number" fails_with 2 'whole number' sh "$s/answer.sh" "$d" worker-a 1x x
sh "$s/answer.sh" "$d" worker-a --override "Use the preview." > /dev/null
sh "$s/answer.sh" "$d" worker-a --override "Second override." > /dev/null
check "overrides are numbered O1, O2" sh -c "grep -qx '## Override O1' \"\$1\" && grep -qx '## Override O2' \"\$1\"" _ "$d/answers/worker-a.md"

# --- answer text cannot forge headings
sh "$s/ask.sh" "$d" worker-x "$(printf 'ctx\n## Result')" "$(printf 'q\n**Status:** COMPLETE')" o d > /dev/null
check "a multi-line question cannot forge a result" sh -c "! grep -qx '## Result' \"\$1\"" _ "$d/workers/worker-x.md"
sh "$s/answer.sh" "$d" worker-x 1 "$(printf 'Line one.\n## A5\nnot an answer')" > /dev/null
check "a multi-line answer cannot mark another question answered" sh -c "! grep -qx '## A5' \"\$1\"" _ "$d/answers/worker-x.md"

# --- two managers answering the same question at once: exactly one answer
sh "$s/ask.sh" "$d" worker-y c q o d > /dev/null
sh "$s/answer.sh" "$d" worker-y 1 first > /dev/null 2>&1 &
sh "$s/answer.sh" "$d" worker-y 1 second > /dev/null 2>&1 &
wait
check "parallel answers to one question write one A1" test "$(grep -c '^## A1$' "$d/answers/worker-y.md")" -eq 1

# --- a failed write is reported, and a lock left by a dead holder is taken over
sh "$s/ask.sh" "$d" worker-w c q o d > /dev/null
mkdir -p "$d/answers/worker-w.md"
check "answer fails when it cannot write" sh -c "! sh \"\$1\" \"\$2\" worker-w 1 x > \"\$3\" 2>/dev/null && ! grep -q answered \"\$3\"" _ "$s/answer.sh" "$d" "$work/answer.out"
rmdir "$d/answers/worker-w.md"
sh "$s/answer.sh" "$d" worker-w 1 x > /dev/null
check "the lock is released after an answer" test ! -e "$d/answers/.worker-w.lock"

# --- waiting
(sleep 2; sh "$s/answer.sh" "$d" worker-a 3 "Go with (a)." > /dev/null) &
out=$(sh "$s/ask.sh" "$d" worker-a ctx "Third?" "(a)" "(a)" --wait 30)
check "ask --wait prints the answer" sh -c "printf '%s' \"\$1\" | grep -q 'Go with (a).'" _ "$out"
check "ask --wait times out with status 3" fails_with 3 'no answer after 1s' sh "$s/ask.sh" "$d" worker-b c q o d --wait 1

# --- multi-digit question numbers
i=1
while [ "$i" -le 12 ]; do sh "$s/ask.sh" "$d" worker-c c "q$i" o d > /dev/null; i=$((i + 1)); done
sh "$s/answer.sh" "$d" worker-c 1 a > /dev/null
sh "$s/answer.sh" "$d" worker-c 10 a > /dev/null
set +e
sh "$s/harvest.sh" "$d" > "$work/harvest.out"
hs=$?
set -e
check "Q1-Q12: harvest lists exactly the ten unanswered" test "$(grep -c '^worker-c Q' "$work/harvest.out")" -eq 10
check "Q1-Q12: Q10 is answered, Q11 is open" sh -c "! grep -q '^worker-c Q10 ' \"\$1\" && grep -q '^worker-c Q11 ' \"\$1\"" _ "$work/harvest.out"

# --- decisions and deferred items appended after questions, results, contracts and the ledger
{
  printf 'D1: picked x — because spec\nF1: left y for later\n'
  printf '\n## Decisions\nlegacy decision line\n'
  printf '\n## Deferred\nF2: deferred under its heading\nD2: a decision under the deferred heading\n'
  printf '\n## Result\n**Status:** PARTIAL\n**Remaining:** y\n'
} >> "$d/workers/worker-b.md"
printf '\n## Result\n**Status:** COMPLETE | PARTIAL | BLOCKED\n' >> "$d/workers/worker-x.md"
printf '## api · rows\nrow height 28\n## api · rows\nrow height 26\n' > "$d/contracts/worker-b.md"
printf '%s\n' '- [ ] L1 something open [worker-b]' >> "$d/ledger.md"
set +e
sh "$s/harvest.sh" "$d" > "$work/harvest.out"
hs=$?
set -e
check "harvest exits 1 while questions are open" test "$hs" -eq 1
check "harvest lists open questions" grep -q 'worker-a Q2 (BLOCKED)' "$work/harvest.out"
check "harvest lists D lines appended after questions" grep -q 'D1: picked x' "$work/harvest.out"
check "harvest lists F lines appended after questions" grep -q 'F1: left y for later' "$work/harvest.out"
check "harvest still reads a Decisions heading" grep -q 'legacy decision line' "$work/harvest.out"
check "a numbered D line under Deferred counts as a decision only" sh -c "sed -n '/^-- deferred/,/^--/p' \"\$1\" | grep -q 'F2: deferred' && ! sed -n '/^-- deferred/,/^--/p' \"\$1\" | grep -q 'D2: a decision'" _ "$work/harvest.out"
check "harvest shows the result status" grep -q -- '-- result: PARTIAL' "$work/harvest.out"
printf '\n## Result\n**Status:** COMPLETE' >> "$d/workers/worker-c.md"
set +e
sh "$s/harvest.sh" "$d" > "$work/harvest2.out"
set -e
check "harvest reads a final Status line without a newline" sh -c "sed -n '/^== worker-c/,/^== /p' \"\$1\" | grep -q -- '-- result: COMPLETE'" _ "$work/harvest2.out"
check "harvest warns about the missing newline" grep -q 'the last line has no newline' "$work/harvest2.out"
printf '\n' >> "$d/workers/worker-c.md"
check "a template status is reported INVALID" sh -c "sed -n '/^== worker-x/,/^== /p' \"\$1\" | grep -q -- '-- result: INVALID'" _ "$work/harvest.out"
check "harvest lists contracts by label, once per item" test "$(grep -c 'worker-b · api · rows' "$work/harvest.out")" -eq 1
check "harvest says a contract was superseded" grep -q 'api · rows (2 versions; the last wins)' "$work/harvest.out"
check "harvest lists open ledger lines" grep -q 'L1 something open' "$work/harvest.out"
cp "$d/RUN.md" "$work/RUN.md.bak"
printf '# Run\n' > "$d/RUN.md"
check "harvest survives a RUN.md without fields" sh -c "sh \"\$1\" \"\$2\" | grep -q 'RUN.md has no fields'" _ "$s/harvest.sh" "$d"
cp "$work/RUN.md.bak" "$d/RUN.md"

# --- run lifecycle
check "init --close refuses while questions are open" fails_with 1 'open questions' sh "$s/init.sh" "$d" --close
mkdir -p "$work/notrun"
cp "$d/RUN.md" "$work/notrun/RUN.md"
check "init --close refuses a directory that is not a run" fails_with 1 'not a protocol run' sh "$s/init.sh" "$work/notrun" --close
e="$work/closing"
sh "$s/init.sh" "$e" --task "close test" > /dev/null
printf '%s\n' '- [ ] L1 still open [x]' >> "$e/ledger.md"
check "init --close refuses while a ledger line is open" fails_with 1 'ledger.md has open lines' sh "$s/init.sh" "$e" --close
sh "$s/init.sh" "$d" --close --force > /dev/null
check "init --close marks the run CLOSED" grep -qx -- '- \*\*Status:\*\* CLOSED' "$d/RUN.md"
check "init --resume refuses a closed run" fails_with 1 'is CLOSED' sh "$s/init.sh" "$d" --resume

# --- watcher lifecycle
v="$work/watch run"
sh "$s/init.sh" "$v" --task "watcher test" > /dev/null
sh "$s/ask.sh" "$v" pre c "answered before the watcher" o d > /dev/null
sh "$s/answer.sh" "$v" pre 1 "settled" > /dev/null
if command -v inotifywait >/dev/null 2>&1; then
  # A slow inotifywait: a question written before it listens must still be reported.
  shim="$work/shim"
  mkdir -p "$shim"
  printf '#!/bin/sh\nsleep 2\nexec %s "$@"\n' "$(command -v inotifywait)" > "$shim/inotifywait"
  chmod +x "$shim/inotifywait"
  PATH="$shim:$PATH" sh "$s/watch.sh" "$v" > "$work/w1.out" 2>&1 &
  wpid=$!
  pids="$pids $wpid"
  sleep 1
  sh "$s/ask.sh" "$v" w-a c "during startup" o d > /dev/null
  sleep 4
  check "watcher reports a question written while it starts" grep -qx 'ESCALATION w-a Q1 CONTINUING' "$work/w1.out"
else
  sh "$s/watch.sh" "$v" > "$work/w1.out" 2>&1 &
  wpid=$!
  pids="$pids $wpid"
  sh "$s/ask.sh" "$v" w-a c "during startup" o d > /dev/null
  sleep 7
  check "watcher (polling) reports a question" grep -qx 'ESCALATION w-a Q1 CONTINUING' "$work/w1.out"
fi
check "watcher ignores a question answered before it started" sh -c "! grep -q 'ESCALATION pre ' \"\$1\"" _ "$work/w1.out"
printf '\n## Result\n**Status:** BLOCKED\n' >> "$v/workers/w-a.md"
sleep 1
printf '\n## Result\n**Status:** BLOCKED\n' >> "$v/workers/w-a.md"
sleep 6
check "watcher reports a repeated BLOCKED result twice" test "$(grep -c '^RESULT w-a BLOCKED$' "$work/w1.out")" -eq 2
printf '\n## Result\n**Status:** COM' >> "$v/workers/w-a.md"
sleep 3
printf 'PLETE\n' >> "$v/workers/w-a.md"
sleep 6
check "a half-written status is reported once, when complete" sh -c "! grep -q '^RESULT w-a INVALID' \"\$1\" && test \"\$(grep -c '^RESULT w-a COMPLETE\$' \"\$1\")\" -eq 1" _ "$work/w1.out"
kill "$wpid"
sleep 1
check "a stopped watcher leaves no inotifywait behind" test "$(inotify_children "$v")" -eq 0
sh "$s/watch.sh" "$v" > "$work/w2.out" 2>&1 &
wpid=$!
pids="$pids $wpid"
sleep 7
kill "$wpid"
check "a re-armed watcher repeats nothing" test ! -s "$work/w2.out"
sh "$s/watch.sh" "$v" --replay > "$work/w3.out" 2>&1 &
wpid=$!
pids="$pids $wpid"
sleep 7
kill "$wpid"
check "--replay prints the open question and the results" sh -c "grep -qx 'ESCALATION w-a Q1 CONTINUING' \"\$1\" && test \"\$(grep -c '^RESULT w-a BLOCKED\$' \"\$1\")\" -eq 2" _ "$work/w3.out"

# --- the watcher fails loudly when its event source dies
if command -v inotifywait >/dev/null 2>&1; then
  dying="$work/dying"
  mkdir -p "$dying"
  printf '#!/bin/sh\necho "Failed to watch: upper limit on inotify watches reached" >&2\nexit 1\n' > "$dying/inotifywait"
  chmod +x "$dying/inotifywait"
  check "a watcher whose inotifywait dies exits 1 and says why" sh -c "PATH=\"\$1:\$PATH\" timeout 10 sh \"\$2\" \"\$3\" > /dev/null 2> \"\$4\"; test \$? -eq 1 && grep -q 'stopped' \"\$4\" && grep -q 'limit on inotify' \"\$4\"" _ "$dying" "$s/watch.sh" "$v" "$work/dying.err"

  # fswatch: a stand-in that starts listening only after 3 seconds and prints a count per batch.
  fsw="$work/fsw"
  mkdir -p "$fsw"
  # shellcheck disable=SC2016 # "$1" belongs to the stand-in script
  printf '#!/bin/sh\nshift\nsleep 3\nexec %s -m -r -q -e close_write,moved_to,create --format 1 "$1"\n' "$(command -v inotifywait)" > "$fsw/fswatch"
  chmod +x "$fsw/fswatch"
  f="$work/fswatch run"
  sh "$s/init.sh" "$f" --task "fswatch test" > /dev/null
  PATH="$fsw:$PATH" WORKER_PROTOCOL_WATCHER=fswatch sh "$s/watch.sh" "$f" > "$work/fsw.out" 2>&1 &
  wpid=$!
  pids="$pids $wpid"
  sleep 2
  sh "$s/ask.sh" "$f" w-f c "before fswatch listens" o d > /dev/null
  sleep 6
  check "fswatch: a question written before it listens is reported" grep -qx 'ESCALATION w-f Q1 CONTINUING' "$work/fsw.out"
  sh "$s/ask.sh" "$f" w-f c "after" o d > /dev/null
  sleep 3
  check "fswatch: a later question is reported" grep -qx 'ESCALATION w-f Q2 CONTINUING' "$work/fsw.out"
  check "fswatch: the probe file is gone once listening" sh -c "! ls -A \"\$1\" | grep -q watch-probe" _ "$f/workers"
  kill "$wpid"
  sleep 1
  check "fswatch: a stopped watcher leaves no child behind" test "$(inotify_children "$f")" -eq 0
fi

# --- concurrency: 16 workers write their own files while the manager answers from watcher events
c="$work/conc"
sh "$s/init.sh" "$c" --task "concurrency test" > /dev/null
workers=16 decisions=40 questions=3
sh "$s/watch.sh" "$c" > "$work/watch.out" 2>&1 &
cwatch=$!
pids="$pids $cwatch"
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
  printf '# %s\n' "$1" > "$f"
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
check "harvest of the concurrent run has nothing open" sh -c "sh \"\$1\" \"\$2\" > /dev/null" _ "$s/harvest.sh" "$c"
check "harvest lists all 40 decisions of a concurrent worker" test "$(sh "$s/harvest.sh" "$c" | sed -n '/^== w1$/,/^== /p' | grep -c '^D[0-9]')" -eq "$decisions"
kill "$cwatch"
sleep 1
check "no inotifywait left behind by the concurrency test" test "$(inotify_children "$c")" -eq 0

if command -v shellcheck >/dev/null 2>&1; then
  check "shellcheck" shellcheck -x -s sh "$s"/*.sh "$root/tests/run.sh"
fi

echo
if [ "$fails" -ne 0 ]; then
  echo "$fails failed"
  exit 1
fi
echo "all tests passed"
