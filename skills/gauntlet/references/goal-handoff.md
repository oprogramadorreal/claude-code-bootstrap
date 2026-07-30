# /goal handoff

The user chose "Copy as /goal prompt": execute nothing — hand the run to a
fresh session.

The emitted message starts with `/goal `. That prefix is the delivery
envelope, not part of the prompt — SKILL.md's ban on slash commands and
effort keywords still governs everything after it.

## Seed the progress page

Write `.claude/gauntlet-progress.md` now with the goal, the resolved bar, the
prompt, and an empty piece/round/verdict table — markdown even for visual work
on this path, because the table gets pasted into the conversation every turn;
the lead agent can keep a rendered page beside it. Anything too bulky for the
message lives here. The seeded page and the bar materials must exist in
whatever directory the new session opens — committed or copied into the
worktree, if the user made one.

## Build the message

One paste-ready message: `/goal ` followed by the same prompt you just showed
— never a rewrite or a second template — with only these deltas: constraint
docs as concrete repo paths that exist (`$CLAUDE_PLUGIN_ROOT` is undefined in
the fresh session); the project's test command, when it has one; an opening
instruction to read the progress page and confirm the bar materials open,
stopping and saying so if they do not; and a completion condition as the final
paragraph.

The condition, in a few lines: a small per-turn evaluator keeps the session
alive until the condition holds — it reads only the conversation and runs no
tools, a keep-alive floor, not a judge; the fresh-context critics stay the
only judges. So every turn ends by pasting the progress page's
piece/round/verdict table, each critic's latest verdict verbatim, and the tail
of the test output with its exit status. The goal is met ONLY when every piece
in the table has a verbatim "beats the bar" from its critic, the suite exits
0, and both are shown in the most recent turn. The table is never empty once
pieces are chosen, and no piece may be removed, renamed, or merged to satisfy
the condition; the lead agent's own assessment never counts. A plateau is not
completion: report it plainly each turn and keep working on the rest until the
user stops the goal — how to stop lives in their checklist, never in this
message. In a testless project drop the test clauses from condition and
evidence alike.

`/goal` caps the condition — everything after the prefix — at 4,000
characters. Target ~3,000, verified with a real count (`wc -c`), not an
estimate. Over budget, move detail to the seeded progress page; never trim the
condition or drop a critic guarantee.

## Print and stop

Print the message with this checklist above it, paste last:

- Claude Code ≥ 2.1.139 (`claude --version`), trust dialog accepted, hooks
  enabled — `/goal` is unavailable otherwise
- a NEW conversation in the directory the run will live in (the worktree, if
  one was made), progress page and bar materials present
- `/effort` → ultracode, and a deliberate permission mode — a goal changes no
  permissions, so without auto-accept the run stalls at its first prompt
- paste as one block, then run bare `/goal`: the status must show the full
  condition through the "met ONLY when" clause; if only the first paragraph
  registered, `/goal clear` and re-paste
- stop with `/goal clear` — Esc only interrupts the turn, the goal stays armed
  until cleared; bare `/goal` shows spend; the goal survives `--resume`;
  `/clear` kills it
- when the goal clears, review and commit (`/optimus:commit`, then
  `/optimus:code-review` in a fresh conversation)

Then stop. The fresh session owns the run.
