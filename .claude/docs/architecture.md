# Architecture

A Claude Code plugin whose skills are markdown, plus one orchestrator skill (`deep`) that dispatches base skills into fresh subagent contexts and drives them with a stdlib-only Python CLI under `scripts/harness_common/`.

The directory layout is discoverable; what follows is what reading it does not tell you.

## The deep loop

`references/orchestrator-loop-single.md` and `-paired.md` are the executable spec for the per-iteration body, and `references/schemas/*.schema.json` is the JSON contract. Those files are the definition — this doc does not restate the step sequence. The invariants they depend on but do not explain:

- **The bisect rebuilds each candidate state from the pre-iteration git snapshot**, never from the reported `pre_edit_content`/`post_edit_content`. A corrupt record can then only fail loudly as `skipped`; it can never tear the working tree.
- **`record-cycle` runs before `check-termination`** on the coverage target, because it pre-increments `cycle.current` and the cap check reads it. Swapping them silently runs one cycle too many.
- **The two soft exits are not archived.** `diminishing-returns` and `blocked` (the coverage target's stop gate) stay resumable on purpose; every other termination reason moves the progress file to `.done.json` so a stray `--resume` cannot reopen a finished run. The set is `RESUMABLE_TERMINATIONS` in `scripts/harness_common/constants.py` — one name, consumed by `cmd_final_report`, so narrowing this back to a single reason breaks the `--resume` each skill's SKILL.md promises.
- **All cross-iteration state lives in the progress file.** The orchestrator sees the subagent's terse JSON return, never its analysis trace — that is what keeps the loop from being bounded by one conversation's context.

## Contracts that fail loudly

- `references/schemas/` holds the harness JSON contracts. `test/harness-common/test_harness_schema.py` validates the golden fixtures under `test/harness-common/fixtures/` against them, round-trips them through `cli parse`, and checks that the harness-mode docs still point at both — change a schema and it fails until the fixtures follow.
- Every text-mode subprocess call passes `encoding="utf-8", errors="replace"`. A bare `text=True` uses the locale codec, which on a cp1252 Windows box silently truncates child output at the first non-decodable byte. `cli.main()` reconfigures its own stdout/stderr for the same reason. Enforced by `test/harness-common/test_encoding_policy.py`.
- `scripts/validate.sh` section 17 pins only strings a program parses or that cross a conversation boundary. Adding a pin for a heading one file reads from another is the anti-pattern that section exists to have removed.

## Agents and references

Two tiers, no inheritance: `agents/` holds standalone user-invocable agents, and `skills/<name>/agents/` holds prompt files scoped to one skill, each carrying its criteria inline. `deep` owns none — it dispatches base skills, which own the analysis agents. The dispatch-time path-substitution rule is in `references/agent-architecture.md`; the rest of the authoring rules are in `.claude/docs/skill-writing-guidelines.md`, which `validate.sh` enforces the two-level reference depth cap for.
