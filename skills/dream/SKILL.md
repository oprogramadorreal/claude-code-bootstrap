---
description: >-
  Prunes and consolidates the project's auto-memory to keep it minimal — deletes stale, wrong,
  or redundant memories, merges overlapping ones into existing files, and trims the index.
  Strong bias against growth: never creates new memory files and never stores new facts.
  Verifies staleness against the current codebase, then presents the plan and asks before
  deleting. Requires Claude Code auto-memory; run periodically after heavy stretches of work.
disable-model-invocation: true
argument-hint: "[optional focus, e.g. a memory file or topic]"
---

# Dream — prune and consolidate auto-memory

A reflective pass over this project's auto-memory, biased toward shrinking it. Memory is context debt: every entry loads into future sessions whether it helps or not, stale entries actively mislead, and near-duplicates dilute the entries that matter. The best memory store is the smallest one that still changes what a future session does. This skill therefore only removes, merges, and tightens — capturing new facts is the job of regular sessions, not of a dream.

**Hard rules:**

- Never create a new memory file, and never store a fact that isn't already in a memory. Merges land in the strongest surviving file (renaming it to fit the consolidated content is fine); the file count must never increase.
- Touch nothing outside the memory directory and its index.
- Memory files are not git-tracked — deletion is irreversible, so nothing is deleted before the Step 3 confirmation.

If the user passed an argument, treat it as the focus: judge only the memories it names or covers.

## Step 1 — Inventory

The auto-memory section of your system prompt names the memory directory and defines the file format — it is the source of truth for both. If your context has no such section, tell the user auto-memory is not enabled for this project and stop; if the directory is missing or empty, report that there is nothing to consolidate and stop.

List the directory and read every top-level memory file (they are small by design), plus the index — `MEMORY.md` where it exists, otherwise the frontmatter `description` lines the harness assembles into an index at load time. Leave any `logs/` or `sessions/` subdirectories alone throughout: they are activity streams, not memories. Record the baseline footprint: memory file count and total bytes including the index.

## Step 2 — Judge every memory

Assign each file one verdict. The bar for KEEP is concrete: name the future-session decision this memory would change. If you can't, it is context cost with no return — delete it.

- **DELETE** — wrong (contradicted by the current codebase — verify by checking the files, flags, branches, or commands it names), superseded or marked historical-only, derivable from the repo itself (code, CLAUDE.md, git history), or scoped to work that is finished (a completed task, a resolved investigation, an expired date).
- **MERGE** — overlaps another memory: fold the surviving facts into the strongest existing file and delete the rest.
- **SHRINK** — the fact earns its place but the file pads it: keep the fact, the why, and how to apply it; cut the narrative of how it was learned, and delete any detail the current codebase now contradicts.
- **KEEP** — already minimal and still true.

The current repo state is the primary evidence. If a memory's staleness is suspected but unconfirmed, a narrow grep of the session transcripts (large JSONL files in the memory directory's parent — grep specific terms, never read whole files) may settle it. Never use transcripts or logs to mine new facts to store.

## Step 3 — Plan and confirm

Present the plan: each file with its verdict and a one-line reason, plus the projected footprint (files and bytes, before → after). If every verdict is KEEP, tell the user the memory is already tight and stop.

Then AskUserQuestion — header "Dream", question "Apply this memory consolidation plan?":

1. "Apply all" (Recommended)
2. "Abort" — change nothing

If the user answers via Other with exclusions, apply everything else.

## Step 4 — Execute

Apply merges and shrinks first, then deletions. While rewriting:

- Convert relative dates ("yesterday", "last week") to absolute dates so entries stay interpretable as time passes.
- Keep each surviving file's frontmatter `description` accurate and one line — it is the index entry future sessions see.
- Fix `[[links]]` that now point at deleted or renamed memories.
- Rebuild `MEMORY.md` (when it exists) with one line per surviving memory — it is an index, never a content dump.

## Step 5 — Report

Report the footprint before → after and what was deleted, merged, or shrunk, each with its one-line reason.

There is no follow-up skill; recommend running `/optimus:dream` again after the next stretch of heavy work.
