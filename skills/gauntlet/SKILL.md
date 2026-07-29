---
description: >-
  Runs a Gauntlet Loop: turns an ambitious goal and optional quality references
  into a minimal builder/critic prompt judged against a concrete comparison
  bar, confirms with the user, then executes it as the lead agent until the
  output beats the bar or the user stops the run. Use for long-horizon goals
  judged against an inspectable reference. Long-running; spawns many subagents
  and edits project files.
disable-model-invocation: true
argument-hint: "<goal> [possible references or quality bars]"
---

# Gauntlet

Turn an ambitious goal into a builder/critic improvement loop judged against a
concrete quality bar, and run that loop until the output wins or the user
stops it.

The user's arguments are the goal, plus any references or quality bars they
mentioned. If no goal was given, ask for one.

Read `$CLAUDE_PLUGIN_ROOT/skills/gauntlet/references/claude-of-duty-prompt.md`
— the reference prompt that gauntlet prompts are modeled on.

## 1. Choose the bar

Choose the strongest concrete bar that an agent can actually inspect and
compare its work against. If the user has not supplied one, propose a useful
comp or measurement that plays the same role for this task that real Call of
Duty screenshots played for the Claude-of-Duty game — the game that reference
prompt produced. Explain the bar in one sentence.

## 2. Write the gauntlet prompt

Write a short prompt in the style of that reference prompt (minimal is better
here — the lead agent decides the specifics).

Give the lead agent the goal and the bar, but let it choose the approach. Tell
it to divide the goal into the smallest pieces that can be improved and judged
independently. For each important piece, it should fan out a builder and a
separate critic with fresh context.

Each critic must inspect the real output, compare it directly with the bar —
using a blind A/B comparison when possible — identify the biggest remaining
gap, and send it back for another round. Keep looping until the output wins or
the user stops the run.

Have the lead agent maintain a simple live progress page that shows the work
evolving over time.

Have it use subagents and ultracode. Do not prescribe the architecture, exact
decomposition, or a fixed number of rounds. Keep the final prompt short, just
like the reference.

## 3. Confirm and run

Show the user the bar and the prompt. If ultracode is not enabled, note that
it is recommended for gauntlet runs (`/effort` → ultracode). Then use
`AskUserQuestion` — header "Gauntlet", question confirming the start of a
long-running multi-agent run — with options "Start the run" and "Adjust
first". Apply requested adjustments and ask again.

On approval, execute the prompt yourself as the lead agent. There is no
arbitrary final round: the run ends when the output beats the bar or the user
stops it.

If the run stops with uncommitted work, recommend `/optimus:commit` in this
conversation.
