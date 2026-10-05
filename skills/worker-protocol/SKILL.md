---
name: worker-protocol
description: File-based communication protocol between an orchestrating session and the agents or workflow workers it dispatches. Every file has a single writer. Workers decide within a fixed precedence and log it, publish interface contracts for their peers, escalate only owner-level, contradictory or blocking questions, and record a durable result. A watcher surfaces escalations and results to the manager, who answers in its own files. Every deferred item lands in a ledger that must be closed before the work is called done. Use when dispatching two or more concurrent agents or a scripted workflow whose workers may need answers, share APIs or leave work behind, and when a brief you received names a protocol directory. Not for a single subagent with a fully specified task.
---

# Worker protocol v2: decide, log, escalate rarely

Chat between a manager and its workers is noisy, reaches the user's screen and is lost on
compaction. In some harnesses a message to a running or finished worker starts a second copy of
it. This protocol moves all coordination into one **run directory**, where every file has exactly
one writer:

| Path | Writer | Purpose |
|---|---|---|
| `RUN.md` | manager | Run id, task, status; workers check the id against their brief |
| `PROTOCOL.md` | manager (from template) | The rules every worker follows, with this run's sources of authority |
| `workers/<label>.md` | that worker | `## Decisions`, `## Q<n>` escalations, `## Deferred`, final `## Result` |
| `contracts/<label>.md` | that worker | Interfaces, sizes, tokens, behaviours its peers must follow |
| `answers/<label>.md` | manager | `## A<n>` answers and `## Override O<n>` entries, binding |
| `ledger.md` | manager | Every deferred or found item until done with evidence or reported |

Single writers mean no lost updates, however many workers run at once. The test suite runs 16
concurrent workers against a manager answering from watcher events. Never write credentials or
other secrets into any of these files.

Scripts live in this skill's `scripts/` directory (POSIX `sh`; `<skill>` below means the directory
holding this file).

## If you are the manager

1. **Create the run** in a scratch location outside the repository:
   `sh <skill>/scripts/init.sh <dir> --task "<one line>"`. It refuses a non-empty directory, so a
   stale run never leaks into a new one, and prints the run id. `--resume` reopens an existing run.
2. **Fill in the sources of authority** in `<dir>/PROTOCOL.md`, section 1, in the order they win:
   - the user's decisions in their own words;
   - the spec;
   - any approved reference;
   - the repository's instruction files.

   This list is what lets workers decide alone; a vague list produces questions.
3. **Brief every worker** with `templates/brief-snippet.md`, filled with its label (unique,
   `[a-z0-9-]+`), the run id and the directory. Add `WAIT <minutes>` only if you will answer that
   fast and the worker may hold its slot meanwhile; otherwise blocked workers end BLOCKED.
4. **Arm the watcher** before workers start: `sh <skill>/scripts/watch.sh <dir>` prints
   `ESCALATION <label> Q<n> <mode>` per unanswered question and `RESULT <label> <status>` per
   result. Run it as a background monitor that notifies you per line (Claude Code: the Monitor
   tool, re-armed on expiry). Without one, run `harvest.sh` at each checkpoint.
5. **Answer in your own files**:
   - `sh <skill>/scripts/answer.sh <dir> <label> <n> "<answer>"` answers a question;
   - `--override "<text>"` overturns a logged decision or redirects a worker.

   When a question was the worker's to decide, name the precedence rule it should have applied.
6. **Never message a worker in chat, running or finished.** Answer in its answers file, even when
   it wrote to you directly. In Claude Code, sending a message to a workflow worker resumes it as a
   *new* instance next to the running one, and two writers then share one worktree. Single
   subagents launched on their own may be messaged.
7. **Re-dispatch BLOCKED workers.** Answer the question, then start a continuation with the same
   label and run id. It reads its worker file and answers and resumes. Stop the original first if
   it is still running.
8. **Harvest at every checkpoint**: after each wave, before integration and before declaring done.
   - `sh <skill>/scripts/harvest.sh <dir>` prints open questions, each result, decisions, deferred
     items and contracts, and exits 1 while a question is open.
   - Fold each deferred item, each PARTIAL or BLOCKED result and each problem you find into
     `ledger.md`, with its source.
   - Review decisions in bulk.
   - Trust a worker's `## Result` only as far as its evidence goes: verify it.
9. **Close the ledger.** Work is not done while a ledger line is open. Each line ends `[x]` with
   its evidence, or `[R]`: reported to the user, with the reason it could not be fixed. The final
   report names every `[R]` item. Set `RUN.md` status to CLOSED at the end.

## If you are a worker

Your brief names your label, the run id and the directory. Read `<dir>/PROTOCOL.md` first and
follow it. In short:
- Check that the `RUN.md` id matches your brief.
- Write only your own two files.
- Decide by the precedence and log one line per decision.
- Publish contracts, and read the other workers' contracts before each commit.
- Escalate a contract conflict at once, and add nothing new that depends on it.
- Escalate only matters no higher source already authorised.
- When blocked, finish the unblocked work and end BLOCKED instead of waiting.
- Defer visibly.
- Write `## Result` (status, changes, tests, evidence, remaining) before your final reply.

`sh <skill>/scripts/ask.sh <dir> <label> "<context>" "<question>" "<options>" "<default>" [--blocked] [--wait <s>]`
appends a well-formed question.

## Why it works

Most worker questions are already answered by an ordered list of authorities. Making the list
explicit turns questions into logged decisions that the manager reviews in bulk. Contracts let
peers converge without a hub. Single-writer files make the record safe under heavy parallelism.
Durable results mean the manager verifies evidence instead of trusting narration. The ledger keeps
deferred work from evaporating between waves, sessions or compactions.
