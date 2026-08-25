# optimus:dream

Prunes and consolidates your project's Claude Code auto-memory. Named after Claude Code's internal "dream" memory-consolidation pass, but inverted: where a dream normally also captures new memories, this skill only removes, merges, and tightens.

The premise: memory is context debt. Every memory file is loaded (via its index line) into future sessions whether it helps or not, stale entries actively mislead, and near-duplicates dilute the entries that matter. `/optimus:dream` keeps the store as small as it can be while still changing what future sessions do.

## Quick Start

This skill is part of the [optimus](https://github.com/oprogramadorreal/optimus-claude) plugin. See the [main README](../../README.md) for installation instructions.

**Run:** Type `/optimus:dream` in a project where Claude Code auto-memory is enabled. Pass an optional focus to narrow the pass, e.g. `/optimus:dream the deploy notes`.

## How It Works

1. **Inventory** — reads every memory file and the index; records the baseline footprint (file count, bytes).
2. **Judge** — each memory gets one verdict, tested against a concrete bar: *what future-session decision would this change?*
   - **Delete** — wrong (checked against the current codebase), superseded, derivable from the repo itself, or scoped to work that is finished
   - **Merge** — overlaps another memory; folded into the strongest existing file
   - **Shrink** — the fact stays, the padding goes
   - **Keep** — already minimal and still true
3. **Confirm** — presents the full plan with per-file reasons and the projected footprint, and asks before changing anything.
4. **Execute** — merges, shrinks, deletes; fixes cross-links and rebuilds the index.
5. **Report** — footprint before → after, with what changed and why.

## Guarantees

- **Never creates a new memory file** and never stores a new fact — the file count can only stay flat or shrink.
- **Always asks before deleting.** Memory files are not git-tracked, so deletion is irreversible — nothing is removed without your approval.
- **Touches nothing outside the memory directory.** Session logs and transcripts are read (narrowly) only as evidence of staleness, never modified.

## Requirements

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) 1.0.33+ (plugin support), with auto-memory enabled for the project

## License

[MIT](../../LICENSE)
