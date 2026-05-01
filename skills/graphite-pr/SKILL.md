---
name: graphite-pr
description: Opens and updates GitHub PRs via Graphite (gt submit) with bodies that follow the pr-formatting template and CI title rules. Use when shipping a branch or stack, running gt submit, filling PR descriptions after Graphite creates drafts, or aligning PR text with validation artifacts and Linear.
allowed-tools:
  - "Bash(gt *)"
  - "Bash(git *)"
  - "Bash(gh pr *)"
---

# Graphite PR workflow

Compose **Graphite CLI steps** with **PR description formatting** from the repository skills below.

## Read first

1. **Graphite mechanics** — Read `.cursor/skills/graphite/SKILL.md` for `gt create`, `gt modify`, `gt submit`, `gt ls`, `gt restack`, branch naming, untracked branches, stack parentage, troubleshooting.
2. **PR body shape** — Read `.agents/skills/pr-formatting/SKILL.md` for the full template (Summary, Context, Changes, Validation, Stack, Linear), rules, and frontend-only Validation variant.

Do not invent a different PR outline; use the pr-formatting template and rules.

## End-to-end flow

1. **Branch and commits** — Follow graphite skill: stage changes, `gt create … -m "…"` (or `gt modify`), correct stack parent (`main`), `gt ls` to confirm.
2. **Draft body** — Before or right after submit, write the description using the pr-formatting template. **Validation** must be present (copy from validation artifact when one exists; use pr-formatting’s frontend section for frontend-only PRs). **Stack** always filled (even “1 of 1”).
3. **Submit** — `gt submit --no-interactive` (graphite skill).
4. **Titles and bodies (required)** — GitHub/pr-lint expects allowed title formats per root `AGENTS.md` (e.g. `[TICKET-123] description`, `[HF]`, `[BUMP]`, `Bump`). After PRs exist:
   - **Never** use Bash heredocs for markdown bodies (escaping breaks content). Write the body to a file (e.g. `/tmp/pr-body.md`) with the editor `Write` tool, then:
   - `gh pr edit <NUMBER> --title "[TICKET-123] Short description" --body-file /tmp/pr-body.md`
   - Repeat per PR in the stack; each body matches pr-formatting and reflects that PR’s scope and stack position.

## Quick checklist

- [ ] Title matches `AGENTS.md` / CI rules.
- [ ] Body has Summary, Context, Changes, Validation, Stack, Linear (per pr-formatting).
- [ ] Summary is not just the ticket title; Validation is not omitted.
- [ ] Stack section lists position, depends-on, blocks.

## Related

- Root **PR title** and workflow: `AGENTS.md`
- Stacked PR rationale and splitting: graphite skill (“What Makes a Good PR?”)
