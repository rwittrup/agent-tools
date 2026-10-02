---
name: creating-skills
description: How to create a skill after doing a task yourself, keeping knowledge in scripts and SKILL.md minimal. Use when asked to turn a task, setup, or workflow into a skill, or to improve an existing skill. Includes a SKILL.md template.
---

# Creating skills

A skill exists so the next run has no roadblocks. Capture what you did not know at the start; do not document what you could have figured out.

## Process

1. **Do the task yourself first.** Write down every roadblock: each thing you had to discover, each wrong guess, each time you asked the user for something you later found you could do alone.
2. **Sort each item.** Can code hold it (a command sequence, a readiness check, a parser, a template, validated arguments)? Put it in `scripts/` or `assets/`. Otherwise it goes in `SKILL.md`.
3. **Pick a home.** If an existing group (a subdirectory of the skills root with no SKILL.md) fits, nest the skill there; otherwise stay top-level. Do not invent a group for one skill, and do not move existing skills as a side effect.
4. **Scaffold:** copy `assets/SKILL.template.md` to `<skills root>/[group/]<name>/SKILL.md` and fill it in (naming rules are in its header comment).
5. **Write the scripts, then run them for real.** Test against the live environment, not just syntax; the first draft of a wait loop will have a bug. In your summary, say which paths ran and which were only syntax-checked.
6. **Write SKILL.md last, and short.** Delete anything a script already does or `--help` would say.

## Layout

The skills root is wherever the repo you are working in keeps its skills; do not hardcode a tool-specific path in a skill.

```
[group/]skill-name/
├── SKILL.md        required; frontmatter name must equal the directory name
├── scripts/        executable code the agent runs
├── references/     longer docs, read only when the task needs them
└── assets/         templates, data files, fixtures
```

- **Progressive disclosure.** Only `name` and `description` load at startup, so make the description say what and when. Keep SKILL.md under 500 lines (~5k tokens) and let it point to references/scripts that load on demand.
- **Relative, shallow paths** from the skill root. Whenever SKILL.md refers to a related file (anything in `scripts/`, `references/`, `assets/`, etc.), use its path relative to the skill root: `scripts/run.py`, `references/guide.md`. Never use absolute paths, tool-specific paths, or names without the directory. No chains of nested links.
- **Groups** are plain subdirectories with no SKILL.md of their own; Not every tool discovers nested skills. Verify the tool you use finds a nested skill before relying on it; until then, keep it top-level.

## What belongs in SKILL.md

Only knowledge a script can't hold:
- Facts that look wrong or are non-obvious ("`op whoami` says signed out when it isn't").
- Which results to trust and which to distrust.
- When a human is needed, and exactly what to ask them (scripts signal this with exit codes).
- A one-line pointer to each script and its arguments.

Not: step-by-step commands a script runs, general background, restated docs.

## Writing scripts

- **Small and focused.** One job each; compose them rather than growing a `do-everything.sh`.
- **Compose through pipes.** Data to stdout, human messages to stderr, meaningful exit codes. Read stdin when it makes sense; print paths or JSON lines another script can consume.
- **Parameterize.** Arguments for what varies, env vars for rarely-changed knobs, sensible defaults (e.g. newest run dir). Make them idempotent so rerunning is safe.
- **Fail with the next action.** On error print what failed and what to do; use a distinct exit code when the answer is "ask the user".

## Worked example: `setup-call-handler-tests`

Built this way: ran Rails, call-handler, and a scenario by hand, then moved the repeatable parts into `up.sh`, `down.sh`, `summarize.py`, and kept only the gotchas in SKILL.md. Honest gaps, as targets for the next pass: `up.sh` bundles Docker, AWS, Rails, and call-handler checks and would compose better as separate scripts (`ensure-docker`, `ensure-rails`, `ensure-call-handler`), and `summarize.py` takes a directory argument but not stdin. It could also nest under an `anet` group if one is created.
