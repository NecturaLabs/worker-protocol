# worker-protocol

A small, file-based communication protocol for an AI agent that orchestrates other agents: Claude
Code subagents and dynamic workflows, Codex agents, or any harness where one session dispatches
many workers.

**Decide, log, escalate rarely.**

- Workers **decide** most questions themselves, using an explicit, ordered list of sources of
  authority: the user's decisions, then the spec, the approved reference, the repository's
  conventions, and finally judgment. Each decision is **logged** as one line the manager reviews
  in bulk.
- Workers publish the interfaces their peers depend on as **contracts**. A contract conflict is
  escalated at once and never built on.
- Workers **escalate** only what they cannot decide:
  - user-level matters that no higher source already authorised;
  - contradictions;
  - blocks.

  A watcher surfaces each escalation to the manager, who answers in its own file. A blocked worker
  finishes its unblocked work, ends BLOCKED, and is re-dispatched.
- Every worker ends with a durable **result** (status, changes, tests, evidence, remaining), so the
  manager verifies evidence rather than trusting narration.
- Everything left undone lands in a **ledger** the manager must close before the work is done:
  each item fixed with evidence, or reported to the user.

Every file has a single writer, so the record stays intact with any number of concurrent workers.
Every run has an id, so a stale directory never leaks into a new run.

Why files and not chat: chat floods the user's screen and is lost on compaction. In some harnesses,
messaging a running or finished worker also starts a second copy of it. Files persist, can be
reviewed afterwards, and with a watcher they are as fast as chat.

## Layout

```
<run>/
  RUN.md               manager   run id, task, status
  PROTOCOL.md          manager   the rules, with this run's sources of authority
  ledger.md            manager   deferred and found items until closed
  workers/<label>.md   worker    decisions (D<n>:), questions (Q<n>), deferred (F<n>:), result
  contracts/<label>.md worker    interfaces peers must follow
  answers/<label>.md   manager   answers (A<n>) and overrides (O<n>)
  .watch-seen          watch.sh  events already printed
  answers/.<label>.lock answer.sh held while an answer is written
```

## Install (Claude Code)

```sh
claude plugin marketplace add NecturaLabs/worker-protocol
claude plugin install worker-protocol@worker-protocol
```

The repository is also a standard Agent Skills plugin (`skills/worker-protocol/SKILL.md`), so
other harnesses that read Claude-format marketplaces can install it the same way.

## Use

```sh
S="<plugin>/skills/worker-protocol/scripts"     # quote it: the path may contain spaces
sh "$S/init.sh" /scratch/run --task "Migrate views to the UI kit"   # prints the run id
# edit section 1 of /scratch/run/PROTOCOL.md; brief workers with templates/brief-snippet.md
sh "$S/watch.sh" /scratch/run        # background monitor: ESCALATION / RESULT lines
sh "$S/answer.sh" /scratch/run mig-a 2 "Use (b): the preview wins on visuals."
sh "$S/answer.sh" /scratch/run mig-a --override "Keep the old row height until integration."
sh "$S/harvest.sh" /scratch/run      # checkpoint summary; exit 1 while questions are open
sh "$S/init.sh" /scratch/run --close # refuses while a question or a ledger line is open
```

A worker escalates with:

```sh
sh "$S/ask.sh" /scratch/run mig-a "views/x.rs:40" "Delete the dead const?" \
  "(a) delete (b) keep" "(a)"        # add --blocked, and --wait <s> only if the brief allows
```

The files are plain Markdown and can be written by hand; the scripts only keep them consistent.
The scripts are POSIX `sh` and use only POSIX utilities (`awk`, `grep`, `sed`, `sort`, `tr`,
`mkfifo` and the like). `watch.sh` uses `inotifywait` or `fswatch` when installed, and polls every
5 seconds otherwise; `WORKER_PROTOCOL_WATCHER=inotifywait|fswatch|poll` forces one. It exits 1 if
its event source dies.

## Changes in 2.0

- **Single-writer layout:** `workers/`, `contracts/` and `answers/`. Answers no longer rewrite a
  worker's file, which removes a lost-update race.
- **Run identity:** `RUN.md`; `init.sh` refuses a non-empty directory unless given `--resume`.
- **Durable results:** a `## Result` block, reported by the watcher.
- **Workers:**
  - contract conflicts escalate instead of being deferred;
  - blocked workers end BLOCKED instead of holding a slot;
  - escalation only where no higher source already authorised the matter;
  - no secrets in protocol files.
- **Append-only worker files:** decisions are `D<n>:` lines and deferred items `F<n>:` lines,
  wherever they fall in the file.
- **Watcher:** starts listening before its first scan, prints each event once per run across
  restarts (`--replay` to repeat), and reports each `## Result` block, including a repeated status.
- **Run lifecycle:** `RUN.md` names the scripts directory; `init.sh --close` ends a run once no
  question or ledger line is open, and `--resume` refuses a closed one.
- **Robustness:** answers are serialised by a lock that INT, TERM and HUP release (a holder
  killed outright is named, never silently taken over); the watcher never parses a half-written line; the watcher exits loudly if its event source dies; fswatch
  readiness is confirmed with a probe instead of a fixed delay.
- **Tests:** a 16-worker concurrency test, plus regression tests for each of the above.

Migrating a 1.x directory: start a new run with `init.sh`. Move each worker's `<label>.md` into
`workers/`, and copy its answers into `answers/<label>.md` as `## A<n>` blocks.

## Test

```sh
sh tests/run.sh
```

## Licence

MIT. See [LICENSE](LICENSE).
