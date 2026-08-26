# /optimus:paper-init

Builds a self-contained paper-context bundle for implementing a research paper — pristine sources,
a faithful transcription, figures, annotated references, an implementation spec with the reported
results, open questions, and dataset provenance — under `paper/`, with datasets in a gitignored
`data/`. Stack-agnostic: it writes no implementation code and sets up no project stack (transient
fetch or extraction tooling may be pip-installed during the run; the final message names it). The
bundle is the launchpad for a later implementation run, typically `/optimus:gauntlet` judged
against the paper's reported results.

## When to run

- You're starting a paper implementation — especially one with no official code.
- Before a `/optimus:gauntlet` run whose quality bar is a paper's reported results.
- Adding a second paper to a project that already implements one (lands in `papers/<slug>/`).
- Refreshing a bundle after the paper or dataset situation changes.

## When NOT to run

- You just want to run the paper's official code — clone it and go.
- You want a summary of a paper, not an implementation.
- The implementation itself — that's `/optimus:gauntlet` (or `/optimus:tdd` for smaller work).

## Usage

    /optimus:paper-init https://arxiv.org/abs/2402.13521
    /optimus:paper-init 2402.13521
    /optimus:paper-init 10.3389/frai.2026.1828627
    /optimus:paper-init ./downloads/paper.pdf

With no argument, it asks for one. It ends with a summary of the bundle, the dataset status, and a
suggested tech stack (a suggestion only — nothing is installed), then points you at the next step:
commit the bundle, then start the implementation in a fresh conversation.

## What it produces

| Path | Contents |
|------|----------|
| `paper/README.md` | Bundle index: what this is, read-first order, status |
| `paper/source/` | Pristine originals (PDF + best machine-readable form) |
| `paper/source/metadata.json` | Provenance: bibliographic facts, license, code/dataset availability, exact re-acquisition record per file |
| `paper/paper.md` | Complete working transcription — LaTeX math, local figure links, inline tables |
| `paper/figures/` + `figures/README.md` | Best-resolution figure rasters, captioned, known defects flagged |
| `paper/references.md` | Every reference annotated with role, link, and fetch priority |
| `paper/spec.md` | What the paper specifies, §-referenced — ending in the targets the implementation is held to |
| `paper/open-questions.md` | What's undefined, blocking-first, with a `[verified]` convention for file-checked findings |
| `paper/dataset.md` | Dataset provenance, exact re-acquisition commands, verified counts, license terms (when the paper uses datasets) |
| `paper/reference-code/` | Vendored existing implementations (gitignored), when they exist — reference, never the implementation |
| `data/` | Downloaded datasets (gitignored; `data/README.md` stays committed) |

It also ensures `.gitignore` ignores `data/*` (with a `!data/README.md` exception) and
`paper/reference-code/`, and adds a short routing block to the root README when one exists.
Everything it writes is tool-agnostic — no file mentions this plugin or any AI product.

## How it works

1. **Resolves the paper** from your argument (URL, PDF path, DOI, or arXiv id).
2. **Acquires sources** redundantly into `paper/source/` and records exactly how each file was
   obtained, so a fresh clone can re-acquire everything.
3. **Writes the working forms** — transcription, figures, annotated references, spec, open
   questions — verifying against the local files whatever can be settled now.
4. **Checks for existing code** (Papers with Code, the paper's own links) and vendors it as
   reference material when found.
5. **Gets the datasets**: freely downloadable ones are fetched and verified; large downloads
   (GB-scale) ask first; blocked downloads (auth, license forms) get exact manual instructions
   in `paper/dataset.md` instead. A paper with no datasets skips this entirely.
6. **Sets up gitignore and routing** so data stays local and the bundle stays discoverable.
7. **Reports** the bundle, dataset status, and a suggested stack — then the next step.

It commits nothing; the final message tells you to commit the bundle before starting the
implementation run (the gauntlet loop reads its bar materials from committed paths).

## Notes

- Needs network access; paywalled papers stop with a plain explanation (or use a PDF you supply).
- In a multi-repo workspace, the bundle goes inside the target repo, not above it.
- Re-running on the same paper refreshes in place; it never moves or merges an existing bundle.
- Never touches `docs/specs/`, `docs/product/`, `.claude/CLAUDE.md`, or `.claude/.optimus-version`.
