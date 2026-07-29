# optimus:gauntlet

A [Claude Code](https://docs.anthropic.com/en/docs/claude-code) skill that runs a **Gauntlet Loop**: give it an ambitious goal, and it turns that goal into a builder/critic improvement loop judged against a concrete quality bar — then keeps looping until the output beats the bar or you stop the run.

Instead of producing one decent result and stopping, the agent must keep comparing its work against a much higher standard that it cannot talk its way around.

## How It Works

1. **Choose the bar** — picks the strongest concrete reference an agent can actually inspect and compare its work against: real screenshots, a reference implementation, a test suite, best-in-class examples. If you supplied references, it uses the strongest; otherwise it proposes one.
2. **Write the gauntlet prompt** — a short, minimal prompt in the style of the bundled Claude-of-Duty exemplar: the goal and the bar, with the approach, decomposition, and round count left to the lead agent.
3. **Confirm** — shows you the bar and the prompt and asks for confirmation before starting, since gauntlet runs are long and spawn many subagents.
4. **Run** — the lead agent divides the goal into the smallest pieces that can be improved and judged independently. Each piece gets a builder and a separate critic with fresh context. The critic inspects the real output, blind-A/B-compares it with the bar, identifies the biggest remaining gap, and sends the work back for another round. A live progress page shows the work evolving.

## Principles

- **Goal over implementation** — you say what you want; the agent chooses how to make it.
- **A real bar** — "make it amazing" is not a bar; a concrete, inspectable reference is.
- **Agent-chosen decomposition** — the lead agent splits the work, not you.
- **Never let the builder grade itself** — critics get fresh context and the actual artifact, never the builder's history or explanation.
- **No fixed round count** — the loop ends when the output wins or you stop it.

## Quick Start

This skill is part of the [optimus](https://github.com/oprogramadorreal/optimus-claude) plugin. See the [main README](../../README.md) for installation instructions.

## Usage

- `/optimus:gauntlet <goal>` — proposes a bar, writes the prompt, confirms, runs
- `/optimus:gauntlet <goal> [possible references or quality bars]` — considers your references when choosing the bar

Examples:

```
/optimus:gauntlet finish porting all the BUILDING tools; match the desktop app's behavior as closely as possible and compare your work against the desktop app as you go
```

```
/optimus:gauntlet build a landing page for the product — the best landing pages in our category are the quality bar
```

For serious runs, enable ultracode first (`/effort` → ultracode) and consider isolating the run in a worktree (`/optimus:worktree`).

## When to Use

- Long-horizon build, port, or polish goals where "done" means matching a reference
- Work whose output can be inspected and compared: UIs, games, ports, writing, designs, backends with a reference implementation or test-suite bar

## When NOT to Use

- **Fixing existing code toward internal standards** — use `/optimus:deep` (review | refactor | coverage), the deterministic resumable fix loop
- **Lightweight "work until a condition holds"** — Claude Code's native `/goal`
- **Small, well-specified tasks** — `/optimus:tdd` or a plain prompt is cheaper

## Skill Structure

| File | Purpose |
|---|---|
| `SKILL.md` | Skill definition |
| `references/claude-of-duty-prompt.md` | The prompt-style exemplar gauntlet prompts are modeled on |

## Requirements

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) 1.0.33+ (plugin support)
- Subagent support; ultracode recommended for serious runs

## License

[MIT](../../LICENSE)
