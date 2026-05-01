---
name: pr-reviewing
description: Runs a staged PR review using four pipeline subagents (high-level, behavioral, code, polish), then rolls findings into a short summary with must-change items, nits, and follow-on design notes. Use when reviewing a pull request end-to-end, chaining reviewer phases, or when the user asks for a full pipeline PR review.
disable-model-invocation: true
---

# PR reviewing (pipeline)

## Subagents (order)

Run these in sequence; each step consumes the previous step’s output plus the PR material as needed:

1. `pr-reviewer-high-level`
2. `pr-reviewer-behavioral`
3. `pr-reviewer-code`
4. `pr-reviewer-polish`

Agent definitions live under `.cursor/agents/` in this repository (`pr-reviewer-high-level.md`, etc.).

## Flow

1. **Gather PR context from GitHub** — description, linked issues, reviewers’ discussion if useful, and the diff (file list + patch). Include branch/base if it clarifies risk.
2. **High-level pass** — Invoke `pr-reviewer-high-level` with that context. If the verdict is blocked or needs realignment, stop and surface that before deeper passes (optionally resume after answers).
3. **Behavioral pass** — Feed the high-level output and focused diff into `pr-reviewer-behavioral`.
4. **Code pass** — Feed behavioral output (and prior summaries as needed) into `pr-reviewer-code`.
5. **Polish pass** — Feed prior outputs into `pr-reviewer-polish`.
6. **Summarize** — After all four responses, produce one consolidated summary using the three groups below (map pipeline output into them; dedupe and prioritize).

## Final summary — findings format

Group everything into exactly these three sections:

### Must-change

Items that must be addressed before merge (or treated as release blockers): correctness bugs, broken builds/tests, high-risk security issues, spec violations that cannot ship, etc.

### Suggestions (nits)

Nice-to-have improvements: style, naming, small refactors, optional polish — not crucial for merge.

### Larger design observations

Broader notes unlikely to land in this PR: coupling, layering, patterns to adopt later, architecture follow-ups for **future** stories. Frame as “consider when starting related work,” not as blocking this change unless phase 1 already flagged directional failure.
