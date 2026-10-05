COMMUNICATION (worker protocol v2): label `<label>`, run id `<run-id>`, protocol directory `<dir>`.
First read `<dir>/PROTOCOL.md` and follow it, and check that `<dir>/RUN.md` names run id
`<run-id>` with status ACTIVE; if it does not, stop. Write only `<dir>/workers/<label>.md` and
`<dir>/contracts/<label>.md`, and only by appending.
- Decide by the sources of authority in PROTOCOL.md section 1; log each decision as a `D<n>:` line.
- Read `<dir>/contracts/` and `<dir>/answers/<label>.md` before each commit.
- Escalate only user-level, contradictory or blocking questions, with
  `sh "<scripts>/ask.sh" "<dir>" <label> "<context>" "<question>" "<options>" "<default>" [--blocked]`
  (keep the quotes: the paths may contain spaces).
- If blocked, finish everything else and end with a BLOCKED result instead of waiting.
  <Keep the next line only if you will answer within that time; otherwise delete it.>
  You may wait up to <seconds> seconds for an answer: add `--wait <seconds>` to `ask.sh`.
- Log everything you leave undone as an `F<n>:` line.
- Never message the manager in chat, and never put secrets in protocol files.
- Finish by appending `## Result` (PROTOCOL.md section 5).
