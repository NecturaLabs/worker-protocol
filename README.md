# worker-protocol

A small, file-based communication protocol for an AI agent that orchestrates other agents: Claude
Code subagents and workflows, Codex agents, or any harness where one session dispatches workers.

**Decide, log, escalate rarely.**

- Workers **decide** most questions themselves, using an explicit, ordered list of sources of
  authority (the user's decisions, the spec, the approved reference, the repository's conventions,
  then judgment), and **log** each decision as one line the manager reviews in bulk.
- Workers publish the interfaces their peers depend on in an append-only **contracts** file, so
  parallel workers converge without routing through the manager.
- Workers **escalate** only user-level matters (product rules, privacy, credentials, network, new
  dependencies, unsafe code, anything destructive), contradictions the precedence cannot settle,
  or a full block — into their own file. A watcher surfaces each escalation to the manager, who
  answers in place.
- Everything a worker leaves undone lands in a **ledger** the manager must close (done with
  evidence, or reported to the user) before the work is called done.

Why files and not chat: chat floods the user's screen, is lost on compaction, and in some harnesses
messaging a running or finished worker restarts it as a second writer. Files persist, can be
reviewed later, and with a watcher are as fast as chat.

## Install

Claude Code:

```sh
claude plugin marketplace add NecturaLabs/worker-protocol
claude plugin install worker-protocol@worker-protocol
```

Codex:

```sh
codex plugin marketplace add https://github.com/NecturaLabs/worker-protocol.git
codex plugin add worker-protocol@worker-protocol
```

The skill (`worker-protocol`) loads when an agent is about to dispatch two or more workers, or when
a brief it received names a protocol directory.

## Use

Manager:

```sh
S=<plugin>/skills/worker-protocol/scripts
sh $S/init.sh /path/to/scratch/qa      # PROTOCOL.md, contracts.md, ledger.md
# edit section 1 of PROTOCOL.md: this task's sources of authority, in order
# brief each worker with templates/brief-snippet.md (label + directory)
sh $S/watch.sh /path/to/scratch/qa     # run as a background monitor: one line per escalation
sh $S/answer.sh /path/to/scratch/qa mig-a 2 "Use (b): the preview wins on visuals."
sh $S/harvest.sh /path/to/scratch/qa   # at each checkpoint: questions, decisions, deferred, ledger
```

Worker:

```sh
sh $S/ask.sh /path/to/scratch/qa mig-a "views/x.rs:40" "Delete the dead const?" \
  "(a) delete (b) keep" "(a), CONTINUING"        # add --wait to block for the answer
```

File formats are plain Markdown and can be written by hand; the scripts only keep them consistent.
The scripts are POSIX `sh` and need `awk` and `grep`; `watch.sh` uses `inotifywait` or `fswatch`
when installed and polls otherwise.

## Test

```sh
sh tests/run.sh
```

## Licence

MIT. See [LICENSE](LICENSE).
