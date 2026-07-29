# Contributing to optimus-claude

## Project structure

```
optimus-claude/
├── skills/
│   ├── init/                 # /optimus:init
│   ├── how-to-run/           # /optimus:how-to-run
│   ├── unit-test/            # /optimus:unit-test
│   ├── refactor/             # /optimus:refactor
│   ├── code-review/          # /optimus:code-review
│   ├── deep/                 # /optimus:deep (review | refactor | coverage)
│   ├── gauntlet/             # /optimus:gauntlet
│   ├── tdd/                  # /optimus:tdd
│   ├── pr/                   # /optimus:pr
│   ├── prompt/               # /optimus:prompt
│   ├── permissions/          # /optimus:permissions
│   ├── reset/                # /optimus:reset
│   ├── worktree/             # /optimus:worktree
│   ├── commit/               # /optimus:commit (default | suggest | branch)
│   ├── brainstorm/           # /optimus:brainstorm (design | scaffold)
│   ├── handoff/              # /optimus:handoff
│   └── jira/                 # /optimus:jira
└── scripts/harness_common/    # orchestrator CLI: cli.py plus findings, convergence,
                              # fixes, git, parser, progress, runner, reporting, constants
```

## Skill anatomy

Every skill follows the same layout:

```
skills/<skill-name>/
├── SKILL.md                  # Step-by-step instructions (the skill's "source code")
├── README.md                 # User-facing documentation
├── templates/                # YAML, markdown, and shell templates (optional)
│   ├── hooks/                # PostToolUse hook scripts
│   └── docs/                 # Documentation templates
├── agents/                   # Individual agent prompt files, one per agent plus shared-constraints.md (optional)
└── references/               # Technical reference docs consumed by the skill (optional)
```

**`SKILL.md`** is the key file. It starts with YAML frontmatter and contains the instructions Claude Code follows when the skill is invoked:

Frontmatter rules — including why there is no `name:` field — are in `.claude/docs/skill-writing-guidelines.md` under Structure, and `scripts/validate.sh` enforces them.

## Agent architecture

Two tiers, no inheritance. The rules — and the dispatch-time path-substitution requirement — are in `.claude/docs/skill-writing-guidelines.md` under Agents and in `references/agent-architecture.md`.

## Adding or modifying a skill

1. Create `skills/<skill-name>/SKILL.md` with YAML frontmatter and step-by-step instructions
2. Create `skills/<skill-name>/README.md` with user-facing documentation
3. Add templates and references as needed in subdirectories
4. Add the skill to the Skills section in the root `README.md`
5. Add the skill directory to the project-structure tree in this file — `scripts/validate.sh` asserts every `skills/` directory appears in both the root `README.md` and this tree

Follow the conventions visible in existing skills — study `skills/worktree/` for a minimal example or `skills/init/` for a full-featured one.

## Skill-authoring projects as a stack

`/optimus:init` detects **skill authoring** as a first-class stack alongside Python, Node, Rust, Go, UI frameworks, and so on. The detection signal is structural: a directory named `skills/`, `agents/`, `prompts/`, `commands/`, or `instructions/` at the repo root — and for monorepos, also at each detected subproject root — containing ≥2 subdirectories, every such subdirectory holding a file named `SKILL.md`, `AGENT.md`, `PROMPT.md`, `COMMAND.md`, or `INSTRUCTION.md` (case-insensitive). When detected, init installs `.claude/docs/skill-writing-guidelines.md` from its framework-agnostic template, and the shared `skills/init/references/constraint-doc-loading.md` reference automatically routes review/refactor skills to use that lens for markdown instruction files while keeping `coding-guidelines.md` as the lens for code files.

This means optimus supports Claude Code plugins (including optimus-claude itself), Codex skill repos, prompt libraries, custom agent frameworks, and any other project whose "source code" is markdown instructions authored for an AI agent.

The routing rule itself lives in `references/shared-agent-constraints.md` under Dual Lens; the template installed into skill-authoring projects is `skills/init/templates/docs/skill-writing-guidelines.md`.

## Plugin manifests

`.claude-plugin/plugin.json` carries the plugin identity and version; bump it for any meaningful change and update the version badge in `README.md` to match — `validate.sh` asserts the two agree on PR branches.

`.claude-plugin/marketplace.json` is how Claude Code discovers the plugin. Its `source` object accepts an optional `ref` to pin plugin code to a branch, tag, or SHA; that is only for the feature-branch testing flow below, and `validate.sh` fails while it is present.

## Testing

This plugin is mostly markdown-based. Testing is split into layers: fast structural checks, hook tests, and Python unit tests that run in CI, and slower skill execution tests that run locally.

**Before merging significant changes**, run the full skill test suite from a clean slate:

```shell
bash scripts/test-skills.sh --fresh --all --worktree
```

This removes existing fixtures, regenerates them, and runs all skill/fixture combinations end-to-end via `claude -p`. The `--worktree` flag runs everything in `.worktrees/skill-tests` inside the project directory so you can freely switch branches or edit files in the main tree while tests execute in the isolated worktree — and easily inspect the worktree from your IDE. See the subsections below for individual test layers and finer-grained options.

### Structural validation (CI)

Runs on every push and PR to master. Catches broken cross-references, syntax errors in templates, stale README entries, and other invariants.

```shell
bash scripts/validate.sh
```

Every check prints its own name as it runs, so the script is the list. Two invariants a contributor has to know before editing it: section 17 pins only strings a program parses or that cross a conversation boundary — never the wording of a skill's own instructions — and `.claude/hooks/restrict-paths.sh` must stay byte-identical to the template users install, with `HOOK_VERSION` bumped on every behavioural change so the SessionStart hook can spot projects running a stale copy.

### Hook execution tests (CI)

