# Skill-writing guidelines for [PROJECT NAME]

This file governs the quality of **markdown instruction files** authored for an AI agent — skills, agents, prompts, commands, or instructions. Code files (Python, TypeScript, etc.) follow `coding-guidelines.md` instead. When reviewing, refactoring, or evaluating any file, route to the lens that matches the file's type: prose instruction files use the rules below; code files use `coding-guidelines.md`.

## The one principle

The agent is already capable. An instruction earns its context cost only for things the agent cannot infer: project-specific procedures, safety constraints, contracts between instruction files, and genuinely fragile sequences. Challenge every line — "would a capable model get this wrong without being told?" If not, delete it. Restating what the agent does natively degrades output by burying the rules that matter.

## Foundation

- **Follow existing patterns** — match the project's established instruction structure, frontmatter conventions, directory layout, and reference patterns. When introducing a new pattern, apply it consistently rather than leaving the project in a mixed state.
- **KISS** — the simplest instructions that meet current requirements. No steps or branches for hypothetical scenarios; no dead branches or redundant clarifications. Safety procedures, command allowlists, and user-approval gates are requirements — their detail is justified.
- **SRP** — one concern per instruction file, one action per step. Decompose a step that mixes concerns or abstraction levels. *Exception:* a one-time setup orchestrator may span concerns when its value depends on running all steps together.
- **Intention-revealing names** — file and directory names should convey purpose without reading the contents. Never `helper.md`, `utils.md`, `doc2.md`.
- **Pragmatic abstractions** — extract a shared reference when 2+ instruction files reuse a procedure. Never for hypothetical future reuse.

## Degrees of freedom

Match specificity to fragility, and treat it as a binary:

- **High freedom** (brief goals and criteria) — judgment tasks: review criteria, document structure, report content. **This is the default.**
- **Low freedom** (exact commands, no deviation) — fragile sequences: schema migrations, git surgery, data formats a script parses. Exact commands here are not bloat.

Over-specified step lists for judgment tasks are the most common failure mode in instruction authoring. Give one sensible default plus an escape hatch, not an option menu. State numeric bounds as guidance with a stated escape ("at most 3 questions — a maximum, not a target; skip them when intent is clear"), not as hard gates.

## What not to instruct

Current models already do these; telling them to do it again costs tokens and can make behavior worse.

- **Self-verification.** No "double-check your work", "verify the output before responding", "re-check your answer", or a final verification step bolted onto a task. Models of this generation verify and self-correct on their own, and these instructions compound into extra passes with no quality gain. What *is* worth instructing: a check against something external the model cannot self-assess — run the test suite, validate against the schema, diff the installed file against its template. That is a real gate; "look at it again" is not.
- **Verifying its own work with a subagent.** Delegation is for large, genuinely independent tracks of work. A second agent reviewing what the first just wrote has less context, not more.
- **Per-step narration.** Don't mandate a status line after every step. Describe the cadence you want instead: one line up front, updates on something important or a change of direction, outcome first at the end.
- **Reasoning echo.** Don't ask the agent to transcribe, narrate, or "show its thinking" as response text. Ask for conclusions and the rationale behind them; on some models an echo-your-reasoning instruction adds noise or triggers a refusal.
- **Exhaustive tool-use examples.** Worked examples of how to call a tool constrain the agent to the paths you happened to demonstrate. Describe the tool's purpose and its parameters instead; a well-named, well-typed interface teaches usage better than a sample transcript. Examples remain worth their cost for **output format** the agent must match exactly.

## Writing style

- Imperative steps, one term per concept throughout, no time-sensitive content.
- Keep instruction file bodies well under 500 lines; move detail to references.
- Output templates stay plain — headings, bold, blockquotes. No decorative emoji, no hand-rolled "[Step N/M]" progress lines.
- Calibrate written deliverables: when an instruction produces a document, say what length the content warrants. Models of this generation write long by default, and unbounded output fills with filler sections and redundant summaries.

## Description quality (frontmatter)

- Descriptions state both WHAT the instruction does and WHEN to use it — that is how an agent selects among many.
- Third person, present tense: "Generates commit messages by analyzing diffs", not "I can help you generate…".
- Lead with the differentiating verb phrase. Declare side effects (writes files, commits, pushes) and hard prerequisites.
- Keep feature inventories out — those belong in a README. A description that lists everything truncates before it reaches what distinguishes it.
- If your instructions are only ever invoked explicitly, the description's real audience is a human scanning a truncating menu; concise beats keyword-rich.

## Progressive disclosure

- Load only the description at startup; the full instruction file on invocation; reference files only when the execution path needs them.
- An instruction's real cost is the main file **plus every reference it loads unconditionally** — budget the sum. Gate conditional reads behind a cheap inline test ("if the directory has no `.git/`, read …").
- A reference that would load on every run belongs inline. Reference depth: two levels maximum (INSTRUCTION → A → B). Flatten deeper chains. Never allow circular references.
- Reference files over 100 lines start with a table of contents.

## Structure and sharing

- Group instruction files in conventional directories (`skills/`, `agents/`, `prompts/`, `commands/`, `instructions/`) — whichever your framework uses; detailed material goes under `references/`.
- Each sub-agent prompt lives in its own file — never inline them in the main instruction.
- When a procedure serves 2+ instructions, extract it to a reference owned by one canonical file; consumers read it and apply their own policy. Two files that each declare the other a copy is a maintenance trap, not sharing.
- Prefer a reference implementation, a schema, a template file, or a test over prose that describes a format. A parsed data contract belongs in a schema with a fixture, not in a paragraph.

## Evaluation

Write minimal instructions, test on real tasks, and iterate on observed behavior — whether the agent misses references, over-relies on one section, or ignores bundled files. Don't document imagined problems. Where quality is judgeable, a rubric the agent can check against carries more signal than prose describing good output.

## Anti-patterns

- Over-explaining concepts the agent knows; defensive branches for hypothetical scenarios; dead steps.
- Option menus where a default plus an escape hatch suffices.
- Windows-style paths — always forward slashes (`references/guide.md`).
- Inconsistent terminology — don't mix "field"/"box"/"element" for one concept.
- Drive-by improvements — when fixing an instruction, change only what the task requires.
- Verbatim-pinned prose — never make CI assert the exact wording of model-facing instructions, except for genuine two-sided contracts (a heading one file emits and another parses).

## Documentation

Every instruction has a user-facing description or README covering what it does and when to use it. After any change, verify that description and any referring index still match actual behavior.
