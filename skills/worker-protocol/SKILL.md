---
name: worker-protocol
description: File-based communication protocol between an orchestrating session and the agents or workflow workers it dispatches — workers decide within a fixed precedence and log it, publish interface contracts for their peers, and escalate only owner-level or blocking questions into their own file, which a watcher surfaces to the orchestrator; every deferred item lands in a ledger that must be closed before the work is called done. Use when dispatching two or more concurrent agents or a scripted workflow whose workers may need answers, share APIs or leave work behind, and when a brief you received names a protocol directory. Not for a single subagent with a fully specified task.
---

# Worker protocol: decide, log, escalate rarely

Chat between a manager and its workers is noisy, reaches the user's screen, is lost on compaction,
and in some harnesses a message to a worker that already finished restarts it outside its workflow.
This protocol moves all of it into files in one **protocol directory**:

| File | Written by | Purpose |
|---|---|---|
| `PROTOCOL.md` | manager (from template) | The rules every worker follows, with this task's sources of authority |
| `<label>.md` | one worker each | Its `## Decisions` log, `## Q<n>` escalations, `## Deferred` items |
| `contracts.md` | workers, append only | APIs, sizes, tokens, behaviours peers must follow |
| `ledger.md` | manager | Every deferred or found item, until done with evidence or reported |

Scripts live in this skill's `scripts/` directory (POSIX `sh`; `<skill>` below means the directory
holding this file).

## If you are the manager

1. **Create the directory** outside the repository (a scratch location, not tracked):
   `sh <skill>/scripts/init.sh <dir>`. It copies `PROTOCOL.md`, `contracts.md` and `ledger.md`.
2. **Fill in the sources of authority** in `<dir>/PROTOCOL.md` (section 1): the user's decisions in
   their own words, the spec, any approved visual or behavioural reference, and the repository's
   instruction files, in the order they win. This list is what lets workers decide alone; a vague
   list produces questions.
3. **Brief every worker** with `templates/brief-snippet.md`, filled with its label and the
   directory. Labels are unique per worker and match `[a-z0-9-]+`.
4. **Arm the watcher** before workers start: `sh <skill>/scripts/watch.sh <dir>` prints one
   `ESCALATION <file>:<heading>` line per new open question and runs until killed. Run it as a
   background monitor that notifies you per output line (Claude Code: the Monitor tool, re-armed on
   expiry). Without such a facility, run `harvest.sh` at each checkpoint instead.
5. **Answer in place**: `sh <skill>/scripts/answer.sh <dir> <label> <n> "<answer>"` flips the
   heading to `ANSWERED` and appends `**A:**`. Answers are binding. Point to the precedence rule the
   worker should have applied when the question was theirs to decide, so the next one isn't asked.
6. **Never message a worker in chat, running or finished.** Answer in its file, even when it
   wrote to you directly. In Claude Code, sending a message to a workflow worker resumes it as a
   *new* instance next to the running one: two writers then share one worktree, under one label,
   and clobber each other's files. If that happens, keep one instance (stopping the workflow stops
   its originals and leaves resumed copies running), tell the survivor in its file under
   `## Overrides`, and integrate its result yourself.
7. **Harvest at every checkpoint** (after each wave, before integration, before declaring done):
   `sh <skill>/scripts/harvest.sh <dir>` prints open questions, decisions, contracts and deferred
   items. Fold each deferred item and each problem you find into `ledger.md` with its source.
   Review decisions in bulk; overturn one by appending to the worker's file under `## Overrides`
   while it runs, or fix it at integration.
8. **Close the ledger.** Work is not done while a ledger line is open: each ends `[x]` with its
   evidence, or `[R]` (reported to the user, with the reason it could not be fixed). The final
   report names every `[R]` item.

## If you are a worker

Your brief names your label and the protocol directory. Read `<dir>/PROTOCOL.md` before you start
and follow it. In short:

- **Decide it yourself** by the precedence in section 1 of `PROTOCOL.md`, and log one line under
  `## Decisions` in `<dir>/<label>.md`.
- **Publish contracts** in `contracts.md` (append only) when peers or the integrator must follow
  something you introduced; read it before each commit.
- **Escalate only** user-level matters (product rules, privacy, credentials, network, new
  dependencies, unsafe code, legal text, anything destructive or outward-facing), contradictions
  the precedence cannot settle, or a full block. Use
  `sh <skill>/scripts/ask.sh <dir> <label> "<context>" "<question>" "<options>" "<default>" [--wait]`
  or append the same format by hand.
- **Never message the manager in chat** for questions or status.
- **Defer visibly**: everything you leave undone goes under `## Deferred` in your file and in your
  final reply.

## Why it works

Most worker questions are already answered by an ordered list of authorities; making the list
explicit turns questions into logged decisions the manager reviews in bulk. Contracts let peers
converge without a hub. Escalations are rare enough to answer promptly, and the ledger keeps
deferred work from evaporating between waves, sessions or compactions.