Unit tests for the session-start hook, formatter hooks, and the path-restriction hook — the hook scripts that run on user machines.

```shell
bash scripts/test-hooks.sh
```

Each assertion names itself in the output. The rationale for individual guards lives next to the code they protect — the `set -f` block in `collapse_dot_segments` is the one worth reading before touching path handling. Note that every verdict is scored from the hook's exit status as well as its output, so a hook that dies before printing scores CRASH rather than passing as a silent allow.

### Python unit tests (CI)

Unit tests for the Python code in the repo: the orchestrator CLI and its supporting modules under `scripts/harness_common/`, plus the `.claude/hooks/format-python.py` formatter hook.

**First-time setup:**

```shell
install.cmd                    # creates .venv and installs dev dependencies
```

**Run tests:**

```shell
test.cmd                       # run all Python unit tests
test-coverage.cmd              # run with coverage (HTML report in htmlcov/)
```

Or manually via pytest:

```shell
.venv\Scripts\activate
python -m pytest test/ -v
```

**Note:** The project uses `pyproject.toml` with `--import-mode=importlib` (kept for general robustness against same-name modules across test trees).

### Fixture generator (local)

Generates minimal project fixtures for testing skills. No dependencies installed — just enough files for project detection to work. Output goes to `test/fixtures/` (gitignored).

```shell
bash scripts/generate-fixtures.sh              # generate all fixtures
bash scripts/generate-fixtures.sh node python   # generate specific ones
```

Available fixtures: `node`, `python`, `go`, `rust`, `csharp`, `monorepo`, `empty`, `multi-repo`.

### Skill execution tests (local)

Runs skills against generated fixtures via `claude -p` (headless mode) and validates expected outputs against `test/expected-outputs.yaml`. Requires the `claude` CLI installed and authenticated (plan subscription or API key).

```shell
bash scripts/test-skills.sh                              # default: init + commit-suggest
bash scripts/test-skills.sh --skill init                 # test one skill
bash scripts/test-skills.sh --skill init --fixture node  # test one skill + one fixture
bash scripts/test-skills.sh --all                        # test all skill/fixture combinations
bash scripts/test-skills.sh --fresh --all                # clean + regenerate fixtures + test all
bash scripts/test-skills.sh --fresh --all --worktree     # same, in an isolated worktree
bash scripts/test-skills.sh --dry-run                    # show what would run without executing
```

Skills use `AskUserQuestion` for interactive decisions, which doesn't work in headless mode. The test script works around this by using `--append-system-prompt` to instruct Claude to make default choices automatically.

Not intended for CI — run locally before merging significant changes.

**`--worktree` flag:** Creates a detached git worktree at `.worktrees/skill-tests` from `HEAD`, runs the entire test suite there, and cleans up the worktree on success. On failure, the worktree is preserved for debugging — the script prints the path and a cleanup command. A subsequent run with `--worktree` automatically removes stale worktrees from previous failed runs. This snapshots the code at the current commit so you can freely switch branches, edit plugin files, or start new work in the main tree while the tests run — and the worktree stays visible in your IDE for easy inspection. Combine with any other flags (`--fresh`, `--all`, `--skill`, etc.).

**Adding expected outputs:** Edit `test/expected-outputs.yaml` to define what files a skill should create and what content they should contain. The format supports `files_exist`, `files_contain`, `files_not_exist`, `files_not_modified`, and `output_contains` assertions.

## Testing a feature branch

This plugin's marketplace catalog and plugin code live in the same repository. Claude Code fetches them in two separate steps, which means testing from a feature branch requires changes at both levels:

1. **Marketplace level** — the `#branch` suffix on the git URL tells Claude Code which branch to read `marketplace.json` from
2. **Plugin source level** — the `ref` field inside `marketplace.json` tells Claude Code which branch to fetch the plugin code from

Without both, `/plugin install` would still pull plugin code from the default branch even though the marketplace was loaded from a feature branch.

### Setup (on the feature branch)

Add a `ref` to `.claude-plugin/marketplace.json` pointing to your branch:

```json
"source": {
  "source": "url",
  "url": "https://github.com/oprogramadorreal/optimus-claude.git",
  "ref": "your-branch-name"
}
```

Commit the change to your feature branch. (This change must NOT be merged to master — remove it before merging.)

### Install

Remove the existing marketplace first, then re-add with the branch suffix:

```shell
/plugin marketplace remove optimus-claude
/plugin marketplace add https://github.com/oprogramadorreal/optimus-claude.git#your-branch-name
/plugin install optimus@optimus-claude
```

> **Note:** The `owner/repo#branch` shorthand is [not yet supported](https://github.com/anthropics/claude-code/issues/23551). Use the full `.git` URL with `#branch`.

### Return to production

To switch back to the stable release from master:

```shell
/plugin marketplace remove optimus-claude
/plugin marketplace add https://github.com/oprogramadorreal/optimus-claude.git
/plugin install optimus@optimus-claude
```

### Before merging

Remove the `ref` field from `marketplace.json` so that production installs continue to use the default branch.

### Local development (faster iteration)

For rapid iteration without pushing to GitHub, add the repo as a local marketplace:

```shell
git clone https://github.com/oprogramadorreal/optimus-claude.git
cd optimus-claude && git checkout your-branch-name
# In Claude Code:
/plugin marketplace add ./path/to/optimus-claude
/plugin install optimus@optimus-claude
```

No `ref` field is needed for local paths — Claude Code reads directly from the working tree.

## Version bumping

The version in `.claude-plugin/plugin.json` affects update behavior. If two refs have the same manifest version, Claude Code may treat them as identical and skip the update. Bump the version in `plugin.json` when publishing meaningful changes, and update the version badge in `README.md` to match.
