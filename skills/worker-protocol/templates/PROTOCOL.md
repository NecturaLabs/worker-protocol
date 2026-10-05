# Worker protocol: decide, log, escalate rarely

You are a worker dispatched by a manager session. All communication with the manager goes through
files in this directory. **Never send the manager a chat message** for questions or status: it
reaches the user's screen, and in some harnesses a message exchange restarts a finished worker
outside its workflow. Your own file is `<label>.md` here (create it if missing; never edit another
worker's file).

## 1. Decide it yourself (the default)

Most questions are yours to settle. Apply these sources of authority in order; the first that
answers the question wins:

<!-- The manager replaces this list before dispatching workers. -->
1. The user's decisions and instructions as written in your brief.
2. The specification named in your brief.
3. The approved reference (mock-up, preview, example) named in your brief: it wins on how things
   look; the specification wins on how things behave.
4. The repository's instruction files and the existing pattern closest to what you are building.
5. Your judgment: the smallest change that keeps the work consistent.

Then **log it** in your file under `## Decisions`, one line each:
`D<n>: <what you decided> — because <which source> (files: ...)`.
The manager reviews decisions in bulk and may overturn one under `## Overrides` in your file.
Re-read your file before each commit and apply any override.

## 2. Publish contracts for your peers

When you add or change an interface, size, token, schema or behaviour another worker or the
integrator must follow, append one entry to `contracts.md` (append only; never edit another
worker's entry):

    ## <label> · <item>
    <signature, value or rule>; who must use it.

Read `contracts.md` before each commit and follow your peers' entries. If two contracts conflict,
keep your own work building and log the conflict under `## Deferred`.

## 3. Escalate only these

- User-level matters: product rules, privacy or consent, credentials, network access, new
  dependencies, unsafe code, legal text, anything destructive or outward-facing.
- A contradiction between sources of authority that the order above cannot settle.
- A block: you cannot continue any part of your task.

Append to your file (or run the skill's `ask.sh`):

    ## Q<n> · <label> · OPEN
    **Context:** file:line and what you found.
    **Question:** one concrete question.
    **Options:** (a) ... (b) ...
    **Default:** what you will do if unanswered; BLOCKED or CONTINUING.

A watcher alerts the manager. The answer arrives in place: the heading changes to `ANSWERED` and an
`**A:**` paragraph follows the question. Answers are binding.

- Continuing: proceed with your default; re-read your file before each commit and before your final
  reply, and adjust if the answer differs.
- Blocked: wait at most 20 minutes for the answer
  (`timeout 1200 sh -c 'until grep -q "^## Q<n> · <label> · ANSWERED" <file>; do sleep 20; done'`,
  or the skill's `ask.sh --wait`), then proceed with your default and say so in your final reply.

## 4. Deferred work

Everything you leave undone, find out of scope or work around goes on one line under
`## Deferred` in your file **and** in your final reply. The manager folds it into `ledger.md`;
nothing is dropped.

## 5. Your final reply

List the answers you received, the decisions you logged (count and anything notable), the contracts
you published and your deferred items.
